#!/usr/bin/env python3
"""Dump cinterp CIPKG v4 headers and disassemble CIVM bytecode.

Usage:
  scripts/tools/cib_dump.py [--headers|--asm] [--data-limit N|--full-data] package.cib [...]
"""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class Bad(Exception):
    pass


def read_u8(data: bytes, pos: int) -> int:
    if pos >= len(data):
        raise Bad("truncated u8")
    return data[pos]


def read_u16(data: bytes, pos: int) -> int:
    if pos + 2 > len(data):
        raise Bad("truncated u16")
    return struct.unpack_from("<H", data, pos)[0]


def read_u32(data: bytes, pos: int) -> int:
    if pos + 4 > len(data):
        raise Bad("truncated u32")
    return struct.unpack_from("<I", data, pos)[0]


def read_i64(data: bytes, pos: int) -> int:
    if pos + 8 > len(data):
        raise Bad("truncated i64")
    return struct.unpack_from("<q", data, pos)[0]


def take(data: bytes, pos: int, length: int) -> tuple[bytes, int]:
    if length < 0 or pos + length > len(data):
        raise Bad("truncated bytes")
    return data[pos : pos + length], pos + length


def xor_bytes(data: bytes, key: bytes) -> bytes:
    return bytes(byte ^ key[i % len(key)] for i, byte in enumerate(data))


ABI_NAMES = {1: "sysv", 2: "win64", 3: "win32", 4: "aapcs64"}
LOC_KINDS = {
    0: "gpr",
    1: "xmm",
    2: "stack",
    3: "sret",
    4: "rax",
    5: "rdx",
    6: "xmm0",
    7: "xmm1",
    8: "st0",
    9: "xmm2",
    10: "xmm3",
}
PRED_NAMES = {
    0: "oeq",
    1: "one",
    2: "olt",
    3: "ole",
    4: "ogt",
    5: "oge",
    6: "ord",
    7: "uno",
}

