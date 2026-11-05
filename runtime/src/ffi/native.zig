const std = @import("std");
const builtin = @import("builtin");

const is_windows = builtin.os.tag == .windows;

const windows = std.os.windows;

extern "kernel32" fn LoadLibraryA(name: [*:0]const u8) callconv(windows.WINAPI) ?windows.HMODULE;
extern "kernel32" fn GetModuleHandleA(name: ?[*:0]const u8) callconv(windows.WINAPI) ?windows.HMODULE;
extern "kernel32" fn GetProcAddress(module: windows.HMODULE, name: [*:0]const u8) callconv(windows.WINAPI) ?windows.FARPROC;

const OSVERSIONINFOW = extern struct {
    dwOSVersionInfoSize: u32,
    dwMajorVersion: u32,
    dwMinorVersion: u32,
    dwBuildNumber: u32,
    dwPlatformId: u32,
    szCSDVersion: [128]u16,
};
extern "ntdll" fn RtlGetVersion(info: *OSVERSIONINFOW) callconv(windows.WINAPI) u32;

pub fn windowsVersion() u16 {
    if (comptime is_windows) {
        var info: OSVERSIONINFOW = std.mem.zeroes(OSVERSIONINFOW);
        info.dwOSVersionInfoSize = @sizeOf(OSVERSIONINFOW);
        if (RtlGetVersion(&info) != 0) return 0;
        return @as(u16, @truncate(info.dwMajorVersion)) << 8 |
            @as(u16, @truncate(info.dwMinorVersion));
    }
    return 0;
}

const RTLD_NOW: c_int = 2;
const RTLD_GLOBAL: c_int = 0x100;
extern fn dlopen(path: [*:0]const u8, mode: c_int) ?*anyopaque;
extern fn dlsym(handle: ?*anyopaque, name: [*:0]const u8) ?*anyopaque;

pub fn load(path: [*:0]const u8) ?*anyopaque {
    if (comptime is_windows) {
        const handle = LoadLibraryA(path) orelse return null;
        return @ptrCast(handle);
    }
    return dlopen(path, RTLD_NOW | RTLD_GLOBAL);
}

pub fn symbol(handle: ?*anyopaque, name: [*:0]const u8) ?*anyopaque {
    if (comptime is_windows) {
        const module: windows.HMODULE = if (handle) |h| @ptrCast(h) else (GetModuleHandleA(null) orelse return null);
        const proc = GetProcAddress(module, name) orelse return null;
        return @ptrCast(proc);
    }
    return dlsym(handle, name);
}

pub fn symbolOrdinal(handle: ?*anyopaque, ordinal: u16) ?*anyopaque {
    if (comptime is_windows) {
        const module: windows.HMODULE = if (handle) |h| @ptrCast(h) else (GetModuleHandleA(null) orelse return null);
        const proc = GetProcAddress(module, @ptrFromInt(@as(usize, ordinal))) orelse return null;
        return @ptrCast(proc);
    }
    return null;
}

const windows_default_libraries = [_][:0]const u8{
    "msvcrt.dll",
    "ucrtbase.dll",
    "ntdll.dll",
};

const linux_default_libraries = [_][:0]const u8{
    "libc.so.6",
    "libm.so.6",
    "libdl.so.2",
    "libpthread.so.0",
    "librt.so.1",
    "libutil.so.1",
    "libresolv.so.2",
};

/// Default libraries searched after the process namespace and explicit
/// `--lib` handles. These cover `--no-auto-link` packages and
/// symbols the build-time link indexes do not know about. Missing entries are
/// skipped by the caller (for example libdl/librt are merged into libc on
/// newer glibc systems).
pub fn defaultLibraries() []const [:0]const u8 {
    if (comptime is_windows) return &windows_default_libraries;
    if (comptime builtin.abi == .musl) return &.{};
    return &linux_default_libraries;
}
