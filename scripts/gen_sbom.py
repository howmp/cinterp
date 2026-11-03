#!/usr/bin/env python3
"""Generate an SPDX 2.3 JSON SBOM for a cinterp release directory."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path

TOOL = "Tool: cinterp-gen-sbom"

# Zig release that supplies the build-time link metadata (MinGW `.def` files
# and the glibc `abilists` table) that `compiler/tools/gen_link_index.zig`
# turns into the external-symbol index embedded in `cinterp-cc`.
ZIG_VERSION = "0.13.0"

# Written next to `bin/cinterp-cc`, i.e. only into tarballs that ship the
# compiler. It is part of the SBOM file list, so it has to exist before
# `file_records()` runs.
NOTICE_NAME = "THIRD_PARTY_NOTICES.md"


def notice_text(version: str, target: str) -> str:
    """Human-readable attribution for the derived data in `cinterp-cc`."""
    return f"""# Third-party notices — cinterp {version} ({target})

This tarball ships `cinterp-cc`, which embeds an external-symbol index
generated at build time from data bundled with Zig {ZIG_VERSION}. That derived
data is redistributed under the terms below. No upstream source code is
included.

## MinGW-w64 export definitions (ZPL-2.1)

- SPDX package: `mingw-w64-defs`
- Upstream: https://github.com/mingw-w64/mingw-w64
- Input files: the `lib32`/`lib64`/`lib-common` `.def` export lists shipped
  with Zig.
- License: ZPL-2.1 (Zope Public License 2.1)
- Copyright: Copyright (c) 2009-2013 by the mingw-w64 project

Reproduced data: the symbol name -> DLL and calling-convention mapping used to
auto-link Windows API imports (`compiler/src/win_defs.zig`). Only factual API
metadata is copied.

## glibc ABI lists (LGPL-2.1-or-later)

- SPDX package: `glibc-abilists`
- Upstream: https://sourceware.org/glibc/
- Input files: Zig's `libc/glibc/abilists` symbol/version table.
- License: LGPL-2.1-or-later
- Copyright: Copyright (C) Free Software Foundation, Inc.

Reproduced data: symbol name -> versioned soname mappings used by
`compiler/src/libc_defs.zig`. Only factual symbol names, versions and library
assignments are copied. The runtime resolves glibc symbols dynamically at run
time like any other ELF program; no glibc source code is copied or statically
linked.

## Build tools (not redistributed)

Zig {ZIG_VERSION} (MIT), LLVM/clang (Apache-2.0 WITH LLVM-exception) and
Python 3.10+ (PSF-2.0) are build-time dependencies. They are not bundled in
this tarball.

## Scope

