#!/usr/bin/env python3
"""Lower a small scalar subset of clang -O0 LLVM IR to a CIVM bytecode module.

The VM is stack-based, but this lowering maps every LLVM SSA value / alloca to a
VM local slot. That avoids phi/stack-merge issues at -O0 and keeps the lowering
mechanical:
  add -> LOAD_LOCAL a; LOAD_LOCAL b; ADD; STORE_LOCAL result
  br  -> LOAD_LOCAL cond; JNZ then; JMP else
"""
from __future__ import annotations

import re
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

from ..codegen.binary_writer import write_package
from ..ffi.plan import PlanTable, build_plan, build_sysv_plan

OP_RET = 0x01
OP_RET_VOID = 0x02
OP_LOAD_CONST_I64 = 0x10
OP_ADD = 0x11
OP_SUB = 0x12
OP_MUL = 0x13
OP_XOR = 0x17
OP_DIV_S = 0x18
OP_DIV_U = 0x19
OP_REM_S = 0x1A
OP_REM_U = 0x1B
OP_AND = 0x1C
OP_OR = 0x1D
OP_SHL = 0x1E
OP_SHR_S = 0x1F
OP_SHR_U = 0x24
OP_FPTOSI = 0x25
OP_SITOFP = 0x26
OP_FADD = 0x27
OP_FSUB = 0x28
OP_FMUL = 0x29
OP_FDIV = 0x2A
OP_FCMP = 0x2B
OP_FADD32 = 0x2C
OP_FSUB32 = 0x2D
OP_FMUL32 = 0x2E
OP_FDIV32 = 0x2F
OP_FCMP32 = 0x38
OP_FPEXT = 0x39
OP_FPTRUNC = 0x3A
OP_FPTOSI32 = 0x3B
OP_SITOFP32 = 0x3C
OP_LOAD_LOCAL = 0x20
OP_STORE_LOCAL = 0x21
OP_JMP = 0x30
OP_JZ = 0x31
OP_JNZ = 0x32
OP_CMP_EQ = 0x33
OP_CMP_LT = 0x34
OP_CMP_LT_U = 0x35
OP_CALL = 0x40
OP_ALLOCA = 0x60
OP_LOAD_MEM = 0x61
OP_STORE_MEM = 0x62
OP_MEMCPY = 0x63
OP_MEMSET = 0x64
OP_ADDR_CONST = 0x65
OP_SET_MEM_TOP = 0x66
OP_CALL_NATIVE = 0x70
OP_CALL_VARARG = 0x71
OP_CREATE_CALLBACK = 0x72
OP_F80_CONST = 0x73
OP_F80_ADD = 0x74
OP_F80_SUB = 0x75
OP_F80_MUL = 0x76
OP_F80_DIV = 0x77
OP_F80_CMP = 0x78
OP_F80_FROM_F64 = 0x79
OP_F80_TO_F64 = 0x7A
OP_F80_FROM_I64 = 0x7B
OP_F80_TO_I64 = 0x7C
OP_F80_FROM_F32 = 0x7D
OP_F80_TO_F32 = 0x7E
OP_F80_NEG = 0x7F
OP_F128_CONST = 0x80
OP_F128_ADD = 0x81
OP_F128_SUB = 0x82
OP_F128_MUL = 0x83
OP_F128_DIV = 0x84
OP_F128_CMP = 0x85
OP_F128_NEG = 0x86
OP_F128_FROM_F64 = 0x87
OP_F128_TO_F64 = 0x88
OP_F128_FROM_I64 = 0x89
OP_F128_TO_I64 = 0x8A
OP_F128_FROM_F32 = 0x8B
OP_F128_TO_F32 = 0x8C


def split_top(s: str, sep: str = ",") -> list[str]:
    parts: list[str] = []
    cur: list[str] = []
    depth = 0
    for ch in s:
        if ch in "([{<":
            depth += 1
        elif ch in ")]}>":
            depth -= 1
        if ch == sep and depth == 0:
            part = "".join(cur).strip()
            if part:
                parts.append(part)
            cur = []
        else:
            cur.append(ch)
    part = "".join(cur).strip()
    if part:
        parts.append(part)
    return parts


def strip_meta(line: str) -> str:
    line = line.split(";", 1)[0].strip()
    line = re.sub(r",\s*!dbg\s*!\d+", "", line)
    line = re.sub(r"\s*!dbg\s*!\d+", "", line)
    line = re.sub(r",\s*!llvm\.loop\s*!\d+", "", line)
    line = re.sub(r"\s*!llvm\.loop\s*!\d+", "", line)
    line = re.sub(r"\s*#\d+", "", line)
    return line.strip()


def align_up(n: int, a: int) -> int:
    return (n + a - 1) // a * a


def parse_structs(text: str) -> dict[str, list[str]]:
    structs: dict[str, list[str]] = {}
    for line in text.splitlines():
        m = re.match(r"^(%[\w.$-]+)\s*=\s*type\s+\{(.*)\}\s*$", line.strip())
        if m:
            inner = m.group(2).strip()
            structs[m.group(1)] = split_top(inner) if inner else []
    return structs


def struct_layout(fields: list[str], structs: dict[str, list[str]], ptr_size: int = 8) -> tuple[list[int], int, int]:
    offsets: list[int] = []
    off = 0
    max_align = 1
    for field in fields:
        size, alignment = type_size_align(field, structs, ptr_size)
        off = align_up(off, alignment)
        offsets.append(off)
        off += size
        max_align = max(max_align, alignment)
    return offsets, align_up(off, max_align), max_align


