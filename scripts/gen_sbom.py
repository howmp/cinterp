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
    winmd_id = "SPDXRef-Package-winmd"
    cstdapi_id = "SPDXRef-Package-cstdapi"
    zig_id = "SPDXRef-Package-zig"
    llvm_id = "SPDXRef-Package-llvm"
    python_id = "SPDXRef-Package-python"

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
            "name": "winmd",
            "SPDXID": winmd_id,
            "versionInfo": "9b8027802f05b1c84a8630e7f739eb519add9767",
            "downloadLocation": "https://github.com/howmp/winmd",
            "filesAnalyzed": False,
            "licenseConcluded": "MIT",
            "licenseDeclared": "MIT",
            "copyrightText": "NOASSERTION",
        },
        {
            "name": "cstdapi",
            "SPDXID": cstdapi_id,
            "versionInfo": "abba9c4569939b4eca640419a7bf2c97e8b550ee",
            "downloadLocation": "https://github.com/howmp/cstdapi",
            "filesAnalyzed": False,
            "licenseConcluded": "NOASSERTION",
            "licenseDeclared": "NOASSERTION",
            "copyrightText": "NOASSERTION",
            "comment": "Upstream snapshot does not declare a license; only generated symbol data is consumed.",
        },
        {
            "name": "zig",
            "SPDXID": zig_id,
            "versionInfo": "0.13.0",
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
    for dep in (winmd_id, cstdapi_id):
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
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2, sort_keys=False) + "\n")
    print(f"SBOM: {args.output} ({len(files)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
