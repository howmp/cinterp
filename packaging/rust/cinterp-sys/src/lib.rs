//! Raw FFI bindings plus a small safe wrapper for the cinterp C embedding ABI.
//!
//! The native library is found through `CINTERP_LIB_DIR`/`CINTERP_INCLUDE_DIR`
//! when set, otherwise through `../../lib` and `../../include` relative to this
//! crate (the layout used by cinterp release tarballs).

#![allow(non_camel_case_types)]

use std::ffi::{c_char, c_int, CStr, CString};
use std::marker::PhantomData;
use std::path::Path;

pub const CI_OK: c_int = 0;
pub const CI_ERROR: c_int = -1;
pub const CI_E_INVALID_ARGUMENT: c_int = -2;
pub const CI_E_OUT_OF_MEMORY: c_int = -3;
pub const CI_E_BAD_PACKAGE: c_int = -4;
pub const CI_E_TARGET: c_int = -5;
pub const CI_E_PLANS: c_int = -6;
pub const CI_E_LINK: c_int = -7;
pub const CI_E_ENTRY: c_int = -8;
pub const CI_E_RESOURCE: c_int = -9;
pub const CI_E_RUNTIME: c_int = -10;
pub const CI_E_DESTROYED: c_int = -11;

pub const CI_ABI_VERSION: c_int = 2;
pub const DEFAULT_MEMORY: usize = 1024 * 1024;
pub const MAX_MEMORY: usize = 16 * 1024 * 1024;

#[repr(C)]
pub struct ci_vm {
    _private: [u8; 0],
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ci_vm_config {
    pub struct_size: u32,
    pub flags: u32,
    pub stack_size: usize,
    pub memory_size: usize,
}

impl Default for ci_vm_config {
    fn default() -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            flags: 0,
            stack_size: 0,
            memory_size: 0,
        }
    }
}

extern "C" {
    pub fn ci_vm_create(stack_size: usize) -> *mut ci_vm;
    pub fn ci_vm_create_ex(config: *const ci_vm_config) -> *mut ci_vm;
    pub fn ci_vm_destroy(vm: *mut ci_vm);
    pub fn ci_vm_load_module(vm: *mut ci_vm, data: *const u8, size: usize) -> c_int;
    pub fn ci_vm_load_plans(vm: *mut ci_vm, data: *const u8, size: usize) -> c_int;
    pub fn ci_vm_load_package(vm: *mut ci_vm, data: *const u8, size: usize) -> c_int;
    pub fn ci_vm_load_library(vm: *mut ci_vm, path: *const c_char) -> c_int;
    pub fn ci_vm_run(vm: *mut ci_vm, entry: *const c_char) -> c_int;
    pub fn ci_vm_run_args(
        vm: *mut ci_vm,
        entry: *const c_char,
        argc: c_int,
        argv: *const *const c_char,
    ) -> c_int;
    pub fn ci_vm_result(vm: *const ci_vm) -> i64;
    pub fn ci_vm_last_error(vm: *const ci_vm) -> *const c_char;
    pub fn ci_vm_last_error_code(vm: *const ci_vm) -> c_int;
    pub fn ci_vm_clear_error(vm: *mut ci_vm) -> c_int;
    pub fn ci_abi_version() -> c_int;
    pub fn ci_version() -> *const c_char;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error {
    pub code: c_int,
    pub message: String,
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "cinterp error {}: {}", self.code, self.message)
    }
}

impl std::error::Error for Error {}

/// A single-threaded VM. `Vm` is neither `Send` nor `Sync`.
pub struct Vm {
    raw: *mut ci_vm,
    _single_thread: PhantomData<*mut ()>,
}

impl Vm {
    pub fn new(stack_size: usize) -> Option<Self> {
        let raw = unsafe { ci_vm_create(stack_size) };
        Self::from_raw(raw)
    }

    pub fn with_config(config: &ci_vm_config) -> Option<Self> {
        let raw = unsafe { ci_vm_create_ex(config) };
        Self::from_raw(raw)
    }

