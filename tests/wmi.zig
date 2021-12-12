const std = @import("std");
const WMI = @import("../lib/core/wmi.zig");
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

test "getItem" {
    const stdout = std.io.getStdOut().writer();
    const iWMI: WMI.SysInfoWMI = .{};
    const pEnumerator = iWMI.query("SELECT * FROM Win32_Processor", null, null) orelse {
        try stdout.print("Failed query. Function returned `null`", .{});
        return;
    };

    const value = iWMI.getItem(pEnumerator, null, "Name", &gpa.allocator) catch null;

    if (value == null) {
        try stdout.print("Failed to obtain 'Name' property of Win32_Processor enumerator. Returned status code: 1", .{});
        return;
    }

    switch (value.?) {
        .String => |val| try stdout.print("----{s}\n", .{val}),
        else => |val| try stdout.print("----{any}\n", .{val}),
    }
}

test "getItems" {
    const stdout = std.io.getStdOut().writer();
    const iWMI: WMI.SysInfoWMI = .{};
    const pEnumerator = iWMI.query("SELECT * FROM Win32_VideoController", null, null) orelse {
        try stdout.print("Failed query. Function returned `null`", .{});
        return;
    };

    var list = iWMI.getItems(pEnumerator, null, &gpa.allocator);

    if (list.items.len == 0) {
        try stdout.print("Failed to obtain properties of Win32_VideoController enumerator. Returned status code: 1", .{});
        return;
    }

    defer list.deinit();

    var i: usize = 0;

    while (i < list.items.len) {
        var itr = list.items[i].iterator();

        while (itr.next()) |entry| {
            switch (entry.value_ptr.*) {
                .String => |val| try stdout.print("Key: {s} | Value: {s}\n", .{ entry.key_ptr.*, val.? }),
                else => |val| try stdout.print("Key: {s} | Value: {any}\n", .{ entry.key_ptr.*, val }),
            }
        }

        i += 1;
    }
}