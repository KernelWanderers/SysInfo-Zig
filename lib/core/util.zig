const std = @import("std");

pub fn printStringHashMap(
    comptime T: anytype,
    map: std.StringHashMap(T),
) void {
    var itr = map.iterator();

    while (itr.next()) |entry|
        std.debug.print("__KEY: {s} | __VAL: {any}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
}