    fn from_raw(raw: *mut ci_vm) -> Option<Self> {
        if raw.is_null() {
            None
        } else {
            Some(Self {
                raw,
                _single_thread: PhantomData,
            })
        }
    }

    fn check(&self, code: c_int) -> Result<(), Error> {
        if code == CI_OK {
            Ok(())
        } else {
            Err(Error {
                code,
                message: self.last_error(),
            })
        }
    }

    pub fn load_package(&mut self, bytes: &[u8]) -> Result<(), Error> {
        let code = unsafe { ci_vm_load_package(self.raw, bytes.as_ptr(), bytes.len()) };
        self.check(code)
    }

    pub fn load_module(&mut self, bytes: &[u8]) -> Result<(), Error> {
        let code = unsafe { ci_vm_load_module(self.raw, bytes.as_ptr(), bytes.len()) };
        self.check(code)
    }

    pub fn load_plans(&mut self, bytes: &[u8]) -> Result<(), Error> {
        let code = unsafe { ci_vm_load_plans(self.raw, bytes.as_ptr(), bytes.len()) };
        self.check(code)
    }

    pub fn load_library(&mut self, path: impl AsRef<Path>) -> Result<(), Error> {
        let path = path.as_ref().to_str().ok_or_else(|| Error {
            code: CI_E_INVALID_ARGUMENT,
            message: "library path is not valid UTF-8".into(),
        })?;
        let cpath = CString::new(path).map_err(|_| Error {
            code: CI_E_INVALID_ARGUMENT,
            message: "library path contains NUL".into(),
        })?;
        let code = unsafe { ci_vm_load_library(self.raw, cpath.as_ptr()) };
        self.check(code)
    }

    pub fn run(&mut self, entry: &str) -> Result<(), Error> {
        let entry = CString::new(entry).map_err(|_| Error {
            code: CI_E_INVALID_ARGUMENT,
            message: "entry name contains NUL".into(),
        })?;
        let code = unsafe { ci_vm_run(self.raw, entry.as_ptr()) };
        self.check(code)
    }

    pub fn run_args<S: AsRef<str>>(&mut self, entry: &str, args: &[S]) -> Result<(), Error> {
        let entry = CString::new(entry).map_err(|_| Error {
            code: CI_E_INVALID_ARGUMENT,
            message: "entry name contains NUL".into(),
        })?;
        let mut owned = Vec::with_capacity(args.len());
        for arg in args {
            owned.push(CString::new(arg.as_ref()).map_err(|_| Error {
                code: CI_E_INVALID_ARGUMENT,
                message: "argument contains NUL".into(),
            })?);
        }
        let mut ptrs: Vec<*const c_char> = owned.iter().map(|s| s.as_ptr()).collect();
        let code = unsafe {
            ci_vm_run_args(
                self.raw,
                entry.as_ptr(),
                ptrs.len() as c_int,
                if ptrs.is_empty() {
                    std::ptr::null()
                } else {
                    ptrs.as_mut_ptr()
                },
            )
        };
        self.check(code)
    }

    pub fn result(&self) -> i64 {
        unsafe { ci_vm_result(self.raw) }
    }

    pub fn last_error(&self) -> String {
        let ptr = unsafe { ci_vm_last_error(self.raw) };
        if ptr.is_null() {
            String::new()
        } else {
            unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned()
        }
    }

    pub fn last_error_code(&self) -> c_int {
        unsafe { ci_vm_last_error_code(self.raw) }
    }

    pub fn clear_error(&mut self) -> c_int {
        unsafe { ci_vm_clear_error(self.raw) }
    }
}

impl Drop for Vm {
    fn drop(&mut self) {
        unsafe { ci_vm_destroy(self.raw) };
    }
}

pub fn abi_version() -> c_int {
    unsafe { ci_abi_version() }
}

pub fn version() -> String {
    let ptr = unsafe { ci_version() };
    if ptr.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned()
    }
}
