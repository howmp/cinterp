use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-env-changed=CINTERP_LIB_DIR");
    println!("cargo:rerun-if-env-changed=CINTERP_INCLUDE_DIR");

    let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let lib_dir = env::var("CINTERP_LIB_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| manifest.join("../../lib"));
    let include_dir = env::var("CINTERP_INCLUDE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| manifest.join("../../include"));

    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    println!("cargo:include={}", include_dir.display());
    println!("cargo:rustc-link-lib=dylib=cinterp");

    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        println!("cargo:rustc-link-lib=dylib=dl");
        println!("cargo:rustc-link-lib=dylib=pthread");
        println!("cargo:rustc-link-lib=dylib=m");
    }
}
