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

pub fn defaultC() ?*anyopaque {
    if (comptime is_windows) {
        if (load("msvcrt.dll")) |h| return h;
        return load("ucrtbase.dll");
    }
    if (comptime builtin.abi == .musl) return null;
    if (load("libc.so.6")) |h| return h;
    return load("libc.so");
}