# opcode -> (name, operand kind).  Operand kinds are decoded below.
NO_ARG = "none"
OPS: dict[int, tuple[str, str]] = {
    0x01: ("RET", NO_ARG),
    0x02: ("RET_VOID", NO_ARG),
    0x10: ("LOAD_CONST_I64", "i64"),
    0x11: ("ADD", NO_ARG),
    0x12: ("SUB", NO_ARG),
    0x13: ("MUL", NO_ARG),
    0x14: ("DUP", NO_ARG),
    0x15: ("POP", NO_ARG),
    0x16: ("SWAP", NO_ARG),
    0x17: ("XOR", NO_ARG),
    0x18: ("DIV_S", NO_ARG),
    0x19: ("DIV_U", NO_ARG),
    0x1A: ("REM_S", NO_ARG),
    0x1B: ("REM_U", NO_ARG),
    0x1C: ("AND", NO_ARG),
    0x1D: ("OR", NO_ARG),
    0x1E: ("SHL", NO_ARG),
    0x1F: ("SHR_S", NO_ARG),
    0x20: ("LOAD_LOCAL", "u16"),
    0x21: ("STORE_LOCAL", "u16"),
    0x24: ("SHR_U", NO_ARG),
    0x25: ("FPTOSI", NO_ARG),
    0x26: ("SITOFP", NO_ARG),
    0x27: ("FADD", NO_ARG),
    0x28: ("FSUB", NO_ARG),
    0x29: ("FMUL", NO_ARG),
    0x2A: ("FDIV", NO_ARG),
    0x2B: ("FCMP", "pred"),
    0x2C: ("FADD32", NO_ARG),
    0x2D: ("FSUB32", NO_ARG),
    0x2E: ("FMUL32", NO_ARG),
    0x2F: ("FDIV32", NO_ARG),
    0x30: ("JMP", "u32target"),
    0x31: ("JZ", "u32target"),
    0x32: ("JNZ", "u32target"),
    0x33: ("CMP_EQ", NO_ARG),
    0x34: ("CMP_LT", NO_ARG),
    0x35: ("CMP_LT_U", NO_ARG),
    0x38: ("FCMP32", "pred"),
    0x39: ("FPEXT", NO_ARG),
    0x3A: ("FPTRUNC", NO_ARG),
    0x3B: ("FPTOSI32", NO_ARG),
    0x3C: ("SITOFP32", NO_ARG),
    0x40: ("CALL", "func"),
    0x41: ("FUNC_ADDR", "func"),
    0x42: ("CALL_INDIRECT", NO_ARG),
    0x60: ("ALLOCA", "u16"),
    0x61: ("LOAD_MEM", "u8"),
    0x62: ("STORE_MEM", "u8"),
    0x63: ("MEMCPY", NO_ARG),
    0x64: ("MEMSET", NO_ARG),
    0x65: ("ADDR_CONST", "u32"),
    0x66: ("SET_MEM_TOP", "u32"),
    0x70: ("CALL_NATIVE", "plan"),
    0x71: ("CALL_VARARG", "plan"),
    0x72: ("CREATE_CALLBACK", "callback"),
    0x73: ("F80_CONST", "f80"),
    0x74: ("F80_ADD", NO_ARG),
    0x75: ("F80_SUB", NO_ARG),
    0x76: ("F80_MUL", NO_ARG),
    0x77: ("F80_DIV", NO_ARG),
    0x78: ("F80_CMP", "pred"),
    0x79: ("F80_FROM_F64", NO_ARG),
    0x7A: ("F80_TO_F64", NO_ARG),
    0x7B: ("F80_FROM_I64", NO_ARG),
    0x7C: ("F80_TO_I64", NO_ARG),
    0x7D: ("F80_FROM_F32", NO_ARG),
    0x7E: ("F80_TO_F32", NO_ARG),
    0x7F: ("F80_NEG", NO_ARG),
    0x80: ("F128_CONST", "f128"),
    0x81: ("F128_ADD", NO_ARG),
    0x82: ("F128_SUB", NO_ARG),
    0x83: ("F128_MUL", NO_ARG),
    0x84: ("F128_DIV", NO_ARG),
    0x85: ("F128_CMP", "pred"),
    0x86: ("F128_NEG", NO_ARG),
    0x87: ("F128_FROM_F64", NO_ARG),
    0x88: ("F128_TO_F64", NO_ARG),
    0x89: ("F128_FROM_I64", NO_ARG),
    0x8A: ("F128_TO_I64", NO_ARG),
    0x8B: ("F128_FROM_F32", NO_ARG),
    0x8C: ("F128_TO_F32", NO_ARG),
    0x8D: ("ALLOCA_DYN", NO_ARG),
    0x8E: ("FPTOUI", NO_ARG),
    0x8F: ("UITOFP", NO_ARG),
    0x90: ("FPTOUI32", NO_ARG),
    0x91: ("UITOFP32", NO_ARG),
    0x92: ("F80_TO_U64", NO_ARG),
    0x93: ("F80_FROM_U64", NO_ARG),
    0x94: ("F128_TO_U64", NO_ARG),
    0x95: ("F128_FROM_U64", NO_ARG),
    0x96: ("ADDR_EXTERN", "import"),
    0x97: ("SETJMP", "u16"),
    0x98: ("LONGJMP", NO_ARG),
    0x99: ("CALL_VARIADIC", "variadic"),
    0x9A: ("VA_START", NO_ARG),
    0x9B: ("VA_COPY", NO_ARG),
    0x9C: ("CALL_INDIRECT_NATIVE", "plan"),
    0x9D: ("STACKSAVE", NO_ARG),
    0x9E: ("STACKRESTORE", NO_ARG),
    0x9F: ("ALLOCA_ALIGNED", "u16u8"),
    0xA0: ("ALLOCA_DYN_ALIGN", "u8"),
    0xA1: ("CALL_VARIADIC_TYPED", "variadic_typed"),
    0xA2: ("FPCLASS", "u8"),
    0xA3: ("CALLBACK_ACQUIRE", "callback_acquire"),
    0xA4: ("CALLBACK_RELEASE", NO_ARG),
    0xA5: ("LOAD_CONST_POOL", "pool"),
    0xA6: ("NORMALIZE", "u8"),
    0xA7: ("FMA", NO_ARG),
    0xA8: ("FMA32", NO_ARG),
    0xA9: ("ADD_N", "u8"),
    0xAA: ("SUB_N", "u8"),
    0xAB: ("MUL_N", "u8"),
    0xAC: ("AND_N", "u8"),
    0xAD: ("OR_N", "u8"),
    0xAE: ("XOR_N", "u8"),
    0xAF: ("MAX_N", "u8"),
    0xB0: ("MIN_N", "u8"),
    0xB1: ("ABS_N", "u8"),
    0xB2: ("CTTZ_N", "u8"),
    0xB3: ("CTLZ_N", "u8"),
    0xB4: ("CTPOP_N", "u8"),
    0xB5: ("BSWAP_N", "u8"),
    0xB6: ("BITREV_N", "u8"),
    0xB7: ("FSHL_N", "u8"),
    0xB8: ("FSHR_N", "u8"),
    0xB9: ("USUB_SAT_N", "u8"),
}


