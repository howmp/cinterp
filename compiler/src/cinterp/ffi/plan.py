"""Compile-time x86-64 SysV FFI plans.

The compiler describes each external call as a list of argument locations
(GPR/XMM/stack) plus return locations. The runtime marshals VM values into an
arg block and the fixed assembly engine performs the native call.
"""
from __future__ import annotations

from dataclasses import dataclass


class UnsupportedFfi(Exception):
    pass


@dataclass
class Loc:
    kind: str  # gpr/xmm/stack/sret/rax/rdx/xmm0/xmm1
    index: int = 0
    size: int = 0
    offset: int = 0


@dataclass
class ArgPlan:
    locs: list[Loc]
    size: int
    alignment: int = 8
    is_struct: bool = False


@dataclass
class CallPlan:
    name: str
    args: list[ArgPlan]
    ret_locs: list[Loc]
    stack_size: int = 0
    sret: bool = False
    sse_count: int = 0
    ret_size: int = 0


def _type_info(ty: str) -> tuple[str, int]:
    ty = ty.strip()
    if ty.startswith("ptr"):
        return "gpr", 8
    if ty == "float":
        return "xmm", 4
    if ty == "double":
        return "xmm", 8
    if ty == "void":
        return "void", 0
    if ty.startswith("i"):
        try:
            bits = int(ty[1:])
        except ValueError:
            raise UnsupportedFfi(f"unsupported type {ty!r}")
        return "gpr", max(1, (bits + 7) // 8)
    raise UnsupportedFfi(
        f"FFI plan for aggregate type {ty!r} is not implemented in the v1 compiler"
    )


def _align8(n: int) -> int:
    return (n + 7) // 8 * 8


def _return_locs(ret_type: str) -> tuple[list[Loc], int]:
    ty = ret_type.strip()
    if ty.startswith("{") and ty.endswith("}"):
        fields = [f.strip() for f in ty[1:-1].split(",") if f.strip()]
        classes: list[str | None] = [None, None]
        offset = 0
        max_align = 1
        for field in fields:
            kind, size = _type_info(field)
            if kind == "void":
                raise UnsupportedFfi("void aggregate field")
            idx = offset // 8
            if idx > 1:
                raise UnsupportedFfi(f"return aggregate with >2 eightbytes: {ty}")
            if classes[idx] is not None and classes[idx] != kind:
                classes[idx] = "gpr"
            else:
                classes[idx] = kind
            offset += size
            max_align = max(max_align, min(size, 8))
        total = (offset + max_align - 1) // max_align * max_align
        gpr = 0
        xmm = 0
        locs: list[Loc] = []
        for idx, cls in enumerate(classes):
            if cls is None:
                continue
            size = min(8, total - idx * 8)
            if cls == "gpr":
                locs.append(Loc("rax" if gpr == 0 else "rdx", 0, size, idx * 8))
                gpr += 1
            else:
                locs.append(Loc("xmm0" if xmm == 0 else "xmm1", 0, size, idx * 8))
                xmm += 1
        return locs, total
    kind, size = _type_info(ty)
    if kind == "void":
        return [], 0
    if kind == "gpr":
        return [Loc("rax", 0, size, 0)], size
    if kind == "xmm":
        return [Loc("xmm0", 0, size, 0)], size
    raise UnsupportedFfi(f"unsupported return type {ret_type!r}")


def build_sysv_plan(
    name: str,
    ret_type: str,
    arg_types: list[str],
    is_varargs: bool = False,
    sret_idx: int | None = None,
    sret_size: int = 0,
    byval_sizes: list[int] | None = None,
) -> CallPlan:
    gpr = 1 if sret_idx is not None else 0
    xmm = 0
    stack_size = 0
    arg_offset = 0
    args: list[ArgPlan] = []
    sse_count = 0

    for i, ty in enumerate(arg_types):
        if sret_idx == i:
            args.append(ArgPlan([Loc("sret", 0, 8, arg_offset)], 8, 8, False))
            arg_offset += 8
            continue
        if byval_sizes and byval_sizes[i] > 0:
            size = byval_sizes[i]
            arg_offset = _align8(arg_offset)
            stack_size = _align8(stack_size)
            loc = Loc("stack", stack_size, size, arg_offset)
            args.append(ArgPlan([loc], size, 8, True))
            stack_size += _align8(size)
            arg_offset += size
            continue
        kind, size = _type_info(ty)
        if kind == "void":
            raise UnsupportedFfi("void argument")
        if kind == "gpr":
            if gpr < 6:
                loc = Loc("gpr", gpr, size, arg_offset)
                gpr += 1
            else:
                stack_size = _align8(stack_size)
                loc = Loc("stack", stack_size, size, arg_offset)
                stack_size += 8
        else:
            if xmm < 8:
                loc = Loc("xmm", xmm, size, arg_offset)
                xmm += 1
                sse_count += 1
            else:
                stack_size = _align8(stack_size)
                loc = Loc("stack", stack_size, size, arg_offset)
                stack_size += 8
                sse_count += 1
        args.append(ArgPlan([loc], size, max(1, size), False))
        arg_offset += 8

    if sret_idx is not None:
        ret_locs: list[Loc] = []
        ret_size = sret_size
    else:
        ret_locs, ret_size = _return_locs(ret_type)

    return CallPlan(
        name=name,
        args=args,
        ret_locs=ret_locs,
        stack_size=_align8(stack_size),
        sret=sret_idx is not None,
        sse_count=sse_count,
        ret_size=ret_size,
    )


class PlanTable:
    def __init__(self) -> None:
        self.plans: list[CallPlan] = []

    def add(self, plan: CallPlan) -> int:
        self.plans.append(plan)
        return len(self.plans) - 1

    def serialize(self) -> bytes:
        return serialize_plans(self.plans)


_KINDS = {
    "gpr": 0,
    "xmm": 1,
    "stack": 2,
    "sret": 3,
    "rax": 4,
    "rdx": 5,
    "xmm0": 6,
    "xmm1": 7,
}


def _loc_bytes(loc: Loc) -> bytes:
    return bytes([_KINDS[loc.kind]]) + (
        loc.index & 0xFFFF
    ).to_bytes(2, "little") + (loc.size & 0xFFFF).to_bytes(2, "little") + (
        loc.offset & 0xFFFF
    ).to_bytes(2, "little")


def serialize_plans(plans: list[CallPlan]) -> bytes:
    import struct

    out = bytearray()
    out += b"CIPL"
    out += bytes([2, 1])
    out += struct.pack("<HH", len(plans), 0)
    for plan in plans:
        name = plan.name.encode("utf-8")
        if len(name) > 255:
            raise UnsupportedFfi(f"plan name too long: {plan.name}")
        out += bytes([len(name)])
        out += name
        out += struct.pack(
            "<HHHBBH",
            len(plan.args),
            len(plan.ret_locs),
            plan.stack_size,
            1 if plan.sret else 0,
            plan.sse_count,
            plan.ret_size,
        )
        for arg in plan.args:
            out += struct.pack(
                "<BHHBB", len(arg.locs), arg.size, arg.alignment, 1 if arg.is_struct else 0, 0
            )
            for loc in arg.locs:
                out += _loc_bytes(loc)
        for loc in plan.ret_locs:
            out += _loc_bytes(loc)
    return bytes(out)
