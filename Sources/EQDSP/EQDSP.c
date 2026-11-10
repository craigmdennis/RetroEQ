#include "EQDSP.h"

#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

// ISO octave bands, the classic 10-band graphic EQ layout.
static const float kBandFreqs[EQ_BAND_COUNT] = {
    31.25f, 62.5f, 125.0f, 250.0f, 500.0f, 1000.0f, 2000.0f, 4000.0f, 8000.0f, 16000.0f
};
static const double kBandQ = 1.41; // ~one octave wide

#define MAX_CHANNELS 2
#define MAX_REFS 64

typedef struct {
    double b0, b1, b2, a1, a2;
} Coeffs;

struct EQEngine {
    // Written by the UI thread, read by the audio thread.
    _Atomic float gains[EQ_BAND_COUNT];
    _Atomic float preampDB;
    _Atomic double sampleRate;
    _Atomic unsigned int version;
    _Atomic int resetRequested;
    _Atomic float peakL, peakR;

    // Audio-thread only.
    unsigned int seenVersion;
    Coeffs coeffs[EQ_BAND_COUNT];
    double z1[MAX_CHANNELS][EQ_BAND_COUNT];
    double z2[MAX_CHANNELS][EQ_BAND_COUNT];
    double preampTarget;
    double preampCurrent;
};

// RBJ audio-EQ-cookbook peaking filter.
static Coeffs design_peak(double freq, double gainDB, double fs) {
    Coeffs c = {1, 0, 0, 0, 0};
    if (fabs(gainDB) < 0.01 || fs <= 0 || freq >= fs * 0.49) return c;
    double A = pow(10.0, gainDB / 40.0);
    double w0 = 2.0 * M_PI * freq / fs;
    double cw = cos(w0), alpha = sin(w0) / (2.0 * kBandQ);
    double a0 = 1.0 + alpha / A;
    c.b0 = (1.0 + alpha * A) / a0;
    c.b1 = (-2.0 * cw) / a0;
    c.b2 = (1.0 - alpha * A) / a0;
    c.a1 = (-2.0 * cw) / a0;
    c.a2 = (1.0 - alpha / A) / a0;
    return c;
}

EQEngine *eq_create(void) {
    EQEngine *eq = calloc(1, sizeof(EQEngine));
    atomic_store(&eq->sampleRate, 48000.0);
    atomic_store(&eq->version, 1);
    atomic_store(&eq->resetRequested, 1);
    return eq;
}

void eq_destroy(EQEngine *eq) { free(eq); }

void eq_set_sample_rate(EQEngine *eq, double sampleRate) {
    atomic_store(&eq->sampleRate, sampleRate);
    atomic_fetch_add(&eq->version, 1);
}

void eq_set_band_gain(EQEngine *eq, int band, float gainDB) {
    if (band < 0 || band >= EQ_BAND_COUNT) return;
    atomic_store(&eq->gains[band], gainDB);
    atomic_fetch_add(&eq->version, 1);
}

void eq_set_preamp(EQEngine *eq, float gainDB) {
    atomic_store(&eq->preampDB, gainDB);
    atomic_fetch_add(&eq->version, 1);
}

void eq_request_reset(EQEngine *eq) { atomic_store(&eq->resetRequested, 1); }

void eq_read_peaks(EQEngine *eq, float *left, float *right) {
    *left = atomic_exchange(&eq->peakL, 0.0f);
    *right = atomic_exchange(&eq->peakR, 0.0f);
}

float eq_band_frequency(int band) {
    return (band >= 0 && band < EQ_BAND_COUNT) ? kBandFreqs[band] : 0.0f;
}

double eq_response_db(const float *gainsDB, double freq) {
    const double fs = 48000.0;
    double w = 2.0 * M_PI * freq / fs;
    double total = 0.0;
    for (int b = 0; b < EQ_BAND_COUNT; b++) {
        Coeffs c = design_peak(kBandFreqs[b], gainsDB[b], fs);
        double nr = c.b0 + c.b1 * cos(w) + c.b2 * cos(2 * w);
        double ni = -(c.b1 * sin(w) + c.b2 * sin(2 * w));
        double dr = 1.0 + c.a1 * cos(w) + c.a2 * cos(2 * w);
        double di = -(c.a1 * sin(w) + c.a2 * sin(2 * w));
        total += 10.0 * log10((nr * nr + ni * ni) / (dr * dr + di * di));
    }
    return total;
}

static void update_params(EQEngine *eq) {
    if (atomic_exchange(&eq->resetRequested, 0)) {
        memset(eq->z1, 0, sizeof(eq->z1));
        memset(eq->z2, 0, sizeof(eq->z2));
        eq->preampCurrent = 0.0; // fade in from silence
    }
    unsigned int v = atomic_load(&eq->version);
    if (v == eq->seenVersion) return;
    eq->seenVersion = v;
    double fs = atomic_load(&eq->sampleRate);
    for (int b = 0; b < EQ_BAND_COUNT; b++) {
        eq->coeffs[b] = design_peak(kBandFreqs[b], atomic_load(&eq->gains[b]), fs);
    }
    eq->preampTarget = pow(10.0, atomic_load(&eq->preampDB) / 20.0);
}