def parse_civm(module: bytes) -> dict:
    if module[:4] != b"CIVM":
        raise Bad("CIVM magic")
    if len(module) < 10:
        raise Bad("CIVM header truncated")
    version = read_u8(module, 4)
    if version != 2:
        raise Bad(f"unsupported CIVM version {version}")
    arch = read_u8(module, 5)
    count = read_u16(module, 6)
    entry = read_u16(module, 8)
    if entry != 0xFFFF and entry >= count:
        raise Bad("CIVM entry index out of range")
    pos = 10
    functions = []
    for index in range(count):
        params = read_u16(module, pos)
        locals_ = read_u16(module, pos + 2)
        code_len = read_u32(module, pos + 4)
        pos += 8
        code, pos = take(module, pos, code_len)
        functions.append(
            {
                "index": index,
                "params": params,
                "locals": locals_,
                "code": code,
                "code_offset": pos - code_len,
            }
        )
    if pos != len(module):
        raise Bad(f"CIVM trailing bytes {len(module) - pos}")
    return {"version": version, "arch": arch, "entry": entry, "functions": functions}


def parse_locs(data: bytes, pos: int, count: int) -> tuple[list[dict], int]:
    locs = []
    for _ in range(count):
        kind = read_u8(data, pos)
        index = read_u16(data, pos + 1)
        size = read_u16(data, pos + 3)
        offset = read_u16(data, pos + 5)
        pos += 7
        locs.append({"kind": kind, "index": index, "size": size, "offset": offset})
    return locs, pos


def parse_cipl(plans: bytes, names: list[str]) -> dict:
    if not plans:
        return {"abi": 0, "plans": [], "omitted": True}
    if len(plans) < 3:
        raise Bad("CIPL header truncated")
    abi = read_u8(plans, 0)
    count = read_u16(plans, 1)
    pos = 3
    parsed = []
    for pi in range(count):
        name_ref = read_u16(plans, pos)
        if name_ref >= len(names):
            raise Bad(f"CIPL name ref {name_ref} out of range")
        name = names[name_ref]
        pos += 2
        args_count = read_u8(plans, pos)
        ret_count = read_u8(plans, pos + 1)
        stack_size = read_u16(plans, pos + 2)
        flags = read_u8(plans, pos + 4)
        ret_size = read_u16(plans, pos + 5)
        pos += 7
        args = []
        for _ in range(args_count):
            arg_flags = read_u8(plans, pos)
            loc_count = arg_flags & 0x0F
            size = read_u16(plans, pos + 1)
            pos += 3
            locs, pos = parse_locs(plans, pos, loc_count)
            args.append(
                {
                    "size": size,
                    "flags": arg_flags,
                    "is_struct": bool(arg_flags & 0x80),
                    "locs": locs,
                }
            )
        ret_locs, pos = parse_locs(plans, pos, ret_count)
        parsed.append(
            {
                "name": name,
                "name_ref": name_ref,
                "flags": flags,
                "args": args,
                "ret_locs": ret_locs,
                "stack_size": stack_size,
                "sret": bool(flags & 1),
                "sse_count": (flags >> 1) & 0x0F,
                "conv": (flags >> 5) & 0x03,
                "native": bool(flags & 0x80),
                "ret_size": ret_size,
            }
        )
    if pos != len(plans):
        raise Bad(f"CIPL trailing bytes {len(plans) - pos}")
    return {"abi": abi, "plans": parsed, "omitted": False}


