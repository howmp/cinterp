//! Run a CIB package through the safe wrapper and print its result.
//!
//! ```sh
//! cargo run --offline --example run_hello -- ../../hello.cib --expect 42
//! ```
//!
//! The package must be built for the target this crate was linked against.
//! `--expect N` turns the example into a smoke test: it exits non-zero when
//! the VM result differs from N. Exit status is 2 for usage errors.

use cinterp_sys::Vm;

fn usage(program: &str) -> ! {
    eprintln!("usage: {program} <package.cib> [--expect N]");
    std::process::exit(2);
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let program = std::env::args().next().unwrap_or_else(|| "run_hello".into());
    let mut package: Option<String> = None;
    let mut expect: Option<i64> = None;

    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--expect" => {
                let value = args.next().unwrap_or_else(|| usage(&program));
                expect = Some(value.parse().map_err(|_| {
                    format!("--expect needs an integer, got {value:?}")
                })?);
            }
            "-h" | "--help" => usage(&program),
            other if other.starts_with('-') => {
                eprintln!("unknown option: {other}");
                usage(&program);
            }
            other => {
                if package.replace(other.to_string()).is_some() {
                    usage(&program);
                }
            }
        }
    }

    let package = package.unwrap_or_else(|| usage(&program));
    let bytes = std::fs::read(&package)?;
    let mut vm = Vm::new(0).ok_or("ci_vm_create returned NULL")?;
    vm.load_package(&bytes)?;
    vm.run("main")?;

    let result = vm.result();
    println!("result = {result}");
    if let Some(expected) = expect {
        if result != expected {
            return Err(format!("expected result {expected}, got {result}").into());
        }
    }
    Ok(())
}
