const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const SysInfoWMI = @import("../../../../core/wmi.zig").SysInfoWMI;
const VariantElem = SysInfoWMI.VariantElem;
const util = @import("../../../../core/util.zig");
const _WMI = @import("win32").system.wmi;
const COM = @import("win32").system.com;
const OLE = @import("win32").system.ole;
const Foundation = @import("win32").foundation;

pub const HardwareManager = extern struct {
    /// An instance of [`SysInfoWMI`](https://github.com/iabtw/SysInfo-Zig/blob/main/lib/core/wmi.zig), used for
    /// querying system information (including hardware)
    /// on Windows.
    pub const WMI: SysInfoWMI = .{};

    /// The default heap allocator used for
    /// tasks where the user doesn't necessarily
    /// have to provide their own allocator.
    ///
    /// __Rarely used.__
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    /// Used internally to append multiple key-value
    /// pairs to an existing hashmap.
    /// Keep note that they're appended by means of index,
    /// meaning, the order in the `keys` slice should reflect
    /// its value pair order in the `vals` slice.
    ///
    /// The `keys` and `vals` slices must have the same amount of items.
    ///
    ///     `T`     - The type for this `StringHashMap`.
    ///     `map`   - The `StringHashMap` to append the keys/values to.
    ///     `keys`  - The keys to append to the hashmap.
    ///     `vals`  - The values to append to the hashmap.
    ///
    /// **Returns**: A status code indicating whether or not the operation
    ///              was successful. `1` means error, `0` means OK.
    pub fn appendKeysToMap(
        self: @This(),
        comptime T: anytype,
        map: *StringHashMap(T),
        keys: [][]const u8,
        vals: [][]const u8,
    ) u8 {
        // Discarding reference to `self` so
        // the compiler won't complain.
        _ = self;

        // Why would we attempt to do something that's broken for this logic?
        if (keys.len != vals.len or keys.len == 0) return 1;

        var i: usize = 0;

        while (i < keys.len) : (i += 1)
            map.put(keys[i], vals[i]) catch return 1;

        return 0;
    }

    /// Used internally to only obtain the provided
    /// set of keys, and return a new, filtered hashmap.
    ///
    ///     `keys`      - A `StringHashMap` of the key-value pairs
    ///                   to look for and "replace". Fallbacks to the key
    ///                   if the value is `null`.
    ///     `list`      - A `StringHashMap` of the actual data.
    ///     `allocator` - The allocator instance used to allocate the
    ///                   hashmap to heap.
    ///
    /// **Returns**: An `ArrayList` of `StringHashMap(VariantElem)`; or `null`
    /// if something goes wrong.
    ///
    /// **NOTE**: if you do use this, you must free the
    ///           newly provided `ArrayList` value from heap after you're 
    ///           done using it! The library doesn't, and can't, do this automatically.
    pub fn getKeys(
        self: @This(),
        keys: StringHashMap([]const u8),
        list: StringHashMap(VariantElem),
        allocator: *Allocator,
    ) StringHashMap(VariantElem) {
        // Discarding reference to `self` so
        // the compiler won't complain.
        _ = self;

        var map = StringHashMap(VariantElem).init(allocator);
        var itr = list.iterator();

        while (itr.next()) |entry| {
            var keysItr = keys.iterator();

            while (keysItr.next()) |keyEntry|
                if (std.mem.eql(u8, entry.key_ptr.*, keyEntry.key_ptr.*)) map.put(keyEntry.value_ptr.*, entry.value_ptr.*) catch continue;
        }

        return map;
    }

    /// Obtains information about the current system's
    /// CPU(s) in use. 
    ///
    ///     `allocator` - The allocator instance used to allocate the `ArrayList`
    ///                   and hashmap to heap.
    /// 
    /// **WARNING**: Haven't tested yet on dual processor setups...
    ///
    /// **Returns**: An `ArrayList` of `StringHashMap`, where each instance of
    /// the hash map is a unique WMI/CIM object's key-value pairs.
    /// Or `null` if something goes wrong.
    ///
    /// **NOTE**: You MUST free the provided value after you're done using it!
    ///           The library doesn't, and can't, do this automatically.
    pub fn getCPUInfo(
        self: @This(),
        allocator: *Allocator,
    ) ?ArrayList(StringHashMap(VariantElem)) {
        // Discarding reference to `self` so
        // the compiler won't complain.
        _ = self;

        const pEnumerator = WMI.query("SELECT * FROM Win32_Processor", null, null) orelse return null;
        const list = WMI.getItems(pEnumerator, null, allocator);

        // Something definitely went wrong.
        if (list.items.len == 0) return null;

        defer list.deinit();

        var array = ArrayList(StringHashMap(VariantElem)).init(allocator);
        var keyMap = StringHashMap([]const u8).init(&gpa.allocator);
        defer keyMap.deinit();
        var i: usize = 0;

        while (i < list.items.len) : (i += 1) {
            var keys = [_][]const u8{ "Manufacturer", "Name", "NumberOfCores", "NumberOfLogicalProcessors" };
            var vals = [_][]const u8{ "Manufacturer", "Model", "Cores", "Threads" };

            if (self.appendKeysToMap(
                []const u8,
                &keyMap,
                keys[0..],
                vals[0..],
            ) != 0) continue;

            array.append(self.getKeys(keyMap, list.items[i], allocator)) catch continue;
        }

        return array;
    }

    /// Obtains information about the current system's
    /// CPU(s) in use. 
    ///
    ///     `allocator` - The allocator instance used to allocate
    ///                   the `ArrayList` and hashmap to heap.
    /// 
    /// **WARNING**: Haven't tested yet on dual processor setups...
    ///
    /// **Returns**: An `ArrayList` of `StringHashMap`, where each instance of
    /// the hash map is a unique WMI/CIM object's key-value pairs.
    /// Or `null` if something goes wrong.
    ///
    /// **NOTE**: You MUST free the provided value after you're done using it!
    ///           The library doesn't, and can't, do this automatically.
    pub fn getGPUInfo(
        self: @This(),
        allocator: *Allocator,
    ) ?ArrayList(StringHashMap(VariantElem)) {
        // Discarding reference to `self` so
        // the compiler won't complain.
        _ = self;

        const pEnumerator = WMI.query("SELECT * FROM Win32_VideoController", null, null) orelse return null;
        const list = WMI.getItems(pEnumerator, null, allocator);

        // Something definitely went wrong.
        if (list.items.len == 0) return null;

        defer list.deinit();

        var array = ArrayList(StringHashMap(VariantElem)).init(allocator);
        var keyMap = StringHashMap([]const u8).init(&gpa.allocator);
        defer keyMap.deinit();
        var i: usize = 0;

        while (i < list.items.len) : (i += 1) {
            var keys = [_][]const u8{ "Manufacturer", "Name", "PNPDeviceID" };
            var vals = [_][]const u8{ "Manufacturer", "Model", "PNPDeviceID" };

            if (self.appendKeysToMap(
                []const u8,
                &keyMap,
                keys[0..],
                vals[0..],
            ) != 0) continue;

            array.append(self.getKeys(keyMap, list.items[i], allocator)) catch continue;
        }

        // TODO: Obtain the ACPI/PCI path of GPU devices.
        //       Currently broken due to faulty logic with SafeArray
        //       element access.

        // i = 0;

        // while (i < array.items.len) : (i += 1) {
        //     var itr = array.items[i].iterator();

        //     while (itr.next()) |entry| {
        //         if (std.mem.eql(u8, entry.key_ptr.*, "PNPDeviceID")) {
        //             var str = std.fmt.allocPrint(&gpa.allocator, "SELECT * FROM Win32_PnPEntity WHERE PNPDeviceID = '{s}'", .{entry.value_ptr.*.String.?}) catch break;

        //             // Replaces regular slashes with
        //             str = std.mem.replaceOwned(u8, &gpa.allocator, str, "\\", "\\\\") catch break;

        //             defer gpa.allocator.free(str);

        //             const pEnum = WMI.query(
        //                 str,
        //                 null,
        //                 null,
        //             );

        //             const myItems = WMI.getItems(pEnum.?, null, &gpa.allocator);

        //             if (myItems.items.len == 0) {
        //                 std.debug.print("Failed to obtain properties of Win32_PnPEntity enumerator. Returned status code: 1\n", .{});
        //                 break;
        //             }

        //             defer myItems.deinit();

        //             var j: usize = 0;

        //             while (j < myItems.items.len) : (j += 1) {
        //                 var iter = myItems.items[j].iterator();

        //                 while (iter.next()) |entry_val| {
        //                     switch (entry_val.value_ptr.*) {
        //                         .String => |str_val| {
        //                             if (std.mem.eql(u8, entry_val.key_ptr.*, "__PATH")) {
        //                                 var path = WMI.utf8ToBSTR(str_val.?) catch continue;

        //                                 var obj = WMI.getObjectInst(path.?);

        //                                 if (obj == null) {
        //                                     std.debug.print("Failed on obj\n", .{});
        //                                     continue;
        //                                 }

        //                                 var methodName = WMI.utf8ToBSTR("GetDeviceProperties") catch continue;
        //                                 var pInInst = WMI.getMethod(obj, methodName.?);
        //                                 var executed = WMI.execMethod(path.?, methodName.?, pInInst);
        //                                 var data = WMI.getItem(null, executed, "deviceProperties", &gpa.allocator) catch continue;

        //                                 var lUpper: i32 = 0;
        //                                 var lLower: i32 = 0;
        //                                 var propName: ?*c_void = null;
        //                                 var propVal: COM.VARIANT = undefined;

        //                                 if (OLE.SafeArrayGetUBound(data.?.AnyArray, 1, &lUpper) != 0)
        //                                     continue;

        //                                 if (OLE.SafeArrayGetLBound(data.?.AnyArray, 1, &lLower) != 0)
        //                                     continue;

        //                                 var l: i32 = lLower;

        //                                 while (l < lUpper) : (l += 1) {
        //                                     var t: ?*i32 = null;

        //                                     // Breaks here \/ !!
        //                                     if (OLE.SafeArrayGetElement(data.?.AnyArray.?, &l, &propName) != 0) continue;

        //                                     var bstr: *Foundation.BSTR = @ptrCast(
        //                                         *Foundation.BSTR,
        //                                         @alignCast(@alignOf(Foundation.BSTR), propName.?),
        //                                     );

        //                                     const slice = std.mem.sliceTo(
        //                                         @ptrCast([*:0]u16, bstr),
        //                                         0,
        //                                     );

        //                                     if (executed.?.*.IWbemClassObject_Get(
        //                                         slice,
        //                                         0,
        //                                         &propVal,
        //                                         t,
        //                                         t,
        //                                     ) != 0) continue;

        //                                     defer _ = OLE.VariantClear(&propVal);

        //                                     if (std.unicode.utf16leToUtf8Alloc(&gpa.allocator, slice)) |propName_utf8| {
        //                                         if (WMI.getElementVariant(propVal, &gpa.allocator) catch null) |val|
        //                                             // map.put(propName_utf8, val) catch continue;
        //                                             std.debug.print("__KEY: {any} | __VAL: {any}\n", .{ propName_utf8, val });
        //                                     } else |_| continue;
        //                                 }
        //                             }
        //                         },
        //                         else => |other_val| {
        //                             _ = other_val;
        //                             continue;
        //                         },
        //                     }
        //                 }
        //             }
        //         }
        //     }
        // }

        return array;
    }
};
