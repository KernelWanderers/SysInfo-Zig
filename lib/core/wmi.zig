const std = @import("std");
const win32 = @import("win32");
const WMI = win32.system.wmi;
const COM = win32.system.com;
const OLE = win32.system.ole;
const Foundation = win32.foundation;
const Allocator = std.mem.Allocator;

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

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

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
        ERROR: error{ERROR},                    //          => 10
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
        const slice = std.mem.sliceTo(@ptrCast([*:0]u16, bstr), 0);

        return self.convertUtf16ToUtf8(slice, allocator);
    }

    /// Destructs the elements inside of a `SafeArray`
    /// into a `StringHashMap`; which can contain any
    /// element of type `VariantElem`.
    ///
    ///     `obj`       - The `IWbemClassObject` instance to obtain the data from.
    ///     `safeArr`   - The `SafeArray` instance to iterate over.
    ///     `allocator` - The allocator instance used to allocate the hashmap to heap.
    ///
    /// **Note**: The returned `StringHashMap` MUST be freed after
    ///           you're done using it! The library does not, and cannot, do this automatically.
    ///
    /// **Returns**: A `StringHashMap` containing the values from the provided `SafeArray`.
    pub fn destructSafeArray(
        self: @This(),
        obj: ?*WMI.IWbemClassObject,
        safeArr: ?*COM.SAFEARRAY,
        allocator: *Allocator,
    ) std.StringHashMap(VariantElem) {
        var map = std.StringHashMap(VariantElem).init(allocator);

        var lUpper: i32 = 0;
        var lLower: i32 = 0;
        var propName: ?*c_void = null;
        var propVal: COM.VARIANT = undefined;

        if (OLE.SafeArrayGetUBound(safeArr, 1, &lUpper) != 0) 
            return map;

        if (OLE.SafeArrayGetLBound(safeArr, 1, &lLower) != 0)
            return map;

        var i: i32 = lLower;

        while (i < lUpper) : (i += 1) {
            var t: ?*i32 = null;

            if (OLE.SafeArrayGetElement(safeArr, &i, &propName) != 0) continue;


            var bstr: *Foundation.BSTR = @ptrCast(
                *Foundation.BSTR,
                @alignCast(@alignOf(Foundation.BSTR), propName.?),
            );

            const slice = std.mem.sliceTo(
                @ptrCast([*:0]u16, bstr),
                0,
            );


            if (obj.?.*.IWbemClassObject_Get(
                slice,
                0,
                &propVal,
                t,
                t,
            ) != 0) continue;

            defer _ = OLE.VariantClear(&propVal);

            if (std.unicode.utf16leToUtf8Alloc(&gpa.allocator, slice)) |propName_utf8| {
                if (self.getElementVariant(propVal, &gpa.allocator) catch null) |val| 
                    map.put(propName_utf8, val) catch continue;
            } else |_| continue;
        }

        return map;
    }

    /// Executes a method based on its name and argument descriptions.
    ///
    ///     `path`      - The path to the parent `IWbemClassObject` which holds the method definition.
    ///     `method`    - The name of the method to execute.
    ///     `pInInst`   - The argument descriptions of the method.
    ///
    /// **Returns**: A pointer to an `IWbemClassObject` instance,
    ///              which is the outputted value from the method.
    pub fn execMethod(
        self: @This(),
        path: Foundation.BSTR,
        method: Foundation.BSTR,
        pInInst: ?*WMI.IWbemClassObject,
    ) ?*WMI.IWbemClassObject {
        _ = self;

        var pOutInst: ?*WMI.IWbemClassObject = null;

        if (iwb_service.?.*.IWbemServices_ExecMethod(
            path,
            method,
            0,
            null,
            pInInst,
            &pOutInst,
            null
        ) != 0) return null;

        return pOutInst;
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
        allocator: *Allocator,
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
            else => return error.UnknownValue,
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
        enumerator: ?*WMI.IEnumWbemClassObject,
        obj: ?*WMI.IWbemClassObject,
        property: []const u8,
        allocator: *Allocator,
    ) !?VariantElem {
        var pclsObj: ?*WMI.IWbemClassObject = obj;
        var uReturn: u32 = 0;

        while (true) {
            var t: i32 = 0;

            if (obj == null) {
                if (enumerator == null) break;

                if (enumerator.?.*.IEnumWbemClassObject_Next(
                    @enumToInt(WMI.WBEM_INFINITE),
                    1,
                    @ptrCast([*]?*WMI.IWbemClassObject, &pclsObj),
                    &uReturn,
                ) != 0) return null;

                if (uReturn == 0) break;
            }


            var prop: COM.VARIANT = undefined;

            if (std.unicode.utf8ToUtf16LeWithNull(allocator, property)) |utf16_str| {
                // Free the freshly allocated utf16_str after scope is finished.
                defer allocator.free(utf16_str);

                if (pclsObj.?.*.IWbemClassObject_Get(
                    utf16_str,
                    0,
                    &prop,
                    &t,
                    &t,
                ) != 0) return null;

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
    /// Returns: An `ArrayList` of all the values of the current CIM/WMI object/class, 
    /// each value is stored in a hashmap.
    ///
    /// **NOTE**: You MUST `deinit` the list & values inside after you're done using it!
    /// The library does not, nor can it, do this automatically.
    pub fn getItems(
        self: @This(),
        enumerator: ?*WMI.IEnumWbemClassObject,
        obj: ?*WMI.IWbemClassObject,
        allocator: *Allocator,
    ) std.ArrayList(std.StringHashMap(VariantElem)) {
        var array = std.ArrayList(std.StringHashMap(VariantElem)).init(allocator);
        var pclsObj: ?*WMI.IWbemClassObject = obj;
        var uReturn: u32 = 0;
        var hres: i32 = 0;

        if (obj == null) {
            if (enumerator == null) return array;

            hres = enumerator.?.*.IEnumWbemClassObject_Next(
                @enumToInt(WMI.WBEM_INFINITE),
                1,
                @ptrCast([*]?*WMI.IWbemClassObject, &pclsObj),
                &uReturn,
            );

            if (hres != 0 or uReturn == 0) return array;
        }
        
        var qualifier: ?*COM.VARIANT = null;
        var safe_arr: ?*COM.SAFEARRAY = null;

        if (pclsObj.?.*.IWbemClassObject_GetNames(
            null,
            0,
            qualifier,
            &safe_arr,
        ) != 0) return array;

        defer _ = pclsObj.?.*.IUnknown_Release();

        _ = array.append(self.destructSafeArray(pclsObj, safe_arr, allocator)) catch return array;

        _ = OLE.SafeArrayDestroy(safe_arr);

        _ = array.appendSlice((self.getItems(enumerator, null, allocator)).items) catch return array;

        return array;
    }

    /// Obtains an instance of the object
    /// based on the provided path.
    ///
    ///     `path` - The path of the wanted object.
    ///
    /// **Returns**: A pointer to an `IWbemClassObject` instance, if possible.
    pub fn getObjectInst(
        self: @This(),
        path: Foundation.BSTR,
    ) ?*WMI.IWbemClassObject {
        _ = self;

        var obj: ?*WMI.IWbemClassObject = null;

        if (iwb_service.?.*.IWbemServices_GetObject(
            path, 
            0, 
            null, 
            &obj, 
            null,
        ) != 0) return null;

        return obj;
    }

    /// Obtains a method matching the provided method name.
    ///
    ///     `obj`  - The object from which to obtain the method.
    ///     `name` - The name of the method to attempt to find.
    ///
    /// **Returns**: A pointer to an `IWbemClassObject` instance
    ///              which matches the method's argument descriptions.
    pub fn getMethod(
        self: @This(),
        obj: ?*WMI.IWbemClassObject,
        name: Foundation.BSTR
    ) ?*WMI.IWbemClassObject {
        _ = self;

        var pInClass: ?*WMI.IWbemClassObject = null;
        var pInInst: ?*WMI.IWbemClassObject = null;

        if (obj.?.*.IWbemClassObject_GetMethod(
            std.mem.sliceTo(
                @ptrCast([*:0]u16, name),
                0
            ),
            0,
            &pInClass,
            null,
        ) != 0) return null;

        if (pInClass.?.*.IWbemClassObject_SpawnInstance(
            0,
            &pInInst,
        ) != 0) return null;

        return pInInst;
    }

    /// Initialises a new `IWbemServices` instance by using `COM` and `WMI`
    ///
    /// Returns: A pointer to an `IWbemServices` instance if successful, otherwise `null`.
    pub fn initialiseIWbemServices(
        self: @This(),
        namespace: ?[]u8,
    ) ?*WMI.IWbemServices {
        var pLoc: ?*c_void = null;
        var pSvc: ?*WMI.IWbemServices = null;
        var hres: i32 = 0;
        var n: u16 = 0;

        if (iwb_service != null) return iwb_service;

        lock.lock();
        defer lock.unlock();

        if (COM.CoInitializeEx(null, COM.COINIT_MULTITHREADED) != 0) return null;

        if (COM.CoInitializeSecurity(
            null,
            -1,
            null,
            null,
            COM.RPC_C_AUTHN_LEVEL_DEFAULT,
            COM.RPC_C_IMP_LEVEL_IMPERSONATE,
            null,
            COM.EOAC_NONE,
            null,
        ) != 0) return null;

        if (COM.CoCreateInstance(
            WMI.CLSID_WbemLocator,
            null,
            COM.CLSCTX_INPROC_SERVER,
            WMI.IID_IWbemLocator,
            &pLoc,
        ) != 0) return null;

        if (hres != 0) return null;

        const IWbemLocator = @ptrCast(
            ?*WMI.IWbemLocator,
            @alignCast(@alignOf(WMI.IWbemLocator), pLoc),
        );

        // Use the provided namespace if possible,
        // otherwise, fallback to the default namespace for WMI objects.
        const Namespace = self.utf8ToBSTR(namespace orelse "ROOT\\CIMV2") catch return null;

        if (IWbemLocator.?.*.IWbemLocator_ConnectServer(
            Namespace,
            null,
            null,
            &n,
            0,
            &n,
            null,
            &pSvc,
        ) != 0) return null;

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
        searchQuery: []const u8,
        pSvcArg: ?*WMI.IWbemServices,
        namespace: ?[]u8,
    ) ?*WMI.IEnumWbemClassObject {
        var pEnumerator: ?*WMI.IEnumWbemClassObject = null;
        var pSvc: ?*WMI.IWbemServices = pSvcArg orelse self.initialiseIWbemServices(namespace orelse null) orelse return null;

        const WQL = self.utf8ToBSTR("WQL") catch return null;
        const Query = self.utf8ToBSTR(searchQuery) catch return null;

        defer Foundation.SysFreeString(WQL);
        defer Foundation.SysFreeString(Query);

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

    /// Converts a "regular" UTF-8 string to a BSTR.
    ///
    ///     `str`  - The string to convert.
    ///
    /// Returns: A `BSTR` representation of the string.
    pub fn utf8ToBSTR(
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
