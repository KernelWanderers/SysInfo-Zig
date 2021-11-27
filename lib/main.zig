const std = @import("std");
const wmi = @import("./core/wmi.zig");

pub fn main() !void {
    try wmi.queryCPU();
    try wmi.queryGPU();
}
