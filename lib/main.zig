const std = @import("std");
const WMI = @import("./core/wmi.zig").SysInfoWMI;
const WindowsHM = @import("./managers/hardware/OS/windows/windows.zig").HardwareManager;
const Foundation = @import("win32").foundation;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    const windowsHM: WindowsHM = .{};

    var list = windowsHM.getGPUInfo(&gpa.allocator);

    defer list.?.deinit();

    var i: usize = 0;

    while (i < list.?.items.len) : (i += 1) {
        var itr = list.?.items[i].iterator();

        while (itr.next()) |entry| {
            var key = entry.key_ptr.*;
            var value = entry.value_ptr.*;

            switch (value) {
                .String => |val| {
                    std.debug.print("Key: {s} | Value: {s}\n", .{ key, val });
                },
                else => |val| std.debug.print("Key: {s} | Value: {s}\n", .{ key, val }),
            }
        }
    }
}
