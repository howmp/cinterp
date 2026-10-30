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


def build_sysv_plan(
    name: str,
    ret_type: str,
    arg_types: list[str],
    is_varargs: bool = False,
) -> CallPlan:
    gpr = 0
    xmm = 0
    stack_size = 0
    arg_offset = 0
    args: list[ArgPlan] = []
    sse_count = 0

    for ty in arg_types:
        kind, size = _type_info(ty)
        if kind == "void":
            raise UnsupportedFfi("void argument")
        if kind == "gpr":
            if gpr < 6:
                loc = Loc("gpr", gpr, size, arg_offset)
                gpr += 1
            else:
                loc = Loc("stack", stack_size, size, arg_offset)
                stack_size += 8
        else:
            if xmm < 8:
                loc = Loc("xmm", xmm, size, arg_offset)
                xmm += 1
                sse_count += 1
            else:
                loc = Loc("stack", stack_size, size, arg_offset)
                stack_size += 8
                sse_count += 1
        args.append(ArgPlan([loc], size, max(1, size), False))
        arg_offset += 8

    ret_kind, ret_size = _type_info(ret_type)
    if ret_kind == "void":
        ret_locs: list[Loc] = []
    elif ret_kind == "gpr":
        ret_locs = [Loc("rax", 0, ret_size, 0)]
    elif ret_kind == "xmm":
        ret_locs = [Loc("xmm0", 0, ret_size, 0)]
    else:
        raise UnsupportedFfi(f"unsupported return type {ret_type!r}")

    return CallPlan(
        name=name,
        args=args,
        ret_locs=ret_locs,
        stack_size=stack_size,
        sret=False,
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