def parse_imports(imports: bytes, names: list[str]) -> dict:
    if not imports:
        return {"entries": [], "omitted": True}
    pos = 0
    count = read_u16(imports, pos)
    pos += 2
    entries = []
    for _ in range(count):
        plan_index = read_u16(imports, pos)
        kind = read_u8(imports, pos + 2)
        flags = read_u8(imports, pos + 3)
        name_ref = read_u16(imports, pos + 4)
        pos += 6
        if name_ref != 0xFFFF:
            if name_ref >= len(names):
                raise Bad(f"CIPI name ref {name_ref} out of range")
            name = names[name_ref]
        else:
            name = ""
        provider_count = read_u8(imports, pos)
        pos += 1
        providers = []
        for _ in range(provider_count):
            lib_ref = read_u16(imports, pos)
            symbol_ref = read_u16(imports, pos + 2)
            ordinal = read_u16(imports, pos + 4)
            pos += 6
            if lib_ref >= len(names):
                raise Bad(f"CIPI lib ref {lib_ref} out of range")
            symbol = ""
            if symbol_ref != 0xFFFF:
                if symbol_ref >= len(names):
                    raise Bad(f"CIPI symbol ref {symbol_ref} out of range")
                symbol = names[symbol_ref]
            providers.append(
                {
                    "lib_ref": lib_ref,
                    "symbol_ref": symbol_ref,
                    "lib": names[lib_ref],
                    "symbol": symbol,
                    "ordinal": ordinal,
                }
            )
        entries.append(
            {
                "plan_index": plan_index,
                "kind": kind,
                "flags": flags,
                "name_ref": name_ref,
                "name": name,
                "providers": providers,
            }
        )
    if pos != len(imports):
        raise Bad(f"CIPI trailing bytes {len(imports) - pos}")
    return {"entries": entries, "omitted": False}


def parse_cipc(pool: bytes) -> dict:
    if len(pool) < 36 or pool[:4] != b"CIPC":
        raise Bad("CIPC magic/header")
    version = read_u8(pool, 4)
    if version != 2:
        raise Bad(f"unsupported CIPC version {version}")
    flags = read_u8(pool, 5)
    if flags & ~1:
        raise Bad(f"CIPC flags 0x{flags:02x}")
    encrypted = bool(flags & 1)
    key = pool[20:36]
    count = read_u16(pool, 6)
    blob_len = read_u32(pool, 8)
    data_len = read_u32(pool, 12)
    data_base = read_u32(pool, 16)
    offsets_end = 36 + count * 2
    blob_start = offsets_end
    if blob_start + blob_len > len(pool):
        raise Bad("CIPC name blob truncated")
    data_start = (blob_start + blob_len + 15) & ~15
    if data_start + data_len != len(pool):
        raise Bad("CIPC data length")
    name_blob = pool[blob_start : blob_start + blob_len]
    data = pool[data_start : data_start + data_len]
    if encrypted:
        name_blob = xor_bytes(name_blob, key)
        data = xor_bytes(data, key)
    names = []
    name_offsets = []
    for i in range(count):
        off = read_u16(pool, 36 + i * 2)
        begin = off
        if begin >= blob_len:
            raise Bad("CIPC name offset")
        end = name_blob.find(b"\x00", begin, blob_len)
        if end < 0:
            raise Bad("CIPC name offset")
        name_offsets.append(off)
        names.append(name_blob[begin:end].decode("utf-8", "replace"))
    return {
        "version": version,
        "flags": flags,
        "encrypted": encrypted,
        "name_count": count,
        "names": names,
        "name_offsets": name_offsets,
        "name_blob_len": blob_len,
        "data_len": data_len,
        "data_base": data_base,
        "data": data,
    }


