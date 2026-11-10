#ifndef EQDSP_H
#define EQDSP_H

#include <CoreAudio/CoreAudio.h>

#define EQ_BAND_COUNT 10

#pragma clang assume_nonnull begin

typedef struct EQEngine EQEngine;

EQEngine *eq_create(void);
void eq_destroy(EQEngine *eq);

/// Parameter setters. Safe to call from any thread while audio is running.
void eq_set_sample_rate(EQEngine *eq, double sampleRate);
void eq_set_band_gain(EQEngine *eq, int band, float gainDB);
void eq_set_preamp(EQEngine *eq, float gainDB);
/// Clears filter history and fades in on the next render.
void eq_request_reset(EQEngine *eq);

/// Peak output levels (linear, 0...1+) since the previous call.
void eq_read_peaks(EQEngine *eq, float *left, float *right);

/// Diagnostics: measures the live input and output magnitude at one frequency.
/// eq_probe_start clears the accumulators; eq_probe_read returns their magnitudes.
void eq_probe_start(EQEngine *eq, double freq);
void eq_probe_read(EQEngine *eq, double *inMag, double *outMag);

float eq_band_frequency(int band);

/// Combined magnitude response of the band filters at `freq` (48 kHz reference), in dB.
double eq_response_db(const float *gainsDB, double freq);

/// Core Audio IOProc. Pass the EQEngine pointer as client data.
OSStatus eq_ioproc(AudioObjectID inDevice,
                   const AudioTimeStamp *_Nonnull inNow,
                   const AudioBufferList *_Nonnull inInputData,
                   const AudioTimeStamp *_Nonnull inInputTime,
                   AudioBufferList *_Nonnull outOutputData,
                   const AudioTimeStamp *_Nonnull inOutputTime,
                   void *_Nullable inClientData);

#pragma clang assume_nonnull end

#endif
