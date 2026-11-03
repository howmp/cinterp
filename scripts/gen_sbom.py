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
# and the glibc `abilists` table) that `compiler-zig/tools/gen_link_index.zig`
# turns into the external-symbol index embedded in `cinterp-cc`.
ZIG_VERSION = "0.13.0"


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


def validate_document(document: dict) -> None:
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--name", default="cinterp")
    parser.add_argument("--version", required=True)
    parser.add_argument("--target", default="native")
    args = parser.parse_args()

    root = args.root.resolve()
    if not root.is_dir():
        raise SystemExit(f"not a directory: {root}")
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

    # Only the `cinterp-cc` compiler embeds the generated external-symbol
    # index; the runtime-only tarballs (win64/win32/arm64) do not.
    ships_compiler = (root / "bin" / "cinterp-cc").is_file()

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

    # `compiler-zig/src/win_defs.zig` embeds a table generated from the
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
                    "compiler-zig/tools/gen_link_index.zig from the MinGW-w64 "
                    "lib32/lib64/lib-common .def files shipped with Zig. The "
                    "ZPL 2.1 attribution is recorded in this SBOM."
                ),
            }
        )
        # `compiler-zig/src/libc_defs.zig` embeds a symbol -> soname table
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
                    "compiler-zig/tools/gen_link_index.zig from Zig's "
                    "libc/glibc/abilists symbol/version table (glibc ABI lists). "
                    "Only factual symbol names and library assignments are "
                    "reproduced; no glibc code is copied."
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
    validate_document(document)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2, sort_keys=False) + "\n")
    print(f"SBOM: {args.output} ({len(files)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
