from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

from .llvm_ir.lower import compile_text
from .ffi.plan import UnsupportedFfi
from .link import cstdapi, winmd
from .link.imports import ImportTable
from .link.target import DEFAULT_TARGET, TARGETS


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="cinterp", description="C interpreter compiler")
    parser.add_argument("--version", action="version", version="cinterp 0.1.0")
    sub = parser.add_subparsers(dest="command", required=True)

    comp = sub.add_parser("compile", help="compile a C file to a CIPKG package")
    comp.add_argument("source")
    comp.add_argument("-o", "--output")
    comp.add_argument("--clang", default="clang")
    comp.add_argument("--target", choices=sorted(TARGETS), default=None)
    comp.add_argument("--keep-ir", action="store_true")
    comp.add_argument("--dump", action="store_true")
    comp.add_argument("--dump-imports", action="store_true")
    comp.add_argument("--cib-version", type=int, choices=(1, 2), default=2)
    comp.add_argument("--no-auto-link", action="store_true")
    comp.add_argument("--link-db", default=None, help="directory containing cstdapi.generated.json and winmd.generated.json.gz")
    return parser


def _compile(args: argparse.Namespace) -> int:
    if args.link_db:
        cstdapi.set_database(args.link_db)
        winmd.set_database(args.link_db)
    src = Path(args.source)
    if not src.is_file():
        print(f"cinterp: no such file: {src}", file=sys.stderr)
        return 2
    out = Path(args.output) if args.output else src.with_suffix(".cib")
    with tempfile.TemporaryDirectory(prefix="cinterp-") as td:
        ll = Path(td) / (src.stem + ".ll")
        target = TARGETS[args.target] if args.target else DEFAULT_TARGET
        cmd = [args.clang]
        if args.target:
            cmd.append("--target=" + target.triple)
        cmd += [
            "-S",
            "-emit-llvm",
            "-O0",
            "-g",
            "-fno-discard-value-names",
            str(src),
            "-o",
            str(ll),
        ]
        try:
            subprocess.run(cmd, check=True)
        except FileNotFoundError:
            print(f"cinterp: clang not found: {args.clang}", file=sys.stderr)
            return 2
        except subprocess.CalledProcessError as exc:
            return exc.returncode or 1
        ir_text = ll.read_text()
        if args.keep_ir:
            kept = out.with_suffix(".ll")
            kept.write_text(ir_text)

    try:
        imports = ImportTable()
        package, module, plan_bytes, functions, plans = compile_text(
            ir_text,
            str(src),
            abi=target.abi,
            ptr_size=target.ptr_bits // 8,
            target=target,
            imports=imports,
            cib_version=args.cib_version,
            auto_link=not args.no_auto_link,
        )
    except (UnsupportedFfi, ValueError) as exc:
        print(f"cinterp: {exc}", file=sys.stderr)
        return 1

    try:
        out.write_bytes(package)
    except OSError as exc:
        print(f"cinterp: cannot write {out}: {exc}", file=sys.stderr)
        return 1
    print(
        f"{out}: {len(module)}B module, {len(plan_bytes)}B plans, "
        f"{len(functions)} functions, {len(plans.plans)} external plans, "
        f"target={target.name}, cib=v{args.cib_version}, imports={len(imports.entries)}"
    )
    if args.dump:
        for fn in functions:
            print(f"  {fn.name}: params={len(fn.params)} locals={fn.local_count} code={len(fn.code)}")
        for i, plan in enumerate(plans.plans):
            print(f"  plan[{i}] {plan.name}: args={len(plan.args)} ret={len(plan.ret_locs)} stack={plan.stack_size}")
    if args.dump_imports:
        for entry in imports.entries:
            providers = ", ".join(f"{p.name}:{p.symbol}" for p in entry.providers)
            print(f"  import[plan {entry.plan_index}] {entry.name}: {providers or '(unresolved)'}")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    if args.command == "compile":
        return _compile(args)
    return 2
