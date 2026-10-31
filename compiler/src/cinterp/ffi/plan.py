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



def _align_up(n: int, a: int) -> int:
    if a <= 1:
        return n
    return (n + a - 1) // a * a


def _split_top(s: str) -> list[str]:
    out: list[str] = []
    depth = 0
    start = 0
    for i, ch in enumerate(s):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 0:
            out.append(s[start:i].strip())
            start = i + 1
    tail = s[start:].strip()
    if tail:
        out.append(tail)
    return out


def _aggregate_fields(ty: str, structs: dict[str, list[str]]) -> list[str] | None:
    ty = ty.strip()
    if ty.startswith("%"):
        return structs.get(ty)
    if ty.startswith("["):
        import re

        m = re.match(r"\[(\d+)\s+x\s+(.+)\]$", ty)
        if not m:
            return None
        return [m.group(2).strip()] * int(m.group(1))
    if ty.startswith("{") and ty.endswith("}"):
        inner = ty[1:-1].strip()
        return _split_top(inner) if inner else []
    return None


def _type_align(ty: str, structs: dict[str, list[str]], ptr_size: int = 8) -> int:
    fields = _aggregate_fields(ty, structs)
    if fields is not None:
        if not fields:
            return 1
        return max(_type_align(f, structs, ptr_size) for f in fields)
    ty = ty.strip()
    if ty == "ptr":
        return ptr_size
    if ty == "x86_fp80":
        return 16
    if ty == "float":
        return 4
    if ty == "double":
        return 8
    if ty.startswith("i"):
        bits = int(ty[1:])
        size = max(1, (bits + 7) // 8)
        return size
    raise UnsupportedFfi(f"unsupported type {ty!r}")


def _type_size(ty: str, structs: dict[str, list[str]], ptr_size: int = 8) -> int:
    fields = _aggregate_fields(ty, structs)
    if fields is not None:
        off = 0
        align = 1
        for field in fields:
            fa = _type_align(field, structs, ptr_size)
            off = _align_up(off, fa)
            off += _type_size(field, structs, ptr_size)
            align = max(align, fa)
        return _align_up(off, align)
    ty = ty.strip()
    if ty == "ptr":
        return ptr_size
    if ty == "x86_fp80":
        return 16
    if ty == "float":
        return 4
    if ty == "double":
        return 8
    if ty == "void":
        return 0
    if ty.startswith("i"):
        bits = int(ty[1:])
        return max(1, (bits + 7) // 8)
    raise UnsupportedFfi(f"unsupported type {ty!r}")


def _is_aggregate(ty: str, structs: dict[str, list[str]]) -> bool:
    return _aggregate_fields(ty, structs) is not None


def _hfa_info(ty: str, structs: dict[str, list[str]], ptr_size: int = 8):
    fields = _aggregate_fields(ty, structs)
    if fields is None:
        return None
    if len(fields) == 0 or len(fields) > 4:
        return None
    if not all(f.strip() in ("float", "double") for f in fields):
        return None
    elem = fields[0].strip()
    if any(f.strip() != elem for f in fields):
        return None
    return len(fields), 4 if elem == "float" else 8, _type_size(ty, structs, ptr_size)


def _scalar_info(ty: str, ptr_size: int = 8) -> tuple[str, int]:
    ty = ty.strip()
    if ty.startswith("ptr"):
        return "gpr", ptr_size
    if ty == "float":
        return "xmm", 4
    if ty == "double":
        return "xmm", 8
    if ty == "x86_fp80":
        raise UnsupportedFfi("long double FFI is not implemented")
    if ty == "void":
        return "void", 0
    if ty.startswith("i"):
        bits = int(ty[1:])
        return "gpr", max(1, (bits + 7) // 8)
    raise UnsupportedFfi(f"unsupported type {ty!r}")


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
    if ty == "x86_fp80":
        return [Loc("st0", 0, 16, 0)], 16
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
    xmm = 1 if sret_idx is not None else 0
    stack_size = 0
    arg_offset = 0
    args: list[ArgPlan] = []
    sse_count = 0

    for i, ty in enumerate(arg_types):
        if sret_idx == i:
            args.append(ArgPlan([Loc("sret", 0, 8, arg_offset)], 8, 8, False))
            arg_offset += 8
            continue
        if ty == "x86_fp80":
            stack_size = _align_up(stack_size, 16)
            loc = Loc("stack", stack_size, 16, arg_offset)
            args.append(ArgPlan([loc], 16, 16, True))
            stack_size += 16
            arg_offset += 16
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



def _win64_ret(ret_type: str, structs: dict[str, list[str]], ptr_size: int) -> tuple[list[Loc], int]:
    ty = ret_type.strip()
    if _is_aggregate(ty, structs):
        size = _type_size(ty, structs, ptr_size)
        if size <= 8:
            return [Loc("rax", 0, size, 0)], size
        raise UnsupportedFfi(f"Win64 aggregate return needs sret: {ty}")
    kind, size = _scalar_info(ty, ptr_size)
    if kind == "void":
        return [], 0
    if kind == "gpr":
        if size > 8:
            raise UnsupportedFfi(f"Win64 gpr return too large: {ty}")
        return [Loc("rax", 0, size, 0)], size
    if kind == "xmm":
        return [Loc("xmm0", 0, size, 0)], size
    raise UnsupportedFfi(f"unsupported Win64 return {ty!r}")


def build_win64_plan(
    name: str,
    ret_type: str,
    arg_types: list[str],
    is_varargs: bool = False,
    sret_idx: int | None = None,
    sret_size: int = 0,
    byval_sizes: list[int] | None = None,
    structs: dict[str, list[str]] | None = None,
    ptr_size: int = 8,
    named_count: int | None = None,
) -> CallPlan:
    structs = structs or {}
    if is_varargs and named_count is None:
        named_count = len(arg_types)
    gpr = 1 if sret_idx is not None else 0
    xmm = 1 if sret_idx is not None else 0
    stack_size = 0
    arg_offset = 0
    args: list[ArgPlan] = []
    sse_count = 0

    for i, ty in enumerate(arg_types):
        if sret_idx == i:
            args.append(ArgPlan([Loc("sret", 0, 8, arg_offset)], 8, 8, False))
            arg_offset += 8
            continue
        if byval_sizes and i < len(byval_sizes) and byval_sizes[i] > 0:
            # Win64 passes MEMORY structs by reference.
            if i < 4:
                loc = Loc("gpr", i, 8, arg_offset)
            else:
                stack_size = _align8((i - 4) * 8)
                loc = Loc("stack", stack_size, 8, arg_offset)
                stack_size += 8
            args.append(ArgPlan([loc], 8, 8, False))
            arg_offset += 8
            continue
        if _is_aggregate(ty, structs):
            raise UnsupportedFfi(f"Win64 aggregate argument should be coerced/pointer: {ty}")
        kind, size = _scalar_info(ty, ptr_size)
        if kind == "void":
            raise UnsupportedFfi("void argument")
        variadic = is_varargs and named_count is not None and i >= named_count
        if variadic:
            locs: list[Loc] = []
            if kind == "xmm":
                if sse_count < 4:
                    locs.append(Loc("xmm", sse_count, size, arg_offset))
                if i < 4:
                    if i != sse_count:
                        locs.append(Loc("xmm", i, size, arg_offset))
                    locs.append(Loc("gpr", i, 8, arg_offset))
                else:
                    stack_size = _align8((i - 4) * 8)
                    locs.append(Loc("stack", stack_size, size, arg_offset))
                    stack_size += _align8(size)
                sse_count += 1
            else:
                if i < 4:
                    locs.append(Loc("gpr", i, 8, arg_offset))
                else:
                    stack_size = _align8((i - 4) * 8)
                    locs.append(Loc("stack", stack_size, size, arg_offset))
                    stack_size += _align8(size)
            args.append(ArgPlan(locs, size, 8, False))
            arg_offset += 8
            continue
        if kind == "gpr":
            if i < 4:
                loc = Loc("gpr", i, size, arg_offset)
            else:
                stack_size = _align8((i - 4) * 8)
                loc = Loc("stack", stack_size, size, arg_offset)
                stack_size += _align8(size)
        else:
            if i < 4:
                loc = Loc("xmm", i, size, arg_offset)
            else:
                stack_size = _align8((i - 4) * 8)
                loc = Loc("stack", stack_size, size, arg_offset)
                stack_size += _align8(size)
        args.append(ArgPlan([loc], size, max(1, size), False))
        arg_offset += 8

    if sret_idx is not None:
        ret_locs: list[Loc] = []
        ret_size = sret_size
    else:
        ret_locs, ret_size = _win64_ret(ret_type, structs, ptr_size)
    return CallPlan(
        name=name,
        args=args,
        ret_locs=ret_locs,
        stack_size=stack_size,
        sret=sret_idx is not None,
        sse_count=min(sse_count, 8) if is_varargs else 0,
        ret_size=ret_size,
    )


def _win32_ret(ret_type: str, structs: dict[str, list[str]], ptr_size: int) -> tuple[list[Loc], int]:
    ty = ret_type.strip()
    if ty == "x86_fp80":
        return [Loc("st0", 0, 16, 0)], 16
    if _is_aggregate(ty, structs):
        size = _type_size(ty, structs, ptr_size)
        if size <= 4:
            return [Loc("rax", 0, 4, 0)], size
        if size <= 8:
            return [Loc("rax", 0, 4, 0), Loc("rdx", 0, 4, 4)], size
        raise UnsupportedFfi(f"Win32 aggregate return needs sret: {ty}")
    kind, size = _scalar_info(ty, ptr_size)
    if kind == "void":
        return [], 0
    if kind == "xmm":
        return [Loc("xmm0", 0, size, 0)], size
    if size <= 4:
        return [Loc("rax", 0, 4, 0)], size
    if size <= 8:
        return [Loc("rax", 0, 8, 0)], size
    raise UnsupportedFfi(f"Win32 gpr return too large: {ty}")


def build_win32_plan(
    name: str,
    ret_type: str,
    arg_types: list[str],
    is_varargs: bool = False,
    sret_idx: int | None = None,
    sret_size: int = 0,
    byval_sizes: list[int] | None = None,
    structs: dict[str, list[str]] | None = None,
    ptr_size: int = 4,
    named_count: int | None = None,
) -> CallPlan:
    _ = is_varargs, named_count
    structs = structs or {}
    stack_size = 0
    arg_offset = 0
    args: list[ArgPlan] = []
    has_sret = sret_idx is not None

    for i, ty in enumerate(arg_types):
        if sret_idx == i:
            loc = Loc("stack", stack_size, 4, arg_offset)
            args.append(ArgPlan([loc], 4, 4, False))
            stack_size += 4
            arg_offset += 4
            continue
        if ty == "x86_fp80":
            size = 16 if ptr_size == 8 else 12
            stack_size = _align_up(stack_size, 4)
            loc = Loc("stack", stack_size, size, arg_offset)
            stack_size += _align_up(size, 4)
            arg_offset = _align_up(arg_offset, 4)
            arg_offset += size
            args.append(ArgPlan([loc], size, 4, True))
            continue
        if byval_sizes and i < len(byval_sizes) and byval_sizes[i] > 0:
            size = byval_sizes[i]
            stack_size = _align_up(stack_size, 4)
            loc = Loc("stack", stack_size, size, arg_offset)
            stack_size += _align_up(size, 4)
            arg_offset = _align_up(arg_offset, 4)
            arg_offset += size
            args.append(ArgPlan([loc], size, 4, True))
            continue
        if _is_aggregate(ty, structs):
            size = _type_size(ty, structs, ptr_size)
            align = 4
            stack_size = _align_up(stack_size, align)
            loc = Loc("stack", stack_size, size, arg_offset)
            stack_size += _align_up(size, 4)
            arg_offset = _align_up(arg_offset, 4)
            arg_offset += size
            args.append(ArgPlan([loc], size, align, True))
            continue
        kind, size = _scalar_info(ty, ptr_size)
        if kind == "void":
            raise UnsupportedFfi("void argument")
        align = 4
        stack_size = _align_up(stack_size, align)
        loc = Loc("stack", stack_size, size, arg_offset)
        stack_size += _align_up(size, 4)
        arg_offset = _align_up(arg_offset, 4)
        arg_offset += size
        args.append(ArgPlan([loc], size, align, False))

    if has_sret:
        ret_locs: list[Loc] = []
        ret_size = sret_size
    else:
        ret_locs, ret_size = _win32_ret(ret_type, structs, ptr_size)
    return CallPlan(
        name=name,
        args=args,
        ret_locs=ret_locs,
        stack_size=_align_up(stack_size, 4),
        sret=has_sret,
        sse_count=0,
        ret_size=ret_size,
    )


def _aapcs64_ret(ret_type: str, structs: dict[str, list[str]], ptr_size: int) -> tuple[list[Loc], int]:
    ty = ret_type.strip()
    if ty == "fp128":
        return [Loc("xmm0", 0, 16, 0)], 16
    hfa = _hfa_info(ty, structs, ptr_size)
    if hfa is not None:
        count, elem_size, size = hfa
        if count > 2:
            raise UnsupportedFfi("AAPCS64 HFA return with more than 2 vectors")
        locs = [Loc("xmm0" if i == 0 else "xmm1", 0, elem_size, i * elem_size) for i in range(count)]
        return locs, size
    if _is_aggregate(ty, structs):
        size = _type_size(ty, structs, ptr_size)
        if size <= 8:
            return [Loc("rax", 0, size, 0)], size
        if size <= 16:
            return [Loc("rax", 0, 8, 0), Loc("rdx", 0, size - 8, 8)], size
        raise UnsupportedFfi(f"AAPCS64 aggregate return needs sret: {ty}")
    kind, size = _scalar_info(ty, ptr_size)
    if kind == "void":
        return [], 0
    if kind == "gpr":
        return [Loc("rax", 0, size, 0)], size
    if kind == "xmm":
        return [Loc("xmm0", 0, size, 0)], size
    raise UnsupportedFfi(f"unsupported AAPCS64 return {ty!r}")


def build_aapcs64_plan(
    name: str,
    ret_type: str,
    arg_types: list[str],
    is_varargs: bool = False,
    sret_idx: int | None = None,
    sret_size: int = 0,
    byval_sizes: list[int] | None = None,
    structs: dict[str, list[str]] | None = None,
    ptr_size: int = 8,
    named_count: int | None = None,
) -> CallPlan:
    _ = is_varargs, named_count, byval_sizes
    structs = structs or {}
    gpr = 0
    vec = 0
    stack_size = 0
    arg_offset = 0
    args: list[ArgPlan] = []

    for i, ty in enumerate(arg_types):
        if sret_idx == i:
            args.append(ArgPlan([Loc("sret", 0, 8, arg_offset)], 8, 8, False))
            arg_offset += 8
            continue
        if ty == "fp128":
            if vec < 8:
                loc = Loc("xmm", vec, 16, arg_offset)
                vec += 1
            else:
                stack_size = _align_up(stack_size, 16)
                loc = Loc("stack", stack_size, 16, arg_offset)
                stack_size += 16
            args.append(ArgPlan([loc], 16, 16, True))
            arg_offset += 16
            continue
        hfa = _hfa_info(ty, structs, ptr_size)
        if hfa is not None:
            count, elem_size, size = hfa
            if vec + count <= 8:
                locs = [
                    Loc("xmm", vec + j, elem_size, arg_offset + j * elem_size)
                    for j in range(count)
                ]
                vec += count
            else:
                stack_size = _align_up(stack_size, 16)
                locs = [Loc("stack", stack_size, size, arg_offset)]
                stack_size += _align_up(size, 16)
            arg_offset = _align_up(arg_offset, 8)
            args.append(ArgPlan(locs, size, 8, True))
            arg_offset += _align_up(size, 8)
            continue
        if _is_aggregate(ty, structs):
            size = _type_size(ty, structs, ptr_size)
            if size > 16:
                raise UnsupportedFfi(f"AAPCS64 aggregate argument should be a pointer: {ty}")
            nregs = (size + 7) // 8
            if gpr + nregs <= 8:
                locs = [Loc("gpr", gpr + j, min(8, size - j * 8), arg_offset + j * 8) for j in range(nregs)]
                gpr += nregs
            else:
                stack_size = _align_up(stack_size, 16)
                locs = [Loc("stack", stack_size, size, arg_offset)]
                stack_size += _align_up(size, 16)
            arg_offset = _align_up(arg_offset, 8)
            args.append(ArgPlan(locs, size, 8, True))
            arg_offset += _align_up(size, 8)
            continue
        kind, size = _scalar_info(ty, ptr_size)
        if kind == "void":
            raise UnsupportedFfi("void argument")
        if kind == "gpr":
            if gpr < 8:
                loc = Loc("gpr", gpr, size, arg_offset)
                gpr += 1
            else:
                stack_size = _align_up(stack_size, 8)
                loc = Loc("stack", stack_size, size, arg_offset)
                stack_size += _align_up(size, 8)
        else:
            if vec < 8:
                loc = Loc("xmm", vec, size, arg_offset)
                vec += 1
            else:
                stack_size = _align_up(stack_size, 16)
                loc = Loc("stack", stack_size, size, arg_offset)
                stack_size += _align_up(size, 16)
        args.append(ArgPlan([loc], size, max(1, size), False))
        arg_offset += 8

    if sret_idx is not None:
        ret_locs: list[Loc] = []
        ret_size = sret_size
    else:
        ret_locs, ret_size = _aapcs64_ret(ret_type, structs, ptr_size)
    return CallPlan(
        name=name,
        args=args,
        ret_locs=ret_locs,
        stack_size=stack_size,
        sret=sret_idx is not None,
        sse_count=0,
        ret_size=ret_size,
    )


def build_plan(
    abi: str,
    name: str,
    ret_type: str,
    arg_types: list[str],
    is_varargs: bool = False,
    sret_idx: int | None = None,
    sret_size: int = 0,
    byval_sizes: list[int] | None = None,
    structs: dict[str, list[str]] | None = None,
    ptr_size: int = 8,
    named_count: int | None = None,
) -> CallPlan:
    if abi == "sysv":
        return build_sysv_plan(
            name, ret_type, arg_types, is_varargs, sret_idx, sret_size, byval_sizes
        )
    if abi == "win64":
        return build_win64_plan(
            name, ret_type, arg_types, is_varargs, sret_idx, sret_size,
            byval_sizes, structs, ptr_size, named_count,
        )
    if abi == "win32":
        return build_win32_plan(
            name, ret_type, arg_types, is_varargs, sret_idx, sret_size,
            byval_sizes, structs, ptr_size, named_count,
        )
    if abi == "aapcs64":
        return build_aapcs64_plan(
            name, ret_type, arg_types, is_varargs, sret_idx, sret_size,
            byval_sizes, structs, ptr_size, named_count,
        )
    raise UnsupportedFfi(f"unknown ABI {abi!r}")


ABI_IDS = {
    "sysv": 1,
    "win64": 2,
    "win32": 3,
    "aapcs64": 4,
}


class PlanTable:
    def __init__(self, abi: str = "sysv") -> None:
        self.plans: list[CallPlan] = []
        self.abi_id = ABI_IDS[abi]

    def add(self, plan: CallPlan) -> int:
        self.plans.append(plan)
        return len(self.plans) - 1

    def serialize(self) -> bytes:
        return serialize_plans(self.plans, self.abi_id)


_KINDS = {
    "gpr": 0,
    "xmm": 1,
    "stack": 2,
    "sret": 3,
    "rax": 4,
    "rdx": 5,
    "xmm0": 6,
    "xmm1": 7,
    "st0": 8,
}


def _loc_bytes(loc: Loc) -> bytes:
    return bytes([_KINDS[loc.kind]]) + (
        loc.index & 0xFFFF
    ).to_bytes(2, "little") + (loc.size & 0xFFFF).to_bytes(2, "little") + (
        loc.offset & 0xFFFF
    ).to_bytes(2, "little")


def serialize_plans(plans: list[CallPlan], abi_id: int = 1) -> bytes:
    import struct

    out = bytearray()
    out += b"CIPL"
    out += bytes([2, abi_id & 0xFF])
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
