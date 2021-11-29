const std = @import("std");
const win32 = @import("win32");
const WMI = win32.system.wmi;
const COM = win32.system.com;
const OLE = win32.system.ole;
const Foundation = win32.foundation;
const Allocator = std.mem.Allocator;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub const SysInfoWMI = extern struct {
    /// Property for when `initialiseIWbemServices()` is called,
    /// to ensure it doesn't attempt to connect to the local namespace
    /// more than a single time.
    ///
    /// It is thread safe due to the nature of `initialiseIWbemServices()`'s
    /// internal handles. It uses `std.Thread.Mutex.lock()` to lock the declaration
    /// for this value to a single thread, and unlock it afterwards.
    pub var iwb_service: ?*WMI.IWbemServices = null;

    var lock: std.Thread.Mutex = .{};

    // Enums' properties are sorted alphabetically.

    /// Union enum for storing type values
    /// of all the possible values a `COM.VARIANT` instance 
    /// could contain.
    pub const VariantElem = union(enum) {
        AnyArray: ?*COM.SAFEARRAY,                      //  => 8192 + varType of elements' type.
        Boolean: i16,                                  //   => 11
        Byte: u8,                                     //    => 17
        Currency: COM.CY,                            //     => 6
        Date: f64,                                  //      => 7
        Decimal: Foundation.DECIMAL,               //       => 14
        Double: f64,                              //        => 5
        EMPTY: void,                             //         => 0
        ERROR: error{ ERROR },                  //          => 10
        Int: i32,                              //           => 2
        Long: i32,                            //            => 3
        LongLong: i64,                       //             => 20
        NULL: void,                         //              => 1
        ObjectRef: ?*c_void,               //               => 9
        Single: i32,                      //                => 4
        String: ?[]u8,                   //                 => 8  (This is actually ?BSTR, but we automatically convert.)
        Variant: ?*COM.VARIANT,         //                  => 12
        VariantNull: void,             //                   => 13
    };

    /// Converts a UTF-16 string into UTF-8 using `std.unicode.utf16leToUtf8Alloc()`
    ///
    ///     `utf16_str`   - The UTF-16 string to convert from.
    ///     `allocator`   - The allocator used to allocate the converted value to heap. 
    ///
    /// Returns: A UTF8 "string" representation of the UTF16 string.
    ///
    /// **NOTE**: You MUST free the returned value after you're done using it.
    /// The library won't, and can't, do this automatically.
    pub fn convertUtf16ToUtf8(
        self: @This(),
        utf16_str: []const u16, 
        allocator: *Allocator,
    ) !?[]u8 {
        // Discarding reference to `self` so
        // the compiler won't complain.
        _ = self;

        return try std.unicode.utf16leToUtf8Alloc(allocator, utf16_str);
    }

    /// Converts a `BSTR` (`?*u16`) value into UTF-8.
    ///
    ///     `bstr`       - The `BSTR` value to convert from.
    ///     `allocator`  - The allocator used to allocate the converted value to heap.
    ///
    /// Returns: A "string" representation of the `BSTR` value.
    ///
    /// **NOTE**: You MUST free the returned value after you're done using it.
    /// The library won't, and can't, do this automatically.
    pub fn convertBSTRToUtf8(
        self: @This(),
        bstr: Foundation.BSTR,
        allocator: *Allocator,
    ) !?[]u8 {
        const slice = std.mem.sliceTo(
            @ptrCast([*:0]u16, bstr),
            0
        );

        return self.convertUtf16ToUtf8(slice, allocator);
    }

    /// Extracts the valid element from the Variant value
    /// based on the `vt` property--which indicates the type 
    /// of value allocated.
    ///
    ///     `variant`   - The value of a `VARIANT` reference.
    ///     `allocator` - The allocator used to allocate `BSTR` to heap, only. Sometimes this won't be used. If you receive a `[]u8` back, you must free the allocated value from memory.
    ///
    /// Returns: A `VariantElem` union, or an error if something goes wrong.
    ///
    /// **NOTE**: Do not forget to free the `String` value from memory if
    /// this value was returned!
    pub fn getElementVariant(
        self: @This(), 
        variant: COM.VARIANT,
        allocator: *Allocator
    ) !VariantElem {
        // Discarding reference to `self` so
        // the compiler won't complain.
        _ = self;

        switch (variant.Anonymous.Anonymous.vt) {
            0 => return VariantElem{ .EMPTY = {} },
            1 => return VariantElem{ .NULL = {} },
            2 => return VariantElem{ .Int = variant.Anonymous.Anonymous.Anonymous.intVal },
            3 => return VariantElem{ .Long = variant.Anonymous.Anonymous.Anonymous.lVal },
            4 => return VariantElem{ .Single = variant.Anonymous.Anonymous.Anonymous.scode },
            5 => return VariantElem{ .Double = variant.Anonymous.Anonymous.Anonymous.dblVal },
            6 => return VariantElem{ .Currency = variant.Anonymous.Anonymous.Anonymous.cyVal },
            7 => return VariantElem{ .Date = variant.Anonymous.Anonymous.Anonymous.date },
            8 => {
                if (variant.Anonymous.Anonymous.Anonymous.bstrVal == null) return VariantElem{ .String = null };

                // Have to ignore here...
                return VariantElem{ .String = self.convertBSTRToUtf8(variant.Anonymous.Anonymous.Anonymous.bstrVal.?, allocator) catch null };
            },
            9 => return VariantElem{ .ObjectRef = variant.Anonymous.Anonymous.Anonymous.byref },
            10 => return VariantElem{ .ERROR = error.ERROR },
            11 => return VariantElem{ .Boolean = variant.Anonymous.Anonymous.Anonymous.boolVal },
            12 => return VariantElem{ .Variant = variant.Anonymous.Anonymous.Anonymous.pvarVal },
            13 => return VariantElem{ .VariantNull = {} },
            14 => return VariantElem{ .Decimal = variant.Anonymous.decVal },
            17 => return VariantElem{ .Byte = variant.Anonymous.Anonymous.Anonymous.bVal },
            20 => return VariantElem{ .LongLong = variant.Anonymous.Anonymous.Anonymous.llVal },
            8192...8228 => return VariantElem{ .AnyArray = variant.Anonymous.Anonymous.Anonymous.parray },
            else => return error.UnknownValue
        }
    }

    /// Obtains a value of some specified property from the current CIM/WMI class/object.
    ///
    ///     `enumerator` - The enumerator instance returned from a query. See: `WMI.query()`; defined as nullable, but the function won't execute without this parameter.
    ///     `property`   - The name of the property to retrieve.
    ///     `allocator`  - The allocator instance used to allocate the value to heap.
    ///
    /// Returns: The queried item. Can be of any type from `VariantElem` union.
    ///
    /// **NOTE**: You MUST free the value allocated to heap after you've finished using it! 
    /// The library does not, nor can it, do this automatically.
    pub fn getItem(
        self: @This(),
        enumerator: *WMI.IEnumWbemClassObject,
        property: []const u8,
        allocator: *Allocator,
    ) !?VariantElem {
        var pclsObj: ?*WMI.IWbemClassObject = null;
        var uReturn: u32 = 0;
        var hres: i32 = 0;

        // Discarding reference to `self` so
        // the compiler won't complain.
        _ = self;

        while (true) {
            var t: i32 = 0;

            hres = enumerator.*.IEnumWbemClassObject_Next(
                @enumToInt(WMI.WBEM_INFINITE),
                1,
                @ptrCast([*]?*WMI.IWbemClassObject, &pclsObj),
                &uReturn,
            );

            if (uReturn == 0) break;

            var prop: COM.VARIANT = undefined;

            if (std.unicode.utf8ToUtf16LeWithNull(allocator, property)) |utf16_str| {
                // Free the freshly allocated utf16_str after scope is finished.
                defer allocator.free(utf16_str);

                hres = pclsObj.?.*.IWbemClassObject_Get(
                    utf16_str,
                    0,
                    &prop,
                    &t,
                    &t,
                );

                defer _ = OLE.VariantClear(&prop);
                defer _ = pclsObj.?.*.IUnknown_Release();

                return try self.getElementVariant(prop, allocator);
            } else |err| return err;
        }

        return null;
    }

    /// Obtains a list of values of all properties (which aren't exposed through this method) from the current CIM/WMI object/class.
    ///
    ///     `enumerator` - The enumerator instance returned from a query. See: `WMI.query()`; defined as nullable, but the function won't execute without this parameter.
    ///     `allocator`  - The allocator instance used to allocate the ArrayList to heap.
    ///
    /// Returns: A `StringHashMap` of all the values of the current CIM/WMI object/class.
    ///
    /// **NOTE**: You MUST `deinit` the list after you're done using it!
    /// The library does not, nor can it, do this automatically.
    pub fn getItems(
        self: @This(),
        enumerator: *WMI.IEnumWbemClassObject,
        allocator: *Allocator,
    ) !std.StringHashMap(VariantElem) {
        var map = std.StringHashMap(VariantElem).init(allocator);
        var pclsObj: ?*WMI.IWbemClassObject = null;
        var uReturn: u32 = 0;
        var hres: i32 = 0;
        var t: ?*i32 = null;
        var k: ?*i32 = null;

        // Discarding reference to `self` so
        // the compiler won't complain.
        _ = self;

        while (true) {
            hres = enumerator.*.IEnumWbemClassObject_Next(
                @enumToInt(WMI.WBEM_INFINITE),
                1,
                @ptrCast([*]?*WMI.IWbemClassObject, &pclsObj),
                &uReturn,
            );

            if (uReturn == 0) break;

            var qualifier: ?*COM.VARIANT = null;
            var safe_arr: ?*COM.SAFEARRAY = null;

            hres = pclsObj.?.*.IWbemClassObject_GetNames(
                null,
                0,
                qualifier,
                &safe_arr,
            );

            if (hres != 0) continue;

            var lUpper: i32 = 0;
            var lLower: i32 = 0;
            var propName: ?*c_void = null;
            var propVal: COM.VARIANT = undefined;

            hres = OLE.SafeArrayGetUBound(safe_arr, 1, &lUpper);
            hres = OLE.SafeArrayGetLBound(safe_arr, 1, &lLower);

            var i: i32 = lLower;

            while (i < lUpper) {
                hres = OLE.SafeArrayGetElement(safe_arr, &i, &propName);

                if (hres != 0) {
                    i += 1;
                    continue;
                }

                var bstr: *Foundation.BSTR = @ptrCast(
                    *Foundation.BSTR,
                    @alignCast(@alignOf(Foundation.BSTR), propName.?),
                );

                const slice = std.mem.sliceTo(
                    @ptrCast([*:0]u16, bstr),
                    0,
                );

                hres = pclsObj.?.*.IWbemClassObject_Get(
                    slice,
                    0,
                    &propVal,
                    t,
                    k,
                );

                defer _ = OLE.VariantClear(&propVal);

                if (hres != 0) {
                    i += 1;
                    continue;
                }


                // TODO: Fix--this for some reason returns garbled text such as `τ│╕∩Öá╔ú`?
                //       Possibly needs to be converted to ASCII first?
                if (std.unicode.utf16leToUtf8Alloc(allocator, slice)) |propName_utf8| {
                    if (self.getElementVariant(propVal, allocator) catch null) |val| {
                        try map.put(propName_utf8, val);
                    }
                } else |_| continue;

                i += 1;
                t = null;
                k = null;
            }

            hres = OLE.SafeArrayDestroy(safe_arr);
        }

        defer uReturn = pclsObj.?.*.IUnknown_Release();

        return map;
    }

    /// Initialises a new `IWbemServices` instance by using `COM` and `WMI`
    ///
    /// Returns: A pointer to an `IWbemServices` instance if successful, otherwise `null`.
    pub fn initialiseIWbemServices(self: @This()) ?*WMI.IWbemServices {
        var pLoc: ?*c_void = null;
        var pSvc: ?*WMI.IWbemServices = null;
        var hres: i32 = 0;
        var n: u16 = 0;

        if (iwb_service != null) return iwb_service;

        lock.lock();
        defer lock.unlock();

        hres = COM.CoInitializeEx(null, COM.COINIT_MULTITHREADED);

        if (hres != 0) return null;

        hres = COM.CoInitializeSecurity(
            null,
            -1,
            null,
            null,
            COM.RPC_C_AUTHN_LEVEL_DEFAULT,
            COM.RPC_C_IMP_LEVEL_IMPERSONATE,
            null,
            COM.EOAC_NONE,
            null,
        );

        if (hres != 0) return null;

        hres = COM.CoCreateInstance(
            WMI.CLSID_WbemLocator,
            null,
            COM.CLSCTX_INPROC_SERVER,
            WMI.IID_IWbemLocator,
            &pLoc,
        );

        if (hres != 0) return null;

        const IWbemLocator = @ptrCast(
            ?*WMI.IWbemLocator,
            @alignCast(@alignOf(WMI.IWbemLocator), pLoc),
        );

        const Namespace = self.stringToBSTR("ROOT\\CIMV2") catch return null; // Default namespace?

        hres = IWbemLocator.?.*.IWbemLocator_ConnectServer(
            Namespace,
            null,
            null,
            &n,
            0,
            &n,
            null,
            &pSvc,
        );

        if (hres != 0) return null;

        iwb_service = pSvc;

        return pSvc;
    }

    /// Runs the provided query in the current namespace `ROOT\\CIMV2`
    ///
    ///     `search_query` - The full query string to execute.
    ///     `pSvcArg`      - The `IWbemServices` instance. Provide null if you can't create one. By default, this calls `WMI.initialiseIWbemServices()`
    ///
    /// Returns: A reference to an `IEnumWbemClassObject` if successful. Otherwise, `null`.
    pub fn query(
        self: @This(),
        search_query: []const u8,
        pSvcArg: ?*WMI.IWbemServices,
    ) ?*WMI.IEnumWbemClassObject {
        var pEnumerator: ?*WMI.IEnumWbemClassObject = null;
        var pSvc: ?*WMI.IWbemServices = pSvcArg orelse self.initialiseIWbemServices() orelse return null;

        const WQL = self.stringToBSTR("WQL") catch return null;
        const Query = self.stringToBSTR(search_query) catch return null;

        // `flag` here should have a value of 16
        const flag = @enumToInt(WMI.WBEM_FLAG_RETURN_IMMEDIATELY);

        const hres = pSvc.?.*.IWbemServices_ExecQuery(
            WQL, // WQL = WMI Query Language
            Query,
            flag,
            null,
            &pEnumerator,
        );

        // In case the search wasn't successful,
        // return null.
        if (hres != 0) return null;

        return pEnumerator;
    }

    /// Converts a "regular string" to a BSTR.
    ///
    ///     `str`  - The string to convert.
    ///
    /// Returns: A `BSTR` representation of the string.
    pub fn stringToBSTR(
        self: @This(),
        str: []const u8,
    ) !?Foundation.BSTR {
        const allocator = &gpa.allocator;

        // Discarding reference to `self` so
        // the compiler won't complain.
        _ = self;

        if (std.unicode.utf8ToUtf16LeWithNull(allocator, str)) |utf16_str| {
            // Free the freshly allocated utf16_str after scope is finished.
            defer allocator.free(utf16_str);

            return Foundation.SysAllocString(utf16_str);
        } else |err| return err;
    }
};