// Gentle soft-knee limiter so bass boosts saturate smoothly instead of hard clipping.
static inline float soft_clip(double x) {
    const double t = 0.85;
    double ax = fabs(x);
    if (ax <= t) return (float)x;
    double y = t + (1.0 - t) * tanh((ax - t) / (1.0 - t));
    return (float)copysign(y, x);
}

typedef struct {
    float *p;
    UInt32 stride;
} ChanRef;

static int collect_channels(const AudioBufferList *abl, ChanRef *refs, UInt32 *framesOut) {
    int n = 0;
    UInt32 frames = UINT32_MAX;
    if (abl) {
        for (UInt32 b = 0; b < abl->mNumberBuffers; b++) {
            const AudioBuffer *buf = &abl->mBuffers[b];
            UInt32 nch = buf->mNumberChannels;
            if (!buf->mData || nch == 0) continue;
            UInt32 f = buf->mDataByteSize / (UInt32)(sizeof(float) * nch);
            if (f < frames) frames = f;
            for (UInt32 c = 0; c < nch && n < MAX_REFS; c++) {
                refs[n].p = (float *)buf->mData + c;
                refs[n].stride = nch;
                n++;
            }
        }
    }
    *framesOut = n ? frames : 0;
    return n;
}

OSStatus eq_ioproc(AudioObjectID inDevice,
                   const AudioTimeStamp *inNow,
                   const AudioBufferList *inInputData,
                   const AudioTimeStamp *inInputTime,
                   AudioBufferList *outOutputData,
                   const AudioTimeStamp *inOutputTime,
                   void *inClientData) {
    (void)inDevice; (void)inNow; (void)inInputTime; (void)inOutputTime;
    EQEngine *eq = (EQEngine *)inClientData;
    if (!eq || !outOutputData) return noErr;

    for (UInt32 b = 0; b < outOutputData->mNumberBuffers; b++) {
        AudioBuffer *buf = &outOutputData->mBuffers[b];
        if (buf->mData) memset(buf->mData, 0, buf->mDataByteSize);
    }

    ChanRef outs[MAX_REFS], ins[MAX_REFS];
    UInt32 outFrames, inFrames;
    int nOut = collect_channels(outOutputData, outs, &outFrames);
    int nIn = collect_channels(inInputData, ins, &inFrames);
    if (nOut == 0 || nIn == 0) return noErr;

    update_params(eq);

    // The tap's stereo stream comes after any input streams of the output device itself.
    ChanRef inL = ins[nIn >= 2 ? nIn - 2 : 0];
    ChanRef inR = ins[nIn - 1];
    UInt32 frames = outFrames < inFrames ? outFrames : inFrames;
    if (frames == 0) return noErr;

    double pre = eq->preampCurrent;
    double step = (eq->preampTarget - pre) / (double)frames;
    float pkL = 0.0f, pkR = 0.0f;

    for (UInt32 i = 0; i < frames; i++) {
        pre += step;
        double s[2] = { inL.p[i * inL.stride] * pre, inR.p[i * inR.stride] * pre };
        for (int ch = 0; ch < 2; ch++) {
            double x = s[ch];
            double *z1 = eq->z1[ch], *z2 = eq->z2[ch];
            for (int b = 0; b < EQ_BAND_COUNT; b++) {
                const Coeffs *c = &eq->coeffs[b];
                double y = c->b0 * x + z1[b];
                z1[b] = c->b1 * x - c->a1 * y + z2[b];
                z2[b] = c->b2 * x - c->a2 * y;
                x = y;
            }
            s[ch] = x;
        }
        float l = soft_clip(s[0]), r = soft_clip(s[1]);
        if (fabsf(l) > pkL) pkL = fabsf(l);
        if (fabsf(r) > pkR) pkR = fabsf(r);
        if (nOut == 1) {
            outs[0].p[i * outs[0].stride] = 0.5f * (l + r);
        } else {
            outs[0].p[i * outs[0].stride] = l;
            outs[1].p[i * outs[1].stride] = r;
        }
    }
    eq->preampCurrent = eq->preampTarget;

    // Flush denormals in the filter history.
    for (int ch = 0; ch < 2; ch++)
        for (int b = 0; b < EQ_BAND_COUNT; b++) {
            if (fabs(eq->z1[ch][b]) < 1e-25) eq->z1[ch][b] = 0;
            if (fabs(eq->z2[ch][b]) < 1e-25) eq->z2[ch][b] = 0;
        }

    if (pkL > atomic_load(&eq->peakL)) atomic_store(&eq->peakL, pkL);
    if (pkR > atomic_load(&eq->peakR)) atomic_store(&eq->peakR, pkR);
    return noErr;
}
