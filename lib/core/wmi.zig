const std = @import("std");
const win32 = @import("win32");
const WMI = win32.system.wmi;
const COM = win32.system.com;
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

    /// Converts a "regular string" to a BSTR.
    ///
    ///     `str`  - The string to convert.
    ///
    /// Returns: A BSTR representation of the string.
    pub fn stringToBSTR(
        str: []const u8,
    ) !?Foundation.BSTR {
        const allocator = &gpa.allocator;

        if (std.unicode.utf8ToUtf16LeWithNull(allocator, str)) |utf16_str| {
            // Free the freshly allocated utf16_str after scope is finished.
            defer allocator.free(utf16_str);

            if (Foundation.SysAllocString(utf16_str)) |bstr| {
                return bstr;
            } else return null;
        } else |err| return err;
    }

    /// Initialises a new `IWbemServices` instance by using `COM` and `WMI`
    ///
    /// Returns: A pointer to an `IWbemServices` instance if successful, otherwise `null`.
    pub fn initialiseIWbemServices() ?*WMI.IWbemServices {
        var pLoc: ?*c_void = null;
        var pSvc: ?*WMI.IWbemServices = null;
        var hres: i32 = 0;
        var n: u16 = 0;

        if (SysInfoWMI.iwb_service != null) return iwb_service;

        @field(SysInfoWMI, "lock").lock();
        defer @field(SysInfoWMI, "lock").unlock();

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
            *WMI.IWbemLocator,
            @alignCast(@alignOf(WMI.IWbemLocator), pLoc),
        );

        const Namespace = stringToBSTR("ROOT\\CIMV2") catch return null; // Default namespace?

        hres = IWbemLocator.vtable.ConnectServer(
            IWbemLocator,
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

        SysInfoWMI.iwb_service = pSvc;

        return pSvc;
    }

    /// Obtains a value of some specified property from the current CIM/WMI class/object.
    ///
    ///     `enumerator` - The enumerator instance returned from a query. See: `WMI.query()`; defined as nullable, but the function won't execute without this parameter.
    ///     `property`   - The name of the property to retrieve.
    ///     `allocator`  - The allocator instance used to allocate the value to heap.
    ///
    /// Returns: A "string" representation of the property's value.
    ///
    /// **NOTE**: You MUST free the value allocated to heap after you've finished using it! 
    /// The library does not do this automatically.
    pub fn getItem(
        enumerator: *WMI.IEnumWbemClassObject,
        property: []const u8,
        allocator: *Allocator,
    ) !?[]u8 {
        var pclsObj: ?*WMI.IWbemClassObject = null;
        var uReturn: u32 = 0;
        var hres: i32 = 0;
        var t: i32 = 0;

        while (true) {
            hres = enumerator.*.IEnumWbemClassObject_Next(
                @enumToInt(WMI.WBEM_INFINITE),
                1,
                @ptrCast([*]?*WMI.IWbemClassObject, &pclsObj),
                &uReturn,
            );

            if (uReturn == 0) break;

            var prop: COM.VARIANT = undefined;

            if (std.unicode.utf8ToUtf16LeWithNull(allocator, property)) |utf16_str| {
                hres = pclsObj.?.*.vtable.Get(
                    @ptrCast(*const WMI.IWbemClassObject, pclsObj),
                    utf16_str,
                    0,
                    &prop,
                    &t,
                    &t,
                );

                const slice = std.mem.sliceTo(
                    @ptrCast([*:0]u16, prop.Anonymous.Anonymous.Anonymous.bstrVal),
                    0,
                );

                // Free the freshly allocated utf16_str after scope is finished.
                defer allocator.free(utf16_str);

                if (std.unicode.utf16leToUtf8Alloc(allocator, slice)) |utf8_str| {
                    // Release the object after we're done using it.
                    uReturn = pclsObj.?.*.IUnknown_Release();

                    return utf8_str;
                } else |err| return err;
            } else |err| return err;
        }

        return null;
    }

    /// Runs the provided query in the current namespace `ROOT\\CIMV2`
    ///
    ///     `search_query` - The full query string to execute.
    ///     `pSvcArg`      - The `IWbemServices` instance. Provide null if you can't create one. By default, this calls `WMI.initialiseIWbemServices()`
    ///
    /// Returns: A reference to an `IEnumWbemClassObject` if successful. Otherwise, `null`.
    pub fn query(
        search_query: []const u8,
        pSvcArg: ?*WMI.IWbemServices,
    ) ?*WMI.IEnumWbemClassObject {
        var pEnumerator: ?*WMI.IEnumWbemClassObject = null;
        var pSvc: ?*WMI.IWbemServices = pSvcArg orelse initialiseIWbemServices() orelse return null;

        const WQL = stringToBSTR("WQL") catch return null;
        const Query = stringToBSTR(search_query) catch return null;

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
};

// Tests.
pub fn queryCPU() !void {
    const stdout = std.io.getStdOut().writer();
    const pEnumerator = SysInfoWMI.query("SELECT * FROM Win32_Processor", null);

    if (pEnumerator == null) {
        try stdout.print("Failed query. Function returned `null`", .{});
        return;
    }

    const value = SysInfoWMI.getItem(pEnumerator.?, "Name", &gpa.allocator) catch null;

    if (value == null) {
        try stdout.print("Failed to obtain 'Name' property of Win32_Processor enumerator. Returned status code: 1", .{});
        return;
    }

    defer gpa.allocator.free(value.?);

    try stdout.print("----{s}\n", .{value});
}

pub fn queryGPU() !void {
    const stdout = std.io.getStdOut().writer();
    const pEnumerator = SysInfoWMI.query("SELECT * FROM Win32_VideoController", null);

    if (pEnumerator == null) {
        try stdout.print("Failed query. Function returned `null`", .{});
        return;
    }

    const value = SysInfoWMI.getItem(pEnumerator.?, "Name", &gpa.allocator) catch null;

    if (value == null) {
        try stdout.print("Failed to obtain 'Name' property of Win32_VideoController enumerator. Returned status code: 1", .{});
        return;
    }

    defer gpa.allocator.free(value.?);

    try stdout.print("====={s}\n", .{value});
}
