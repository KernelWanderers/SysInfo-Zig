const std = @import("std");

// Testing C imports.
pub fn main() !void {
    const c = @cImport({
        @cInclude("IOKit/IOKitLib.h");
    });

    const dict = c.IOServiceMatching("IOPCIDevice");

    const stdout = std.io.getStdOut().writer();

    try stdout.print("{s}\n", .{dict});
}