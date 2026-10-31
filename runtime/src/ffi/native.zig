const std = @import("std");
const builtin = @import("builtin");

const is_windows = builtin.os.tag == .windows;

const windows = std.os.windows;

extern "kernel32" fn LoadLibraryA(name: [*:0]const u8) callconv(windows.WINAPI) ?windows.HMODULE;
extern "kernel32" fn GetModuleHandleA(name: ?[*:0]const u8) callconv(windows.WINAPI) ?windows.HMODULE;
extern "kernel32" fn GetProcAddress(module: windows.HMODULE, name: [*:0]const u8) callconv(windows.WINAPI) ?windows.FARPROC;

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

pub fn alias(name: []const u8) ?[*:0]const u8 {
    if (comptime is_windows) {
        if (std.mem.eql(u8, name, "snprintf")) return "_snprintf";
        if (std.mem.eql(u8, name, "vsnprintf")) return "_vsnprintf";
    }
    return null;
}

pub fn defaultC() ?*anyopaque {
    if (comptime is_windows) {
        if (load("msvcrt.dll")) |h| return h;
        return load("ucrtbase.dll");
    }
    if (load("libc.so.6")) |h| return h;
    return load("libc.so");
}
