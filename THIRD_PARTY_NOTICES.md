# Third-party notices

cinterp itself is licensed under the MIT License; see `LICENSE`.

The release artifacts contain generated link metadata derived from the
following upstream projects. The generated files contain symbol names,
availability flags and provider library names; no upstream source code is
vendored.

## winmd

- Source: https://github.com/howmp/winmd
- Upstream commit used: 9b8027802f05b1c84a8630e7f739eb519add9767
- License: MIT (recorded in `compiler/src/cinterp/link/winmd.generated.json.gz`)
- Generated file: `compiler/src/cinterp/link/winmd.generated.json.gz`

MIT License

Copyright (c) winmd contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## cstdapi

- Source: https://github.com/howmp/cstdapi
- Upstream commit used: abba9c4569939b4eca640419a7bf2c97e8b550ee
- License: the upstream snapshot does not declare a license. cinterp only
  consumes the generated factual symbol-availability table
  (`compiler/src/cinterp/link/cstdapi.generated.json`); no upstream source
  code, documentation or other creative text is included. If the upstream
  project later publishes a license, this notice and the generated data must
  be revalidated against it.
- Generated file: `compiler/src/cinterp/link/cstdapi.generated.json`

## Build and test toolchain (not redistributed)

The compiler and runtime require the following external tools at build time.
They are not included in cinterp release tarballs:

- Zig 0.13 (MIT) — builds the runtime and supplies MinGW headers for Windows
  targets.
- Clang/LLVM (Apache-2.0 with LLVM exceptions) — emits LLVM IR that the
  compiler lowers.
- Python 3.10+ (PSF-2.0) — runs the build-time compiler.
- MinGW-w64 headers and import libraries (bundled with Zig) — used when
  compiling Windows targets.

Runtime FFI calls resolve symbols from the host C runtime (glibc on Linux,
UCRT/MSVCRT/NTDLL on Windows). Those libraries are provided by the operating
system and are not redistributed.
