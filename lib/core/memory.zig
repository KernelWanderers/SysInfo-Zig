const MemoryModuleSlot = struct {
    // The bank index this RAM module is located in.
    bank: u32,

    // The specific channel index this RAM module is located in,
    // relative to its bank location.
    channel: u32
};

const MemoryModule = struct {
    // The size of this RAM module.
    size: u32,

    // The slot this RAM module is located in.
    slot: MemoryModuleSlot,

    // The serial number of this RAM module.
    // Aliases: `serialNumber`
    sn: *const []u8,

    // The serial number of this RAM module.
    // Aliases: `sn`
    serialNumber: *const []u8,

    // The part number of this RAM module.
    partNumber: *const []u8,

    // The type of this RAM module.
    // For example, DDR4, DDR3, DDR2, etc.
    module_type: *const []u8,

    // The manufacturer of this RAM module.
    manufacturer: *const []u8
};

const RAMData = struct {
    // The number of RAM modules in this data structure.
    count: u32,

    // A slice of memory modules available..
    modules: *const MemoryModule,

    // The total size of RAM installed.
    totalSize: u32
};