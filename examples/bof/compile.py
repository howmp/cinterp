#!/usr/bin/env python3
"""Compile the bundled CS-Situational-Awareness-BOF sources into CIBs.

The upstream BOF sources use Cobalt Strike's `LIB$symbol` import naming and
Beacon API names. This driver keeps the checked-in sources readable and emits
a per-entry wrapper that:

  * defines BOF and includes the common headers;
  * maps `KERNEL32$Foo` / `MSVCRT$foo` / ... to normal WinAPI/CRT symbols;
  * maps BeaconPrintf/BeaconOutput to small local shims;
  * adds a `main` that calls the BOF `go(NULL, 0)` entry.

The result is a CIB for the requested Windows target, not a COFF BOF object.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
COMMON = HERE / "src" / "common"
SA = HERE / "src" / "SA"
DEFAULT_COMPILER = REPO / "build" / "cinterp-cc"

EXTRA_DECLS = {
    "probe": """\
int getaddrinfo(const char*, const char*, const struct addrinfo*, struct addrinfo**);
void freeaddrinfo(struct addrinfo*);
""",
    "netlocalgroup2": "BOOL ConvertSidToStringSidW(PSID, LPWSTR*);\n",
    "listdns": "int DnsGetCacheDataTable(PVOID);\n",
    "ipconfig": "const wchar_t *InetNtopW(int, const void *, wchar_t *, size_t);\n",
}

# `ipconfig` includes the IP helper headers itself, but it also relies on
# `_WIN32_WINNT` being visible before `bofdefs.h` pulls in `windows.h`. Seed the
# same include order here so MinGW exposes IP_ADAPTER_ADDRESSES and the
# Windows 10 gateway fields.
PRELUDE = {
    "ipconfig": """\
#define _WIN32_WINNT 0x0603
#include <winsock2.h>
#include <ws2ipdef.h>
#include <windows.h>
#include <iphlpapi.h>
""",
}


def prefix_macros() -> str:
    text = (COMMON / "bofdefs.h").read_text()
    names = sorted(set(re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\$[A-Za-z_][A-Za-z0-9_]*", text)))
    return "\n".join(f"#define {name} {name.split('$', 1)[1]}" for name in names) + "\n"


def wrapper(entry: Path, name: str, macros: Path) -> str:
    extra = EXTRA_DECLS.get(name, "")
    prelude = PRELUDE.get(name, "")
    return f"""\
{prelude}#define BOF
#include "{COMMON / 'bofdefs.h'}"
#include "{COMMON / 'beacon.h'}"
#include <lm.h>
#include "{macros}"
#undef MSVCRT$wcstok
#define MSVCRT$wcstok bof_wcstok
wchar_t *bof_wcstok(wchar_t *s, const wchar_t *d);
{extra}#define BeaconPrintf bof_BeaconPrintf
#define BeaconOutput bof_BeaconOutput
void bof_BeaconPrintf(int type, char *fmt, ...);
void bof_BeaconOutput(int type, char *data, int len);
#include "{entry}"
#include <stdarg.h>
#include <stdio.h>

int main(void) {{
    go(NULL, 0);
    return 0;
}}

wchar_t *bof_wcstok(wchar_t *s, const wchar_t *d) {{
    return wcstok(s, d, NULL);
}}

void bof_BeaconPrintf(int type, char *fmt, ...) {{
    (void)type;
    va_list ap;
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    fflush(stdout);
}}

void bof_BeaconOutput(int type, char *data, int len) {{
    (void)type;
    if (data && len > 0) {{
        fwrite(data, 1, (size_t)len, stdout);
        fflush(stdout);
    }}
}}
"""


def compile_one(
    compiler: Path,
    target: str,
    entry: Path,
    macros: Path,
    work: Path,
    out: Path,
) -> tuple[str, bool, str]:
    name = entry.parent.name
    src = work / f"{name}.c"
    src.write_text(wrapper(entry, name, macros))
    proc = subprocess.run(
        [str(compiler), "compile", str(src), "--target", target, "-o", str(out / f"{name}.cib")],
        env=dict(os.environ, CPATH=str(COMMON)),
        cwd=REPO,
        capture_output=True,
        text=True,
    )
    if proc.returncode == 0:
        return name, True, ""
    lines = (proc.stdout + proc.stderr).strip().splitlines()
    return name, False, "\n".join(lines[-8:])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=("x86_64-windows", "i686-windows"), default="x86_64-windows")
    parser.add_argument("--compiler", default=str(DEFAULT_COMPILER))
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    parser.add_argument("--out", default="", help="output directory (default: build/bof/<target>)")
    parser.add_argument("--allow-failures", action="store_true")
    args = parser.parse_args()

    compiler = Path(args.compiler)
    if not compiler.is_file():
        print(f"missing compiler: {compiler} (run make compiler)", file=sys.stderr)
        return 2
    entries = sorted(SA.glob("*/entry.c"))
    if not entries:
        print(f"no BOF entries under {SA}", file=sys.stderr)
        return 2
    out = Path(args.out) if args.out else REPO / "build" / "bof" / args.target
    out.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="cinterp-bof-") as tmp:
        work = Path(tmp)
        macros = work / "prefix_macros.h"
        macros.write_text(prefix_macros())
        results = []
        with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
            futures = [
                pool.submit(compile_one, compiler, args.target, entry, macros, work, out)
                for entry in entries
            ]
            for future in as_completed(futures):
                results.append(future.result())

    results.sort()
    failures = [(name, detail) for name, ok, detail in results if not ok]
    ok = len(results) - len(failures)
    print(f"{args.target}: {ok}/{len(results)} compiled into {out}")
    for name, detail in failures:
        print(f"--- {name} ---", file=sys.stderr)
        print(detail, file=sys.stderr)
    if failures and not args.allow_failures:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