This file is emitted only for tarballs that contain `bin/cinterp-cc` (today the
Linux x86-64 tarball). Runtime-only tarballs (win64/win32/arm64) contain no
derived MinGW-w64 or glibc data, so they ship no notice file and their
`SBOM.spdx.json` does not name those packages. The same facts are recorded
programmatically in `SBOM.spdx.json`.
"""


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sha1(path: Path) -> str:
    h = hashlib.sha1()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def verification_code(root: Path) -> str:
    digests = sorted(sha1(path) for path in root.rglob("*") if path.is_file())
    return hashlib.sha1("".join(digests).encode("ascii")).hexdigest()


def spdx_id(prefix: str, value: str) -> str:
    clean = re.sub(r"[^A-Za-z0-9.-]", "-", value)
    return f"SPDXRef-{prefix}-{clean}"


def file_records(root: Path) -> list[dict]:
    records = []
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        rel = path.relative_to(root).as_posix()
        records.append(
            {
                "fileName": f"./{rel}",
                "SPDXID": spdx_id("File", rel),
                "checksums": [{"algorithm": "SHA256", "checksumValue": sha256(path)}],
                "licenseConcluded": "NOASSERTION",
                "licenseInfoInFiles": ["NOASSERTION"],
                "copyrightText": "NOASSERTION",
            }
        )
    return records


def validate_document(document: dict, ships_compiler: bool) -> None:
    """Check the referential integrity SPDX consumers rely on.

    Every relationship endpoint must exist as a package, a file or the
    document id, and element ids must be unique. Keeps a bad edit
    to the package list from shipping an unusable SBOM.
    """
    known = {"SPDXRef-DOCUMENT"}
    for package in document["packages"]:
        element_id = package["SPDXID"]
        if element_id in known:
            raise SystemExit(f"duplicate SPDX element id: {element_id}")
        known.add(element_id)
    for record in document["files"]:
        element_id = record["SPDXID"]
        if element_id in known:
            raise SystemExit(f"duplicate SPDX element id: {element_id}")
        known.add(element_id)
    for relationship in document["relationships"]:
        for key in ("spdxElementId", "relatedSpdxElement"):
            if relationship[key] not in known:
                raise SystemExit(
                    f"relationship {key} references unknown id: {relationship[key]}"
                )
    names = [package["name"] for package in document["packages"]]
    for removed in ("winmd", "cstdapi"):
        if removed in names:
            raise SystemExit(f"SBOM must not reference the removed {removed} package")

    file_names = {record["fileName"] for record in document["files"]}
    notice_entry = f"./{NOTICE_NAME}"
    derived = {"mingw-w64-defs", "glibc-abilists"}
    if ships_compiler:
        if notice_entry not in file_names:
            raise SystemExit(
                f"compiler tarball SBOM is missing {NOTICE_NAME}; "
                "generate it before the file list"
            )
        missing = derived - set(names)
        if missing:
            raise SystemExit(
                "compiler tarball SBOM is missing derived-data packages: "
                + ", ".join(sorted(missing))
            )
    else:
        if notice_entry in file_names:
            raise SystemExit(f"runtime-only SBOM must not include {NOTICE_NAME}")
        claimed = derived & set(names)
        if claimed:
            raise SystemExit(
                "runtime-only SBOM must not claim derived-data packages: "
                + ", ".join(sorted(claimed))
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--name", default="cinterp")
    parser.add_argument("--version", required=True)
    parser.add_argument("--target", default="native")
    parser.add_argument(
        "--no-notice",
        action="store_true",
        help=(
            f"do not write {NOTICE_NAME}; rejected when bin/cinterp-cc is "
            "present because compiler tarballs must ship the notice"
        ),
    )
    args = parser.parse_args()

    root = args.root.resolve()
    if not root.is_dir():
        raise SystemExit(f"not a directory: {root}")

    # Only the `cinterp-cc` compiler embeds the generated external-symbol
    # index; the runtime-only tarballs (win64/win32/arm64) do not.
    ships_compiler = (root / "bin" / "cinterp-cc").is_file()

    # Emit (or drop) the notice before hashing, so it appears in the SBOM file
    # list, the package verification code and the tarball.
    notice_path = root / NOTICE_NAME
    if ships_compiler:
        if args.no_notice:
            raise SystemExit(
                f"{NOTICE_NAME} is required when bin/cinterp-cc is packaged; "
                "drop --no-notice"
            )
        notice_path.write_text(notice_text(args.version, args.target))
        print(f"notice: {notice_path}")
    elif notice_path.exists():
        notice_path.unlink()
        print(f"notice: removed stale {notice_path} (runtime-only tree)")

    files = file_records(root)
    digest = hashlib.sha256()
    for record in files:
        digest.update(record["fileName"].encode())
        digest.update(record["checksums"][0]["checksumValue"].encode())
    namespace = uuid.uuid5(
        uuid.NAMESPACE_URL, f"cinterp:{args.version}:{args.target}:{digest.hexdigest()}"
    )

    cinterp_id = "SPDXRef-Package-cinterp"
    zig_id = "SPDXRef-Package-zig"
    llvm_id = "SPDXRef-Package-llvm"
    python_id = "SPDXRef-Package-python"
    mingw_id = "SPDXRef-Package-mingw-w64-defs"
    glibc_abilists_id = "SPDXRef-Package-glibc-abilists"

    packages = [
        {
            "name": args.name,
            "SPDXID": cinterp_id,
            "versionInfo": args.version,
            "downloadLocation": "NOASSERTION",
            "filesAnalyzed": True,
            "licenseConcluded": "MIT",
            "licenseDeclared": "MIT",
            "copyrightText": "Copyright (c) 2026 cinterp contributors",
            "packageVerificationCode": {
                "packageVerificationCodeValue": verification_code(root)
            },
            "comment": f"target={args.target}",
        },
        {
            "name": "zig",
            "SPDXID": zig_id,
            "versionInfo": ZIG_VERSION,
            "downloadLocation": "https://ziglang.org/download/",
            "filesAnalyzed": False,
            "licenseConcluded": "MIT",
            "licenseDeclared": "MIT",
            "copyrightText": "NOASSERTION",
        },
        {
            "name": "clang-llvm",
            "SPDXID": llvm_id,
            "versionInfo": "NOASSERTION",
            "downloadLocation": "https://llvm.org/",
            "filesAnalyzed": False,
            "licenseConcluded": "Apache-2.0 WITH LLVM-exception",
            "licenseDeclared": "Apache-2.0 WITH LLVM-exception",
            "copyrightText": "NOASSERTION",
        },
        {
            "name": "python",
            "SPDXID": python_id,
            "versionInfo": "3.10+",
            "downloadLocation": "https://www.python.org/",
            "filesAnalyzed": False,
            "licenseConcluded": "PSF-2.0",
            "licenseDeclared": "PSF-2.0",
            "copyrightText": "NOASSERTION",
        },
    ]

    # `compiler/src/win_defs.zig` embeds a table generated from the
    # MinGW-w64 `.def` export lists that Zig bundles. Only the derived
    # symbol -> DLL/callconv index is redistributed, never upstream sources.
    if ships_compiler:
        packages.append(
            {
                "name": "mingw-w64-defs",
                "SPDXID": mingw_id,
                "versionInfo": f"bundled-with-zig-{ZIG_VERSION}",
                "downloadLocation": "https://github.com/mingw-w64/mingw-w64",
                "filesAnalyzed": False,
                "licenseConcluded": "ZPL-2.1",
                "licenseDeclared": "ZPL-2.1",
                "copyrightText": "Copyright (c) 2009 - 2013 by the mingw-w64 project",
                "comment": (
                    "Derived data: the Windows external-symbol index embedded in "
                    "cinterp-cc is generated at build time by "
                    "compiler/tools/gen_link_index.zig from the MinGW-w64 "
                    "lib32/lib64/lib-common .def files shipped with Zig. The "
                    "ZPL 2.1 attribution is recorded in this SBOM and in "
                    f"{NOTICE_NAME}."
                ),
            }
        )
        # `compiler/src/libc_defs.zig` embeds a symbol -> soname table
        # generated from the glibc abilists that Zig bundles for its own
        # glibc linking support.
        packages.append(
            {
                "name": "glibc-abilists",
                "SPDXID": glibc_abilists_id,
                "versionInfo": f"bundled-with-zig-{ZIG_VERSION}",
                "downloadLocation": "https://sourceware.org/glibc/",
                "filesAnalyzed": False,
                "licenseConcluded": "LGPL-2.1-or-later",
                "licenseDeclared": "LGPL-2.1-or-later",
                "copyrightText": "Copyright (C) Free Software Foundation, Inc.",
                "comment": (
                    "Derived data: the Linux external-symbol index embedded in "
                    "cinterp-cc is generated at build time by "
                    "compiler/tools/gen_link_index.zig from Zig's "
                    "libc/glibc/abilists symbol/version table (glibc ABI lists). "
                    "Only factual symbol names and library assignments are "
                    "reproduced; no glibc code is copied. The "
                    "LGPL-2.1-or-later attribution is recorded in this SBOM and "
                    f"in {NOTICE_NAME}."
                ),
            }
        )

    relationships = [
        {
            "spdxElementId": "SPDXRef-DOCUMENT",
            "relationshipType": "DESCRIBES",
            "relatedSpdxElement": cinterp_id,
        }
    ]
    for record in files:
        relationships.append(
            {
                "spdxElementId": cinterp_id,
                "relationshipType": "CONTAINS",
                "relatedSpdxElement": record["SPDXID"],
            }
        )
    if ships_compiler:
        for dep in (mingw_id, glibc_abilists_id):
            relationships.append(
                {
                    "spdxElementId": dep,
                    "relationshipType": "DEPENDENCY_OF",
                    "relatedSpdxElement": cinterp_id,
                }
            )
    for tool in (zig_id, llvm_id, python_id):
        relationships.append(
            {
                "spdxElementId": tool,
                "relationshipType": "BUILD_TOOL_OF",
                "relatedSpdxElement": cinterp_id,
            }
        )

    document = {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"{args.name}-{args.version}-{args.target}",
        "documentNamespace": f"urn:uuid:{namespace}",
        "creationInfo": {
            "created": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "creators": [TOOL, f"Tool: cinterp {args.version}"],
        },
        "packages": packages,
        "files": files,
        "relationships": relationships,
    }
    validate_document(document, ships_compiler)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2, sort_keys=False) + "\n")
    print(f"SBOM: {args.output} ({len(files)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
