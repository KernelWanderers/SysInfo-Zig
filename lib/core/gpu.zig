const GPUData = extern union(enum) {
    /// The ACPI path of this GPU device,
    /// if possible to construct.
    ///
    /// Aliases: `acpiPath`
    ACPI: ?[]const u8,

    /// The ACPI path of this GPU device,
    /// if possible to construct.
    ///
    /// Aliases: `acpiPath`
    acpiPath: ?[]const u8,

    /// The codename of this GPU.
    ///      For the time being, NVidia/AMD GPus are only supported.
    ///
    /// Sometimes, this data will not be reliable.
    /// If you wish to be 100% certain, I highly advise you to
    /// implement your own logic to determine this.
    ///
    /// The current implementation simply uses the data from one of my other repositories,
    /// which has this data hard-coded. It's not perfect, but it's better than nothing.
    ///
    /// Sources:
    ///  - [AMD List](https://github.com/iabtw/OCSysInfo/tree/main/src/uarch/gpu/amd_gpu.json)
    ///  - [NVidia List](https://github.com/iabtw/OCSysInfo/tree/main/src/uarch/gpu/nvidia_gpu.json)
    ///
    /// Special thanks to:
    ///  - [khronokernel](https://github.com/khronokernel) — for allowing us to copy over their NVidia device IDs for Curie, Tesla, Fermi & Kepler cards in the first place.
    ///  - [Flagers](https://github.com/flagersgit) — for providing us with the AMD & NVidia GPU device IDs data.
    codename: []const u8,

    /// The device ID of this GPU device in decimal.
    ///
    /// The valid representation should be converted to hex.
    deviceID: u32,

    /// The vendor ID of this GPU device in decimal.
    ///
    /// The valid representation should be converted to hex.
    vendorID: u32,

    /// The model of this GPU.
    model: []const u8,

    /// The PCI path of this GPU device,
    /// if possible to construct.
    ///
    /// Aliases: `pciPath`
    PCI: ?[]const u8,

    /// The PCI path of this GPU device,
    /// if possible to construct.
    ///
    /// Aliases: `PCI`
    pciPath: ?[]const u8,

    /// The total amount of video RAM (VRAM) available for this GPU.
    ///
    /// Sometimes this won't be available.
    /// Most notably, in cases of integrated graphics, where the VRAM is
    /// dynamically allocated from system memory.
    vram: u32,
};