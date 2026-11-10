struct Preset: Equatable {
    let name: String
    let preamp: Float
    /// dB for the 31, 62, 125, 250, 500, 1K, 2K, 4K, 8K, 16K bands.
    let gains: [Float]

    static let flat = Preset(name: "Flat", preamp: 0, gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

    static let all: [Preset] = [
        flat,
        Preset(name: "Bass Boost", preamp: -5, gains: [6, 6, 5, 3, 1, 0, 0, 0, 0, 0]),
        Preset(name: "Laptop Bass", preamp: -5, gains: [0, 3, 6, 5, 2, 0, 0, 0, 1, 1]),
        Preset(name: "Deep Bass", preamp: -7, gains: [8, 7, 4, 1, 0, 0, 0, 0, 0, 0]),
        Preset(name: "Bass & Treble", preamp: -4, gains: [5, 5, 3, 1, -1, -2, 0, 2, 4, 5]),
        Preset(name: "Loudness", preamp: -3, gains: [4, 4, 2, 0, -1, -1, 0, 1, 3, 3]),
        Preset(name: "Rock", preamp: -3, gains: [4, 3, 2, 0, -1, -1, 1, 2, 3, 3]),
        Preset(name: "Pop", preamp: -3, gains: [-1, 1, 3, 4, 3, 0, -1, -1, 0, 1]),
        Preset(name: "Hip-Hop", preamp: -5, gains: [6, 6, 3, 1, -1, -1, 1, 0, 1, 2]),
        Preset(name: "Electronic", preamp: -4, gains: [5, 4, 1, 0, -2, 1, 0, 1, 4, 4]),
        Preset(name: "Dance", preamp: -5, gains: [6, 5, 2, 0, 0, -2, -2, 0, 2, 3]),
        Preset(name: "Jazz", preamp: -2, gains: [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]),
        Preset(name: "Classical", preamp: -2, gains: [3, 3, 2, 1, 0, 0, -1, 0, 2, 3]),
        Preset(name: "Acoustic", preamp: -3, gains: [3, 3, 2, 1, 1, 1, 2, 2, 2, 1]),
        Preset(name: "Vocal", preamp: -3, gains: [-2, -2, -1, 1, 3, 4, 3, 2, 0, -1]),
        Preset(name: "Treble Boost", preamp: -5, gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
        Preset(name: "Late Night", preamp: 0, gains: [-3, -2, 0, 1, 2, 2, 1, 0, -1, -2]),
    ]
}