def type_size_align(ty: str, structs: dict[str, list[str]], ptr_size: int = 8) -> tuple[int, int]:
    ty = ty.strip()
    if ty.startswith("%"):
        fields = structs.get(ty)
        if fields is None:
            raise ValueError(f"unknown struct type {ty}")
        _, size, alignment = struct_layout(fields, structs, ptr_size)
        return size, alignment
    if ty.startswith("["):
        m = re.match(r"\[(\d+)\s+x\s+(.+)\]$", ty)
        if not m:
            raise ValueError(f"bad array type {ty}")
        count = int(m.group(1))
        elem_size, elem_align = type_size_align(m.group(2), structs, ptr_size)
        return count * align_up(elem_size, elem_align), elem_align
    if ty.startswith("{"):
        inner = ty[1:-1].strip()
        fields = split_top(inner) if inner else []
        _, size, alignment = struct_layout(fields, structs, ptr_size)
        return size, alignment
    if ty == "ptr":
        return ptr_size, ptr_size
    if ty == "x86_fp80":
        return (12, 4) if ptr_size == 4 else (16, 16)
    if ty == "fp128":
        return 16, 16
    if ty == "void":
        return 0, 1
    if ty == "float":
        return 4, 4
    if ty == "double":
        return 8, 8
    m = re.match(r"i(\d+)$", ty)
    if m:
        bits = int(m.group(1))
        size = max(1, (bits + 7) // 8)
        return size, size
    raise ValueError(f"unsupported type {ty}")


def array_element(ty: str) -> str | None:
    m = re.match(r"\[(\d+)\s+x\s+(.+)\]$", ty.strip())
    return m.group(2).strip() if m else None


def struct_fields(ty: str, structs: dict[str, list[str]]) -> list[str] | None:
    ty = ty.strip()
    if ty.startswith("%"):
        return structs.get(ty)
    if ty.startswith("{"):
        inner = ty[1:-1].strip()
        return split_top(inner) if inner else []
    return None


def parse_llvm_cstring(body: str) -> bytes:
    out = bytearray()
    i = 0
    while i < len(body):
        ch = body[i]
        if ch == "\\" and i + 2 < len(body):
            pair = body[i + 1 : i + 3]
            if all(c in "0123456789abcdefABCDEF" for c in pair):
                out.append(int(pair, 16))
                i += 3
                continue
        if ch == "\\" and i + 1 < len(body):
            esc = body[i + 1]
            out.append({"n": 10, "t": 9, "r": 13, "\\": 92, '"': 34, "0": 0}.get(esc, ord(esc)))
            i += 2
            continue
        out.append(ord(ch))
        i += 1
    return bytes(out)


def parse_x86_fp80(init: str) -> float:
    text = init.strip()
    if text.startswith("0xK") or text.startswith("0x"):
        hex_text = text[3:] if text.startswith("0xK") else text[2:]
        try:
            value = int(hex_text, 16)
        except ValueError:
            return 0.0
        sign = (value >> 79) & 1
        exponent = (value >> 64) & 0x7FFF
        mantissa = value & ((1 << 64) - 1)
        if exponent == 0x7FFF:
            result = float("inf") if mantissa == (1 << 63) else float("nan")
        elif exponent == 0:
            result = float(mantissa) * (2.0 ** (-16382 - 63))
        else:
            result = float(mantissa) * (2.0 ** (exponent - 16383 - 63))
        return -result if sign else result
    try:
        return float(text.rstrip("LlFf"))
    except ValueError:
        return 0.0


def parse_fp128_bytes(init: str) -> bytes:
    text = init.strip().split()[-1]
    if text.startswith("0xL"):
        hex_text = text[3:]
        try:
            if len(hex_text) == 32:
                high = int(hex_text[:16], 16)
                low = int(hex_text[16:], 16)
                value = (low << 64) | high
            else:
                value = int(hex_text, 16)
        except ValueError:
            value = 0
        return value.to_bytes(16, "little")
    try:
        value = float(text.rstrip("LlFf"))
    except ValueError:
        value = 0.0
    return struct.pack("<d", value) + b"\x00" * 8


def parse_x86_fp80_bytes(init: str) -> bytes:
    text = init.strip().split()[-1]
    if text.startswith("0xK"):
        try:
            value = int(text[3:], 16)
        except ValueError:
            value = 0
        return value.to_bytes(10, "little")
    try:
        value = float(text.rstrip("LlFf"))
    except ValueError:
        value = 0.0
    return struct.pack("<d", value) + b"\x00\x00"


def parse_constant_bytes(ty: str, init: str, structs: dict[str, list[str]], ptr_size: int = 8) -> bytes:
    size, _ = type_size_align(ty, structs, ptr_size)
    out = bytearray(size)
    init = init.strip()
    if init.startswith("{") and init.endswith("}"):
        fields = struct_fields(ty, structs)
        if fields is not None:
            offsets, _, _ = struct_layout(fields, structs, ptr_size)
            parts = split_top(init[1:-1]) if init[1:-1].strip() else []
            for i, part in enumerate(parts):
                if i >= len(fields):
                    break
                tm = re.match(r"(\[[^\]]*\]|%[\w.$-]+|\S+)\s+(.+)$", part.strip())
                if not tm:
                    continue
                chunk = parse_constant_bytes(tm.group(1), tm.group(2), structs, ptr_size)
                off = offsets[i]
                n = min(len(chunk), max(0, size - off))
                out[off : off + n] = chunk[:n]
            return bytes(out)
    if init.startswith("[") and init.endswith("]"):
        elem = array_element(ty)
        if elem is not None:
            es, ea = type_size_align(elem, structs, ptr_size)
            stride = align_up(es, ea)
            parts = split_top(init[1:-1]) if init[1:-1].strip() else []
            for i, part in enumerate(parts):
                tm = re.match(r"(\[[^\]]*\]|%[\w.$-]+|\S+)\s+(.+)$", part.strip())
                if not tm:
                    continue
                chunk = parse_constant_bytes(tm.group(1), tm.group(2), structs, ptr_size)
                off = i * stride
                n = min(len(chunk), max(0, size - off))
                out[off : off + n] = chunk[:n]
            return bytes(out)
    if init.startswith('c"') and init.endswith('"'):
        raw = parse_llvm_cstring(init[2:-1])
        out[: min(len(raw), size)] = raw[:size]
        return bytes(out)
    if init in ("zeroinitializer", "null"):
        return bytes(out)
    if ty == "x86_fp80":
        raw = parse_x86_fp80_bytes(init)
        out[: min(len(raw), size)] = raw[:size]
        return bytes(out)
    if ty == "fp128":
        raw = parse_fp128_bytes(init)
        out[: min(len(raw), size)] = raw[:size]
        return bytes(out)
    if ty in ("double", "float"):
        try:
            value = float(init)
        except ValueError:
            return bytes(out)
        if ty == "double":
            raw = struct.pack("<d", value)
        else:
            raw = struct.pack("<f", value)
        out[: min(len(raw), size)] = raw[:size]
        return bytes(out)
    if re.match(r"^-?\d+$", init):
        value = int(init)
        for i in range(size):
            out[i] = (value >> (8 * i)) & 0xFF
        return bytes(out)
    if init in ("true", "false"):
        out[0] = 1 if init == "true" else 0
    return bytes(out)


def parse_globals(text: str, structs: dict[str, list[str]], ptr_size: int = 8) -> tuple[dict[str, int], bytes]:
    globals_map: dict[str, int] = {}
    data = bytearray()
    for line in text.splitlines():
        line = strip_meta(line.strip())
        m = re.match(r"^(@[A-Za-z0-9_.$]+)\s*=\s*(.+)$", line)
        if not m:
            continue
        name, rest = m.group(1), m.group(2)
        km = re.search(r"\b(global|constant)\b", rest)
        if not km:
            continue
        tail = re.sub(r",\s*align\s+\d+\s*$", "", rest[km.end():].strip()).strip()
        tm = re.match(r"(\[[^\]]*\]|%[\w.$-]+|\S+)\s+(.+)$", tail)
        if not tm:
            continue
        ty, init = tm.group(1).strip(), tm.group(2).strip()
        try:
            size, align = type_size_align(ty, structs, ptr_size)
        except ValueError:
            continue
        off = align_up(len(data), max(align, 1))
        if off > len(data):
            data.extend(b"\x00" * (off - len(data)))
        data.extend(parse_constant_bytes(ty, init, structs, ptr_size))
        globals_map[name] = off
    if len(data) % 8:
        data.extend(b"\x00" * (8 - len(data) % 8))
    return globals_map, bytes(data)


def parse_decls(text: str) -> dict[str, tuple[str, list[str], bool]]:
    decls: dict[str, tuple[str, list[str], bool]] = {}
    for line in text.splitlines():
        line = line.strip()
        m = re.match(r"declare\s+(.+?)\s+@([\w.$-]+)\((.*)\)", line)
        if not m:
            continue
        pre = re.sub(r"\s*\([^()]*\)\s*$", "", m.group(1).strip()).strip()
        ret, name, params_text = pre.split()[-1], m.group(2), m.group(3)
        is_varargs = False
        types: list[str] = []
        for p in split_top(params_text):
            p = p.strip()
            if p == "...":
                is_varargs = True
                continue
            tm = re.match(r"(\[[^\]]*\]|%[\w.$-]+|\S+)", p)
            if tm:
                types.append(tm.group(1))
        decls[name] = (ret, types, is_varargs)
    return decls


@dataclass
class Function:
    name: str
    ret: str
    params: list[tuple[str, str]]
    body: list[str]
    index: int = 0
    param_attrs: list[str] = field(default_factory=list)
    code: bytes = b""
    local_count: int = 0


class CallbackTable:
    def __init__(self, abi: str = "sysv", structs: dict[str, list[str]] | None = None, ptr_size: int = 8) -> None:
        self.by_func: dict[str, tuple[int, int, int]] = {}
        self.next_slot = 0
        self.abi = abi
        self.structs = structs or {}
        self.ptr_size = ptr_size

    def add(self, name: str, fn: Function, func_index: int, plans: PlanTable) -> tuple[int, int, int]:
        if name in self.by_func:
            return self.by_func[name]
        if self.next_slot >= 256:
            raise ValueError("callback slot pool exhausted")
        sret_idx = None
        sret_size = 0
        byval_sizes = [0] * len(fn.params)
        for i, raw in enumerate(fn.param_attrs):
            sm = re.search(r"\bsret\(([^)]+)\)", raw)
            if sm:
                sret_idx = i
                sret_size = type_size_align(sm.group(1), self.structs, self.ptr_size)[0]
            bm = re.search(r"\bbyval\(([^)]+)\)", raw)
            if bm:
                byval_sizes[i] = type_size_align(bm.group(1), self.structs, self.ptr_size)[0]
        plan = build_plan(
            self.abi,
            "callback:" + name,
            fn.ret,
            [ptype for ptype, _pname in fn.params],
            sret_idx=sret_idx,
            sret_size=sret_size,
            byval_sizes=byval_sizes,
            structs=self.structs,
            ptr_size=self.ptr_size,
        )
        plan_index = plans.add(plan)
        slot = self.next_slot
        self.next_slot += 1
        entry = (slot, func_index, plan_index)
        self.by_func[name] = entry
        return entry


class Lowerer:
    def __init__(
        self,
        fn: Function,
        func_indices: dict[str, int],
        structs: dict[str, list[str]],
        globals_map: dict[str, int],
        global_data: bytes,
        decls: dict[str, tuple[str, list[str], bool]],
        plans: PlanTable,
        functions_by_name: dict[str, Function],
        callbacks: CallbackTable,
        abi: str = "sysv",
        ptr_size: int = 8,
    ):
        self.fn = fn
        self.func_indices = func_indices
        self.structs = structs
        self.globals = globals_map
        self.global_data = global_data
        self.decls = decls
        self.plans = plans
        self.functions_by_name = functions_by_name
        self.callbacks = callbacks
        self.abi = abi
        self.ptr_size = ptr_size
        self.code = bytearray()
        self.slots: dict[str, int] = {}
        self.allocas: dict[str, int] = {}
        self.next_slot = 0
        self.label_pos: dict[str, int] = {}
        self.patches: list[tuple[int, str]] = []
        self.select_id = 0

        for _ptype, pname in fn.params:
            self.slots[pname] = self.alloc_slot()

    def alloc_slot(self) -> int:
        s = self.next_slot
        self.next_slot += 1
        return s

    def slot_for(self, name: str) -> int:
        if name not in self.slots:
            self.slots[name] = self.alloc_slot()
        return self.slots[name]

    def emit_u8(self, v: int) -> None:
        self.code.append(v & 0xFF)

    def emit_u16(self, v: int) -> None:
        self.code += (v & 0xFFFF).to_bytes(2, "little")

    def emit_u32(self, v: int) -> None:
        self.code += (v & 0xFFFFFFFF).to_bytes(4, "little")

    def emit_i64(self, v: int) -> None:
        self.code += (v & 0xFFFFFFFFFFFFFFFF).to_bytes(8, "little")

    def emit_const(self, v: int) -> None:
        self.emit_u8(OP_LOAD_CONST_I64)
        self.emit_i64(v)

    def load_slot(self, slot: int) -> None:
        self.emit_u8(OP_LOAD_LOCAL)
        self.emit_u16(slot)

    def store_slot(self, slot: int) -> None:
        self.emit_u8(OP_STORE_LOCAL)
        self.emit_u16(slot)

    def emit_operand(self, text: str) -> None:
        globals_found = re.findall(r"@[\w.$-]+", text)
        if globals_found:
            name = globals_found[-1]
            if name not in self.globals:
                raise ValueError(f"unknown global {name}")
            self.emit_u8(OP_ADDR_CONST)
            self.emit_u32(self.globals[name])
            return
        locals_found = re.findall(r"%[\w.$-]+", text)
        if locals_found:
            self.load_slot(self.slot_for(locals_found[-1][1:]))
            return
        stripped = text.strip()
        if "x86_fp80" in text or stripped.startswith("0xK"):
            raw = parse_x86_fp80_bytes(stripped.split()[-1])
            self.emit_u8(OP_F80_CONST)
            self.code.extend(raw[:10])
            return
        if "fp128" in text or stripped.startswith("0xL"):
            raw = parse_fp128_bytes(stripped.split()[-1])
            self.emit_u8(OP_F128_CONST)
            self.code.extend(raw[:16])
            return
        if re.fullmatch(r"[-+]?(?:\d+\.\d*|\.\d+)(?:[eE][-+]?\d+)?", stripped):
            bits = struct.unpack("<Q", struct.pack("<d", float(stripped)))[0]
            self.emit_const(bits)
            return
        if re.search(r"\btrue\b", text):
            self.emit_const(1)
            return
        if re.search(r"\bfalse\b", text):
            self.emit_const(0)
            return
        if re.search(r"\b(double|float)\b", text):
            fnums = re.findall(r"[-+]?\d+(?:\.\d*)?(?:[eE][-+]?\d+)?", text)
            if fnums:
                value = float(fnums[-1])
                if re.search(r"\bdouble\b", text):
                    bits = struct.unpack("<Q", struct.pack("<d", value))[0]
                else:
                    bits = struct.unpack("<I", struct.pack("<f", value))[0]
                self.emit_const(bits)
                return
        nums = re.findall(r"-?\d+", text)
        if nums:
            self.emit_const(int(nums[-1]))
            return
        raise ValueError(f"unsupported operand: {text!r}")

    def type_size(self, ty: str) -> int:
        return type_size_align(ty, self.structs, self.ptr_size)[0]

    def emit_float_operand(self, text: str, ty: str) -> None:
        stripped = text.strip()
        if ty in ("x86_fp80", "fp128"):
            self.emit_operand(text)
            return
        if not re.search(r"[%@]", stripped) and re.fullmatch(
            r"[-+]?(?:\d+\.\d*|\.\d+)(?:[eE][-+]?\d+)?", stripped
        ):
            value = float(stripped)
            if ty == "float":
                bits = struct.unpack("<I", struct.pack("<f", value))[0]
            else:
                bits = struct.unpack("<Q", struct.pack("<d", value))[0]
            self.emit_const(bits)
            return
        self.emit_operand(text)

    def emit_arg(self, text: str) -> None:
        found = re.findall(r"@[\w.$-]+", text)
        if found:
            name = found[-1]
            key = name[1:]
            if key in self.functions_by_name and name not in self.globals:
                fn = self.functions_by_name[key]
                slot, func_index, plan_index = self.callbacks.add(
                    key, fn, self.func_indices[key], self.plans
                )
                self.emit_u8(OP_CREATE_CALLBACK)
                self.emit_u16(slot)
                self.emit_u16(func_index)
                self.emit_u16(plan_index)
                return
        self.emit_operand(text)

    def emit_pointer(self, text: str) -> None:
        text = text.strip()
        if text.startswith("ptr "):
            text = text[4:].strip()
        if text.startswith("@"):
            self.emit_operand(text)
            return
        if text.startswith("null"):
            self.emit_const(0)
            return
        self.emit_operand(text)

    def emit_index_add(self, index: str, step: int) -> None:
        if step == 0:
            return
        if "%" not in index:
            nums = re.findall(r"-?\d+", index)
            if nums:
                off = int(nums[-1]) * step
                if off:
                    self.emit_const(off)
                    self.emit_u8(OP_ADD)
                return
        self.emit_operand(index)
        self.emit_const(step)
        self.emit_u8(OP_MUL)
        self.emit_u8(OP_ADD)

    def lower_gep(self, rhs: str, result: str | None) -> None:
        if result is None:
            raise ValueError("getelementptr without result")
        rest = re.sub(r"^(?:inbounds\s+|nuw\s+)*", "", rhs[len("getelementptr"):].strip())
        parts = split_top(rest)
        if len(parts) < 2:
            raise ValueError(f"bad getelementptr: {rhs}")
        source_ty = parts[0].strip()
        ptr = parts[1].strip()
        indices = [p.strip() for p in parts[2:]]

        self.emit_pointer(ptr)
        current = source_ty
        for pos, index in enumerate(indices):
            if pos == 0:
                self.emit_index_add(index, self.type_size(current))
                continue
            elem = array_element(current)
            fields = struct_fields(current, self.structs)
            if elem is not None:
                self.emit_index_add(index, self.type_size(elem))
                current = elem
            elif fields is not None:
                nums = re.findall(r"-?\d+", index)
                if not nums:
                    raise ValueError(f"non-constant struct index: {index}")
                field_idx = int(nums[-1])
                offsets, _, _ = struct_layout(fields, self.structs, self.ptr_size)
                if field_idx < 0 or field_idx >= len(fields):
                    raise ValueError(f"bad struct field index {field_idx}")
                off = offsets[field_idx]
                if off:
                    self.emit_const(off)
                    self.emit_u8(OP_ADD)
                current = fields[field_idx]
            else:
                raise ValueError(f"too many gep indices for {current}")
        self.store_slot(self.slot_for(result))

    def jump(self, op: int, label: str) -> None:
        self.emit_u8(op)
        self.patches.append((len(self.code), label))
        self.emit_u32(0)

    def lower(self) -> None:
        if self.fn.name == "main" and self.global_data:
            self.emit_u8(OP_SET_MEM_TOP)
            self.emit_u32(len(self.global_data))
            data = self.global_data
            for off in range(0, len(data), 8):
                chunk = int.from_bytes(data[off : off + 8].ljust(8, b"\x00"), "little")
                self.emit_const(chunk)
                self.emit_u8(OP_ADDR_CONST)
                self.emit_u32(off)
                self.emit_u8(OP_STORE_MEM)
                self.emit_u8(min(8, len(data) - off))

        i = 0
        while i < len(self.fn.body):
            line = strip_meta(self.fn.body[i])
            if not line or line.startswith("#dbg"):
                i += 1
                continue
            m = re.match(r"^([\w.$-]+):$", line)
            if m:
                self.label_pos[m.group(1)] = len(self.code)
                i += 1
                continue
            if line.startswith("switch "):
                header = line
                cases: list[str] = []
                i += 1
                while i < len(self.fn.body):
                    part = strip_meta(self.fn.body[i])
                    closed = "]" in part
                    part = part.replace("]", "").strip()
                    if part:
                        cases.append(part)
                    i += 1
                    if closed:
                        break
                self.lower_switch(header, cases)
                continue
            self.lower_instr(line)
            i += 1

        for pos, label in self.patches:
            if label not in self.label_pos:
                raise ValueError(f"unknown label %{label}")
            target = self.label_pos[label]
            self.code[pos:pos + 4] = target.to_bytes(4, "little")

        self.fn.code = bytes(self.code)
        self.fn.local_count = self.next_slot

    def lower_switch(self, header: str, cases: list[str]) -> None:
        m = re.match(r"switch\s+\S+\s+(%[\w.$-]+),\s*label\s+%([\w.$-]+)\s*\[?$", header)
        if not m:
            raise ValueError(f"bad switch: {header}")
        cond, default = m.group(1), m.group(2)
        for case in cases:
            cm = re.match(r"\S+\s+(-?\d+),\s*label\s+%([\w.$-]+)", case)
            if not cm:
                raise ValueError(f"bad switch case: {case}")
            value = int(cm.group(1))
            label = cm.group(2)
            self.emit_operand(cond)
            self.emit_const(value)
            self.emit_u8(OP_CMP_EQ)
            self.jump(OP_JNZ, label)
        self.jump(OP_JMP, default)

    def lower_instr(self, line: str) -> None:
        result: str | None = None
        rhs = line
        if "=" in line:
            lhs, rhs = line.split("=", 1)
            lhs = lhs.strip()
            rhs = rhs.strip()
            if lhs.startswith("%"):
                result = lhs[1:]

        if rhs.startswith("alloca "):
            if result is None:
                raise ValueError("alloca without result")
            ty = re.sub(r",\s*align\s+\d+\s*$", "", rhs[len("alloca "):]).strip()
            if re.search(r",\s*i\d+\s+%", ty):
                raise ValueError("VLA alloca unsupported")
            size = self.type_size(ty)
            if size <= 0 or size > 0xFFFF:
                raise ValueError(f"bad alloca size {size} for {ty}")
            self.emit_u8(OP_ALLOCA)
            self.emit_u16(size)
            self.store_slot(self.slot_for(result))
            return

        if rhs.startswith("store "):
            m = re.match(r"store\s+(\[[^\]]*\]|\{[^}]*\}|[^,]+?)\s+([^,]+),\s*ptr\s+(.+)$", rhs)
            if not m:
                raise ValueError(f"bad store: {line}")
            ty, value, ptr = m.group(1).strip(), m.group(2).strip(), m.group(3).strip()
            size = self.type_size(ty)
            if size <= 0:
                raise ValueError(f"aggregate store unsupported: {ty}")
            if ty in ("x86_fp80", "fp128"):
                self.emit_pointer(ptr)
                self.emit_operand(value)
                self.emit_const(size)
                self.emit_u8(OP_MEMCPY)
                return
            if size > 8 and ty.startswith(("%", "[", "{")):
                self.emit_pointer(ptr)
                self.emit_pointer(value)
                self.emit_const(size)
                self.emit_u8(OP_MEMCPY)
                return
            if size > 8:
                raise ValueError(f"aggregate store unsupported: {ty}")
            if ty in ("float", "double"):
                self.emit_float_operand(value, ty)
            else:
                self.emit_operand(value)
            self.emit_pointer(ptr)
            self.emit_u8(OP_STORE_MEM)
            self.emit_u8(size)
            return

        if rhs.startswith("load "):
            if result is None:
                raise ValueError("load without result")
            m = re.match(r"load\s+(\[[^\]]*\]|\{[^}]*\}|[^,]+?)\s*,\s*ptr\s+(.+)$", rhs)
            if not m:
                raise ValueError(f"bad load: {line}")
            ty, ptr = m.group(1).strip(), m.group(2).strip()
            size = self.type_size(ty)
            if ty in ("x86_fp80", "fp128"):
                self.emit_pointer(ptr)
                self.store_slot(self.slot_for(result))
                return
            if size > 8:
                # An aggregate value is represented by a pointer to its bytes.
                self.emit_pointer(ptr)
                self.store_slot(self.slot_for(result))
                return
            if size <= 0:
                raise ValueError(f"aggregate load unsupported: {ty}")
            self.emit_pointer(ptr)
            self.emit_u8(OP_LOAD_MEM)
            self.emit_u8(size)
            self.store_slot(self.slot_for(result))
            return

        m = re.match(r"(fadd|fsub|fmul|fdiv)\s+(?:fast\s+)?(double|float|x86_fp80|fp128)\s+(.+)$", rhs)
        if m:
            if result is None:
                raise ValueError(f"float arithmetic without result: {line}")
            ty = m.group(2)
            a, b = split_top(m.group(3), ",")
            self.emit_float_operand(a, ty)
            self.emit_float_operand(b, ty)
            if ty == "x86_fp80":
                self.emit_u8({
                    "fadd": OP_F80_ADD,
                    "fsub": OP_F80_SUB,
                    "fmul": OP_F80_MUL,
                    "fdiv": OP_F80_DIV,
                }[m.group(1)])
                self.store_slot(self.slot_for(result))
                return
            if ty == "fp128":
                self.emit_u8({
                    "fadd": OP_F128_ADD,
                    "fsub": OP_F128_SUB,
                    "fmul": OP_F128_MUL,
                    "fdiv": OP_F128_DIV,
                }[m.group(1)])
                self.store_slot(self.slot_for(result))
                return
            ops = {
                "double": {
                    "fadd": OP_FADD,
                    "fsub": OP_FSUB,
                    "fmul": OP_FMUL,
                    "fdiv": OP_FDIV,
                },
                "float": {
                    "fadd": OP_FADD32,
                    "fsub": OP_FSUB32,
                    "fmul": OP_FMUL32,
                    "fdiv": OP_FDIV32,
                },
            }
            self.emit_u8(ops[ty][m.group(1)])
            self.store_slot(self.slot_for(result))
            return

        m = re.match(r"fneg\s+(double|float|x86_fp80|fp128)\s+(.+)$", rhs)
        if m:
            if result is None:
                raise ValueError(f"fneg without result: {line}")
            ty = m.group(1)
            if ty == "x86_fp80":
                self.emit_operand(m.group(2))
                self.emit_u8(OP_F80_NEG)
                self.store_slot(self.slot_for(result))
                return
            if ty == "fp128":
                self.emit_operand(m.group(2))
                self.emit_u8(OP_F128_NEG)
                self.store_slot(self.slot_for(result))
                return
            self.emit_float_operand(m.group(2), ty)
            self.emit_const(0x8000000000000000 if ty != "float" else 0x80000000)
            self.emit_u8(OP_XOR)
            self.store_slot(self.slot_for(result))
            return

        if rhs.startswith("fcmp "):
            if result is None:
                raise ValueError(f"fcmp without result: {line}")
            m = re.match(r"fcmp\s+(\w+)\s+(\S+)\s+(.+)$", rhs)
            if not m:
                raise ValueError(f"bad fcmp: {line}")
            src_ty = m.group(2)
            if src_ty not in ("double", "float", "x86_fp80", "fp128"):
                raise ValueError(f"unsupported fcmp type: {src_ty}")
            pred = m.group(1)
            pred_code = {
                "oeq": 0,
                "one": 1,
                "olt": 2,
                "ole": 3,
                "ogt": 4,
                "oge": 5,
                "ord": 6,
                "uno": 7,
            }.get(pred)
            if pred_code is None:
                raise ValueError(f"unsupported fcmp predicate: {pred}")
            a, b = split_top(m.group(3), ",")
            if src_ty in ("x86_fp80", "fp128"):
                self.emit_operand(a)
                self.emit_operand(b)
                self.emit_u8(OP_F80_CMP if src_ty == "x86_fp80" else OP_F128_CMP)
                self.emit_u8(pred_code)
                self.store_slot(self.slot_for(result))
                return
            self.emit_float_operand(a, src_ty)
            self.emit_float_operand(b, src_ty)
            self.emit_u8(OP_FCMP if src_ty != "float" else OP_FCMP32)
            self.emit_u8(pred_code)
            self.store_slot(self.slot_for(result))
            return

        m = re.match(
            r"(add|sub|mul|sdiv|udiv|srem|urem|and|or|xor|shl|lshr|ashr)\s+"
            r"(?:nsw\s+|nuw\s+|exact\s+)?\S+\s+(.+)$",
            rhs,
        )
        if m:
            if result is None:
                raise ValueError(f"arithmetic without result: {line}")
            a, b = split_top(m.group(2), ",")
            self.emit_operand(a)
            self.emit_operand(b)
            self.emit_u8({
                "add": OP_ADD,
                "sub": OP_SUB,
                "mul": OP_MUL,
                "sdiv": OP_DIV_S,
                "udiv": OP_DIV_U,
                "srem": OP_REM_S,
                "urem": OP_REM_U,
                "and": OP_AND,
                "or": OP_OR,
                "xor": OP_XOR,
                "shl": OP_SHL,
                "lshr": OP_SHR_U,
                "ashr": OP_SHR_S,
            }[m.group(1)])
            self.store_slot(self.slot_for(result))
            return

        m = re.match(r"icmp\s+(\w+)\s+\S+\s+(.+)$", rhs)
        if m:
            if result is None:
                raise ValueError(f"icmp without result: {line}")
            pred = m.group(1)
            a, b = split_top(m.group(2), ",")
            invert = False
            if pred in ("eq",):
                self.emit_operand(a)
                self.emit_operand(b)
                self.emit_u8(OP_CMP_EQ)
            elif pred in ("ne",):
                self.emit_operand(a)
                self.emit_operand(b)
                self.emit_u8(OP_CMP_EQ)
                invert = True
            elif pred in ("slt", "ult"):
                self.emit_operand(a)
                self.emit_operand(b)
                self.emit_u8(OP_CMP_LT if pred == "slt" else OP_CMP_LT_U)
            elif pred in ("sgt", "ugt"):
                self.emit_operand(b)
                self.emit_operand(a)
                self.emit_u8(OP_CMP_LT if pred == "sgt" else OP_CMP_LT_U)
            elif pred in ("sle", "ule"):
                self.emit_operand(b)
                self.emit_operand(a)
                self.emit_u8(OP_CMP_LT if pred == "sle" else OP_CMP_LT_U)
                invert = True
            elif pred in ("sge", "uge"):
                self.emit_operand(a)
                self.emit_operand(b)
                self.emit_u8(OP_CMP_LT if pred == "sge" else OP_CMP_LT_U)
                invert = True
            else:
                raise ValueError(f"unsupported icmp predicate: {pred}")
            if invert:
                self.emit_const(1)
                self.emit_u8(OP_XOR)
            self.store_slot(self.slot_for(result))
            return

        m = re.match(
            r"(trunc|zext|sext|fptosi|sitofp|fpext|fptrunc)\s+(\S+)\s+(.+?)\s+to\s+(\S+)$",
            rhs,
        )
        if m:
            if result is None:
                raise ValueError(f"cast without result: {line}")
            op, src_ty, value, dst_ty = m.group(1), m.group(2), m.group(3), m.group(4)
            if src_ty in ("x86_fp80", "fp128"):
                self.emit_operand(value)
            elif op in ("fptosi", "fptrunc", "fpext"):
                self.emit_float_operand(value, src_ty)
            else:
                self.emit_operand(value)
            if op == "fptosi":
                if src_ty == "x86_fp80":
                    self.emit_u8(OP_F80_TO_I64)
                elif src_ty == "fp128":
                    self.emit_u8(OP_F128_TO_I64)
                else:
                    self.emit_u8(OP_FPTOSI32 if src_ty == "float" else OP_FPTOSI)
            elif op == "sitofp":
                if dst_ty == "x86_fp80":
                    self.emit_u8(OP_F80_FROM_I64)
                elif dst_ty == "fp128":
                    self.emit_u8(OP_F128_FROM_I64)
                else:
                    self.emit_u8(OP_SITOFP32 if dst_ty == "float" else OP_SITOFP)
            elif op == "fpext":
                if src_ty == "float" and dst_ty == "double":
                    self.emit_u8(OP_FPEXT)
                elif src_ty == "float" and dst_ty == "x86_fp80":
                    self.emit_u8(OP_F80_FROM_F32)
                elif src_ty == "double" and dst_ty == "x86_fp80":
                    self.emit_u8(OP_F80_FROM_F64)
                elif src_ty == "float" and dst_ty == "fp128":
                    self.emit_u8(OP_F128_FROM_F32)
                elif src_ty == "double" and dst_ty == "fp128":
                    self.emit_u8(OP_F128_FROM_F64)
                else:
                    raise ValueError(f"unsupported fpext {src_ty} -> {dst_ty}")
            elif op == "fptrunc":
                if src_ty == "double" and dst_ty == "float":
                    self.emit_u8(OP_FPTRUNC)
                elif src_ty == "x86_fp80" and dst_ty == "float":
                    self.emit_u8(OP_F80_TO_F32)
                elif src_ty == "x86_fp80" and dst_ty == "double":
                    self.emit_u8(OP_F80_TO_F64)
                elif src_ty == "fp128" and dst_ty == "float":
                    self.emit_u8(OP_F128_TO_F32)
                elif src_ty == "fp128" and dst_ty == "double":
                    self.emit_u8(OP_F128_TO_F64)
                else:
                    raise ValueError(f"unsupported fptrunc {src_ty} -> {dst_ty}")
            elif not src_ty.startswith("i") or not dst_ty.startswith("i"):
                raise ValueError(f"unsupported cast {op} {src_ty} -> {dst_ty}")
            else:
                src_bits = int(src_ty[1:])
                dst_bits = int(dst_ty[1:])
                if op == "trunc":
                    self.emit_const((1 << dst_bits) - 1)
                    self.emit_u8(OP_AND)
                elif op == "zext":
                    self.emit_const((1 << src_bits) - 1)
                    self.emit_u8(OP_AND)
                else:
                    shift = 64 - src_bits
                    if shift > 0:
                        self.emit_const(shift)
                        self.emit_u8(OP_SHL)
                        self.emit_const(shift)
                        self.emit_u8(OP_SHR_S)
            self.store_slot(self.slot_for(result))
            return

        if rhs.startswith("extractvalue "):
            if result is None:
                raise ValueError("extractvalue without result")
            em = re.match(r"extractvalue\s+(.+?)\s+(%[\w.$-]+),\s*(\d+)$", rhs)
            if not em:
                raise ValueError(f"bad extractvalue: {line}")
            agg_ty, value, index_text = em.group(1).strip(), em.group(2), em.group(3)
            fields = struct_fields(agg_ty, self.structs)
            if fields is None:
                raise ValueError(f"bad extractvalue type {agg_ty}")
            offsets, _, _ = struct_layout(fields, self.structs, self.ptr_size)
            index = int(index_text)
            if index < 0 or index >= len(fields):
                raise ValueError(f"bad extractvalue index {index}")
            field_ty = fields[index]
            self.emit_pointer(value)
            if offsets[index]:
                self.emit_const(offsets[index])
                self.emit_u8(OP_ADD)
            self.emit_u8(OP_LOAD_MEM)
            self.emit_u8(self.type_size(field_ty))
            self.store_slot(self.slot_for(result))
            return

        if rhs.startswith("getelementptr "):
            self.lower_gep(rhs, result)
            return

        if rhs.startswith("select "):
            if result is None:
                raise ValueError(f"select without result: {line}")
            parts = split_top(rhs[len("select "):])
            if len(parts) != 3:
                raise ValueError(f"bad select: {line}")
            cond = parts[0].strip()
            true_val = parts[1].strip()
            false_val = parts[2].strip()
            n = self.select_id
            self.select_id += 1
            else_label = f"__select_else_{n}"
            end_label = f"__select_end_{n}"
            self.emit_operand(cond)
            self.jump(OP_JZ, else_label)
            self.emit_operand(true_val)
            self.jump(OP_JMP, end_label)
            self.label_pos[else_label] = len(self.code)
            self.emit_operand(false_val)
            self.label_pos[end_label] = len(self.code)
            self.store_slot(self.slot_for(result))
            return

        if rhs.startswith("br "):
            m = re.match(r"br\s+i1\s+(%[\w.$-]+),\s*label\s+%([\w.$-]+),\s*label\s+%([\w.$-]+)", rhs)
            if m:
                self.emit_operand(m.group(1))
                self.jump(OP_JNZ, m.group(2))
                self.jump(OP_JMP, m.group(3))
                return
            m = re.match(r"br\s+label\s+%([\w.$-]+)", rhs)
            if m:
                self.jump(OP_JMP, m.group(1))
                return
            raise ValueError(f"bad br: {line}")

        if rhs == "ret void":
            self.emit_u8(OP_RET_VOID)
            return
        m = re.match(r"ret\s+(\S+)\s+(.+)$", rhs)
        if m:
            if m.group(1) in ("float", "double", "x86_fp80"):
                self.emit_float_operand(m.group(2), m.group(1))
            else:
                self.emit_operand(m.group(2))
            self.emit_u8(OP_RET)
            return

        if re.match(r"(?:tail\s+)?call\s+void\s+@llvm\.(lifetime|dbg)\.", rhs):
            return

        m = re.match(r"(?:tail\s+)?call\s+void\s+@llvm\.(memcpy|memset)\.[^(]*\((.*)\)$", rhs)
        if m:
            kind = m.group(1)
            args = split_top(m.group(2))
            if len(args) < 3:
                raise ValueError(f"bad {kind}: {line}")
            self.emit_pointer(args[0])
            if kind == "memcpy":
                self.emit_pointer(args[1])
                self.emit_operand(args[2])
                self.emit_u8(OP_MEMCPY)
            else:
                self.emit_operand(args[1])
                self.emit_operand(args[2])
                self.emit_u8(OP_MEMSET)
            return

        m = re.match(r"(?:tail\s+)?call\s+(.*?)\s+@([\w.$-]+)\((.*)\)$", rhs)
        if m:
            ret_expr = re.sub(r"\s*\([^()]*\)\s*$", "", m.group(1).strip()).strip()
            ret_type, fname, args_text = ret_expr, m.group(2), m.group(3)
            args = split_top(args_text) if args_text.strip() else []
            arg_types: list[str] = []
            arg_values: list[str] = []
            for arg in args:
                tm = re.match(r"(\[[^\]]*\]|%[\w.$-]+|\S+)\s+(.+)$", arg.strip())
                if not tm:
                    raise ValueError(f"bad call argument: {arg!r}")
                arg_types.append(tm.group(1).strip())
                arg_values.append(arg.strip())

            if fname not in self.func_indices:
                decl = self.decls.get(fname)
                is_varargs = decl[2] if decl else ("..." in rhs)
                sret_idx: int | None = None
                sret_size = 0
                byval_sizes = [0] * len(args)
                for idx, arg in enumerate(args):
                    sm = re.search(r"\bsret\(([^)]+)\)", arg)
                    if sm:
                        sret_idx = idx
                        sret_size = self.type_size(sm.group(1))
                    bm = re.search(r"\bbyval\(([^)]+)\)", arg)
                    if bm:
                        byval_sizes[idx] = self.type_size(bm.group(1))
                plan_ret = "void" if sret_idx is not None else ret_type
                named_count = len(decl[1]) if (is_varargs and decl) else None
                plan = build_plan(
                    self.abi,
                    fname,
                    plan_ret,
                    arg_types,
                    is_varargs,
                    sret_idx,
                    sret_size,
                    byval_sizes,
                    self.structs,
                    self.ptr_size,
                    named_count,
                )
                plan_index = self.plans.add(plan)
                for value in arg_values:
                    self.emit_arg(value)
                self.emit_u8(OP_CALL_VARARG if is_varargs else OP_CALL_NATIVE)
                self.emit_u16(plan_index)
                if ret_type != "void":
                    if result is None:
                        raise ValueError(f"call without result: {line}")
                    self.store_slot(self.slot_for(result))
                return

            for value in arg_values:
                self.emit_operand(value)
            self.emit_u8(OP_CALL)
            self.emit_u16(self.func_indices[fname])
            if ret_type != "void":
                if result is None:
                    raise ValueError(f"call without result: {line}")
                self.store_slot(self.slot_for(result))
            return

        if rhs == "unreachable":
            self.emit_u8(OP_RET_VOID)
            return

        raise ValueError(f"unsupported instruction: {line}")


def parse_functions(text: str) -> list[Function]:
    lines = text.splitlines()
    functions: list[Function] = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        line = re.sub(r"\s*!dbg\s*!\d+", "", line).strip()
        m = re.search(r"define\s+(.+?)\s+@([\w.$-]+)\((.*)\)\s*(?:#\d+)?\s*\{", line)
        if not m:
            i += 1
            continue
        pre, name, params_text = m.group(1), m.group(2), m.group(3)
        ret = pre.split()[-1]
        params: list[tuple[str, str]] = []
        raw_params = split_top(params_text) if params_text.strip() else []
        for p in raw_params:
            pm = re.match(r"(i\d+|ptr|void|double|float|x86_fp80|fp128)\s+.*%([\w.$-]+)", p)
            if not pm:
                raise ValueError(f"bad parameter: {p!r}")
            params.append((pm.group(1), pm.group(2)))

        body: list[str] = []
        i += 1
        while i < len(lines) and lines[i].strip() != "}":
            body.append(lines[i])
            i += 1
        functions.append(Function(name=name, ret=ret, params=params, body=body, param_attrs=raw_params))
        i += 1
    return functions


def serialize(functions: list[Function]) -> bytes:
    out = bytearray()
    out += b"CIVM"
    out += bytes([1, 1])
    out += len(functions).to_bytes(2, "little")
    out += (0).to_bytes(2, "little")
    for fn in functions:
        name = fn.name.encode()
        if len(name) > 255:
            raise ValueError("function name too long")
        out += bytes([len(name)])
        out += name
        out += len(fn.params).to_bytes(2, "little")
        out += fn.local_count.to_bytes(2, "little")
        out += len(fn.code).to_bytes(4, "little")
        out += fn.code
    return bytes(out)


def compile_text(text: str, source_name: str = "<input>", abi: str = "sysv", ptr_size: int = 8):
    structs = parse_structs(text)
    globals_map, global_data = parse_globals(text, structs, ptr_size)
    decls = parse_decls(text)
    functions = parse_functions(text)
    indices = {fn.name: idx for idx, fn in enumerate(functions)}
    plans = PlanTable(abi)
    callbacks = CallbackTable(abi, structs, ptr_size)
    functions_by_name = {fn.name: fn for fn in functions}
    for fn in functions:
        fn.index = indices[fn.name]
        Lowerer(
            fn,
            indices,
            structs,
            globals_map,
            global_data,
            decls,
            plans,
            functions_by_name,
            callbacks,
            abi,
            ptr_size,
        ).lower()
    module = serialize(functions)
    plan_bytes = plans.serialize()
    package = write_package(module, plan_bytes)
    return package, module, plan_bytes, functions, plans


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: lower.py input.ll [-o output.cib]", file=sys.stderr)
        return 1
    src = Path(sys.argv[1])
    out_path = Path(sys.argv[3]) if len(sys.argv) >= 4 and sys.argv[2] == "-o" else src.with_suffix(".cib")
    package, module, plan_bytes, functions, plans = compile_text(src.read_text(), str(src))
    out_path.write_bytes(package)
    print(f"wrote {out_path}: {len(functions)} functions, {len(plans.plans)} plans, {len(module)}B module")
    for fn in functions:
        print(f"  {fn.name}: params={len(fn.params)} locals={fn.local_count} code={len(fn.code)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
