# Examples

Examples are grouped by topic:

- `basics/` — core C language and arithmetic examples: `hello`, arrays,
  structs, packed structs, bitfields, `long double`, and float math.
- `ffi/` — native calls, callbacks, aggregate returns, HFA, varargs, and
  Win32 `stdcall`/`fastcall`/`thiscall` examples. Files ending in `_helper.c`
  are shared-library helpers for the matching example.
- `linux/` — Linux command examples: `ifconfig`, `ps`, `netstat`, and `route`.
- `windows/` — Win32 examples that include `<windows.h>` directly instead of
  declaring WinAPI prototypes: `winapi.c`, `system_info.c`, `process_info.c`,
  and `file_io.c`. They run on Windows or under Wine via `make test-winapi`.
- `bof/` — the CS-Situational-Awareness-BOF compile harness and normalized BOF
  sources.
- `keygenme/` — a name/serial keygenme whose CIB bytecode is embedded into a
  Zig host; `make keygenme` builds standalone Linux x86-64, Linux ARM64,
  Windows x64, and Windows x86 executables, writes CIB dumps, and includes a
  Python keygen.

Most examples can be compiled and run with:

```sh
make compiler runtime
./build/cinterp-cc compile examples/basics/hello.c -o build/hello.cib
./runtime/zig-out/bin/cinterp-run build/hello.cib
```
