const CPUData = struct {
    // The base clock speed of this CPU.
    //
    // Do note that this data may or may not be accurate,
    // depending on the current system in use.
    //
    // For example, macOS provides a neat to check this:
    // `sysctl hw.cpufrequency`
    baseClockSpeed: u32,

    // The codename of this CPU.
    //      For the time being, Intel/AMD CPUs are only supported.
    //
    // Sometimes, this data will not be reliable.
    // Usually, in cases of older CPUs, or if the machine this is
    // being ran on has not internet connection.
    //
    // If you wish to be 100% certain, it's best to implement your own logic
    // to determine this, or hardcode every model in existence (I do not recommend doing this.)
    //
    // The current implementation scrapes [Intel's ARK](https://ark.intel.com) for Intel's CPUs,
    // and [AMD's page](https://amd.com) for AMD's CPUs.
    //
    // Special thanks to [CorpNewt](https://github.com/CorpNewt) who originally implemented the
    // logic for scraping AMD's site.
    codename: *const []u8,

    // The number of cores of this CPU.
    cores: u32,

    // The current clock speed of this CPU.
    currentClockSpeed: u32,

    // The available instruction sets for this CPU.
    //
    // Here, we can simply take advantage of Zig's
    // built-in instruction set detection.
    //
    // Aliases: `flags`
    instructionSets: *const []const []u8,

    // The available instruction sets for this CPU.
    //
    // Here, we can simply take advantage of Zig's
    // built-in instruction set detection.
    //
    // Aliases: `instructionSets`
    flags: *const []const []u8,

    // The maximum clock speed of this CPU.
    maxClockSpeed: u32,

    // The microarchitecture of this CPU.
    //
    // Some examples being:
    //      - Intel
    //          - Haswell
    //          - Kaby Lake
    //          - Skylake
    //      - AMD
    //          - Zen
    //          - Zen+ (Zen+ is a Zen variant with a larger L1 cache.)
    //          - Zen2
    microarchitecture: *const []u8,

    // The model of this CPU.
    model: *const []u8,

    // The number of logical processors (threads) of this CPU.
    threads: u32,
};