def parse_cib(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 22 or data[:5] != b"CIPKG" or data[5] != 4:
        raise Bad("expected CIPKG v4")
    module_len = read_u32(data, 6)
    plan_len = read_u32(data, 10)
    import_len = read_u32(data, 14)
    const_len = read_u32(data, 18)
    if 22 + module_len + plan_len + import_len + const_len != len(data):
        raise Bad("CIPKG section lengths do not match file size")
    module = data[22 : 22 + module_len]
    plans = data[22 + module_len : 22 + module_len + plan_len]
    imports = data[22 + module_len + plan_len : 22 + module_len + plan_len + import_len]
    pool = data[22 + module_len + plan_len + import_len :]
    cipc = parse_cipc(pool)
    return {
        "path": path,
        "size": len(data),
        "module_len": module_len,
        "plan_len": plan_len,
        "import_len": import_len,
        "const_len": const_len,
        "civm": parse_civm(module),
        "cipl": parse_cipl(plans, cipc["names"]),
        "cipi": parse_imports(imports, cipc["names"]),
        "cipc": cipc,
    }


def loc_text(loc: dict) -> str:
    kind = LOC_KINDS.get(loc["kind"], f"kind{loc['kind']}")
    return f"{kind}{loc['index']}:{loc['size']}@{loc['offset']}"


IMPORT_FLAGS = (("required", 0x01), ("lazy", 0x02), ("fallback", 0x04), ("override", 0x08))


def flag_text(value: int) -> str:
    names = [name for name, bit in IMPORT_FLAGS if value & bit]
    return ",".join(names) if names else "-"


def hexdump(data: bytes, limit: int | None, base: int = 0) -> list[str]:
    shown = data if limit is None else data[:limit]
    lines = []
    for off in range(0, len(shown), 16):
        chunk = shown[off : off + 16]
        hex_part = " ".join(f"{byte:02x}" for byte in chunk)
        ascii_part = "".join(chr(byte) if 32 <= byte < 127 else "." for byte in chunk)
        lines.append(f"    {base + off:04x}: {hex_part:<47}  |{ascii_part}|")
    if limit is not None and len(data) > len(shown):
        lines.append(f"    ... {len(data) - len(shown)} more byte(s); use --full-data to show all")
    return lines


def header_text(cib: dict, data_limit: int | None = 256) -> str:
    civm = cib["civm"]
    cipl = cib["cipl"]
    cipi = cib["cipi"]
    lines = [
        f"file: {cib['path']}",
        f"size: {cib['size']} bytes",
        "CIPKG: v4",
        f"  module: off=22 len={cib['module_len']}",
        f"  plans:  off={22 + cib['module_len']} len={cib['plan_len']}"
        + (" (omitted)" if cipl["omitted"] else ""),
        f"  imports: off={22 + cib['module_len'] + cib['plan_len']} len={cib['import_len']}"
        + (" (omitted)" if cipi["omitted"] else ""),
        f"  const:   off={22 + cib['module_len'] + cib['plan_len'] + cib['import_len']} len={cib['const_len']}",
        f"CIVM: v{civm['version']} arch={civm['arch']} entry={civm['entry']} functions={len(civm['functions'])}",
        f"CIPC: v{cib['cipc']['version']} names={len(cib['cipc']['names'])} "
        f"data={cib['cipc']['data_len']} bytes base=0x{cib['cipc']['data_base']:08x} "
        f"flags=0x{cib['cipc']['flags']:02x} encrypted={'yes' if cib['cipc']['encrypted'] else 'no'}",
    ]
    cipc = cib["cipc"]
    for index, name in enumerate(cipc["names"]):
        off = cipc["name_offsets"][index]
        lines.append(f"  name[{index}] off=0x{off:04x} ref=0x{index:04x} {name!r}")
    if cipc["data_len"]:
        lines.append(f"  data[{cipc['data_len']} bytes]:")
        lines.extend(hexdump(cipc["data"], data_limit, cipc["data_base"]))
    for fn in civm["functions"]:
        lines.append(
            f"  [{fn['index']}] params={fn['params']} "
            f"locals={fn['locals']} code={len(fn['code'])} bytes "
            f"code_off=0x{fn['code_offset']:04x}"
        )
    if cipl["omitted"]:
        lines.append("CIPL: omitted")
    else:
        abi = ABI_NAMES.get(cipl["abi"], f"abi{cipl['abi']}")
        lines.append(f"CIPL: abi={abi} plans={len(cipl['plans'])}")
        for index, plan in enumerate(cipl["plans"]):
            lines.append(
                f"  [{index}] ref=0x{plan['name_ref']:04x} {plan['name']}: "
                f"args={len(plan['args'])} rets={len(plan['ret_locs'])} "
                f"stack={plan['stack_size']} flags=0x{plan['flags']:02x} "
                f"sret={int(plan['sret'])} sse={plan['sse_count']} "
                f"conv={plan['conv']} ret_size={plan['ret_size']} "
                f"native={int(plan['native'])}"
            )
            for ai, arg in enumerate(plan["args"]):
                locs = ", ".join(loc_text(loc) for loc in arg["locs"])
                struct = " struct" if arg["is_struct"] else ""
                lines.append(
                    f"      arg{ai}: flags=0x{arg['flags']:02x} "
                    f"size={arg['size']}{struct} locs=[{locs}]"
                )
            if plan["ret_locs"]:
                lines.append(
                    "      ret: "
                    + ", ".join(loc_text(loc) for loc in plan["ret_locs"])
                )
    if cipi["omitted"]:
        lines.append("CIPI: omitted")
    else:
        lines.append(f"CIPI: entries={len(cipi['entries'])}")
        for index, entry in enumerate(cipi["entries"]):
            plan = (
                "data"
                if entry["plan_index"] == 0xFFFF
                else f"plan {entry['plan_index']}"
            )
            display_name = entry["name"]
            if not display_name and entry["plan_index"] != 0xFFFF:
                display_name = (
                    cipl["plans"][entry["plan_index"]]["name"]
                    if entry["plan_index"] < len(cipl["plans"])
                    else ""
                )
            name_ref = "0xffff" if entry["name_ref"] == 0xFFFF else f"0x{entry['name_ref']:04x}"
            kind = "data" if entry["kind"] == 1 else "function"
            lines.append(
                f"  [{index}] {plan} kind={entry['kind']}({kind}) "
                f"flags=0x{entry['flags']:02x}({flag_text(entry['flags'])}) "
                f"name_ref={name_ref} name={display_name} "
                f"providers={len(entry['providers'])}"
            )
            for provider in entry["providers"]:
                ordinal = f" ordinal={provider['ordinal']}" if provider["ordinal"] else ""
                symbol = provider["symbol"] or display_name
                lines.append(
                    f"      lib_ref=0x{provider['lib_ref']:04x} "
                    f"symbol_ref=0x{provider['symbol_ref']:04x} "
                    f"{provider['lib']}:{symbol}{ordinal}"
                )
    return "\n".join(lines)


def read_operand(kind: str, code: bytes, pos: int, functions: list[dict], plans: list[dict], imports: list[dict]) -> tuple[str, int]:
    if kind == NO_ARG:
        return "", pos
    if kind == "u8":
        return f" {read_u8(code, pos)}", pos + 1
    if kind == "u16":
        return f" {read_u16(code, pos)}", pos + 2
    if kind == "u32":
        return f" {read_u32(code, pos)}", pos + 4
    if kind == "pool":
        ref = read_u32(code, pos)
        off = ref & 0x0FFFFFFF
        width = 1 << ((ref >> 28) & 3)
        signed = bool(ref & (1 << 30))
        return f" off={off} width={width} signed={int(signed)}", pos + 4
    if kind == "u32target":
        value = read_u32(code, pos)
        return f" @0x{value:04x}", pos + 4
    if kind == "i64":
        value = read_i64(code, pos)
        return f" {value} (0x{value & 0xFFFFFFFFFFFFFFFF:x})", pos + 8
    if kind == "pred":
        value = read_u8(code, pos)
        return f" {PRED_NAMES.get(value, str(value))}", pos + 1
    if kind == "f80":
        raw, pos = take(code, pos, 10)
        return f" {raw.hex()}", pos
    if kind == "f128":
        raw, pos = take(code, pos, 16)
        return f" {raw.hex()}", pos
    if kind == "func":
        index = read_u16(code, pos)
        name = f"fn{index}" if index < len(functions) else "?"
        return f" {index} ({name})", pos + 2
    if kind == "plan":
        index = read_u16(code, pos)
        name = plans[index]["name"] if index < len(plans) else "?"
        return f" {index} ({name})", pos + 2
    if kind == "import":
        index = read_u16(code, pos)
        name = imports[index]["name"] if index < len(imports) else "?"
        return f" {index} ({name})", pos + 2
    if kind == "callback":
        slot = read_u16(code, pos)
        func = read_u16(code, pos + 2)
        plan = read_u16(code, pos + 4)
        fname = f"fn{func}" if func < len(functions) else "?"
        pname = plans[plan]["name"] if plan < len(plans) else "?"
        return f" slot={slot} func={func} ({fname}) plan={plan} ({pname})", pos + 6
    if kind == "callback_acquire":
        plan = read_u16(code, pos)
        func = read_u16(code, pos + 2)
        pname = plans[plan]["name"] if plan < len(plans) else "?"
        fname = f"fn{func}" if func < len(functions) else "?"
        return f" plan={plan} ({pname}) func={func} ({fname})", pos + 4
    if kind == "u16u8":
        size = read_u16(code, pos)
        align = read_u8(code, pos + 2)
        return f" size={size} align={align}", pos + 3
    if kind == "variadic":
        func = read_u16(code, pos)
        total = read_u16(code, pos + 2)
        fname = f"fn{func}" if func < len(functions) else "?"
        return f" func={func} ({fname}) total={total}", pos + 4
    if kind == "variadic_typed":
        func = read_u16(code, pos)
        total = read_u16(code, pos + 2)
        pos += 4
        fname = f"fn{func}" if func < len(functions) else "?"
        params = functions[func]["params"] if func < len(functions) else 0
        extra = max(total - params, 0)
        types = []
        for _ in range(extra):
            type_code = read_u8(code, pos)
            pos += 1
            if type_code == 3:
                size = read_u16(code, pos)
                pos += 2
                types.append(f"3:{size}")
            else:
                types.append(str(type_code))
        return f" func={func} ({fname}) total={total} extra=[{','.join(types)}]", pos
    raise Bad(f"unknown operand kind {kind}")


def asm_text(cib: dict) -> str:
    functions = cib["civm"]["functions"]
    plans = cib["cipl"]["plans"]
    imports = cib["cipi"]["entries"]
    lines = []
    for fn in functions:
        code = fn["code"]
        marker = " entry" if fn["index"] == cib["civm"]["entry"] else ""
        lines.append(
            f"\nfn{fn['index']}{marker}: params={fn['params']} locals={fn['locals']} code={len(code)}"
        )
        pos = 0
        while pos < len(code):
            start = pos
            opcode = code[pos]
            pos += 1
            info = OPS.get(opcode)
            if info is None:
                lines.append(f"  {start:04x}: {opcode:02x}              .byte 0x{opcode:02x}")
                continue
            name, kind = info
            operands = ""
            try:
                operands, pos = read_operand(kind, code, pos, functions, plans, imports)
            except Bad:
                lines.append(
                    f"  {start:04x}: {code[start:].hex():<20} {name}{operands} <truncated>"
                )
                break
            raw = code[start:pos]
            raw_text = raw.hex()
            if len(raw_text) > 24:
                raw_text = raw_text[:21] + "..."
            lines.append(f"  {start:04x}: {raw_text:<24} {name}{operands}")
    return "\n".join(lines)


def dump(path: Path, show_headers: bool, show_asm: bool, data_limit: int | None) -> None:
    cib = parse_cib(path)
    print(f"==> {path} ==")
    if show_headers:
        print(header_text(cib, data_limit))
    if show_asm:
        print(asm_text(cib))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--headers", action="store_true", help="print headers only")
    mode.add_argument("--asm", action="store_true", help="print disassembly only")
    parser.add_argument("--data-limit", type=int, default=256,
                        help="CIPC data bytes to hexdump (default: 256)")
    parser.add_argument("--full-data", action="store_true", help="hexdump all CIPC data")
    parser.add_argument("packages", nargs="+", type=Path)
    args = parser.parse_args()
    show_headers = not args.asm
    show_asm = not args.headers
    failed = False
    for package in args.packages:
        try:
            data_limit = None if args.full_data else max(0, args.data_limit)
            dump(package, show_headers, show_asm, data_limit)
        except (OSError, Bad) as exc:
            print(f"{package}: {exc}", file=sys.stderr)
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