// Tests.
pub fn queryCPU() !void {
    const stdout = std.io.getStdOut().writer();
    const _WMI: SysInfoWMI = .{};
    const pEnumerator = _WMI.query("SELECT * FROM Win32_VideoController", null) orelse {
        try stdout.print("Failed query. Function returned `null`", .{});
        return;
    };

    const value = _WMI.getItem(pEnumerator, "Name", &gpa.allocator) catch null;

    if (value == null) {
        try stdout.print("Failed to obtain 'Name' property of Win32_Processor enumerator. Returned status code: 1", .{});
        return;
    }

    switch (value.?) {
        .String => |val| {
            defer gpa.allocator.free(val.?);

            try stdout.print("----{s}\n", .{val});
        },

        else => |val| try stdout.print("----{any}\n", .{val})
    }
}

pub fn queryGPU() !void {
    const stdout = std.io.getStdOut().writer();
    const _WMI: SysInfoWMI = .{};
    const pEnumerator = _WMI.query("SELECT * FROM Win32_VideoController", null);

    if (pEnumerator == null) {
        try stdout.print("Failed query. Function returned `null`", .{});
        return;
    }

    var map = _WMI.getItems(pEnumerator.?, &gpa.allocator) catch null;

    if (map == null) {
        try stdout.print("Failed to obtain 'Name' property of Win32_VideoController enumerator. Returned status code: 1", .{});
        return;
    }

    defer map.?.deinit();

    var itr = map.?.iterator();

    while (itr.next()) |entry| {
        switch (entry.value_ptr.*) {
            .String => |val| {
                defer gpa.allocator.free(val.?);

                try stdout.print("Key: {s} | Value: {s}\n", .{entry.key_ptr.*, val.? });
            },
            else => |val|  try stdout.print("Key: {s} | Value: {s}\n", .{ entry.key_ptr.*, val }) 
        }
    }
}
