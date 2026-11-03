# `.cib` 文件结构

`.cib` 是 `cinterp compile` 生成的**发布包**。当前外层格式为 `CIPKG` v2，内部由四个 section 组成：

1. `CIVM`：字节码模块（函数表 + 每个函数的 code）；
2. `CIPL`：FFI/callback 计划表（每个外部符号的参数/返回位置）；
3. `CIPM`：目标声明（架构、OS、ABI、指针宽度、端序、特性、链接数据库版本）；
4. `CIPI`：外部符号链接表（plan → provider 库/符号/别名/架构/最低 OS）。

运行时按“包 → 目标校验 → 模块 → 计划 → import 校验 → 固定汇编引擎”的顺序工作。`CIPKG` v1（无 CIPM/CIPI）仍然可读。本文描述的是**当前实现**的二进制格式；代码是最终事实来源：

- `compiler-zig/src/main.zig`：`CIPKG`、CIPM、CIPI 写入
- `compiler-zig/src/lower_ast.zig`：CIVM、opcode、globals 初始化
- `compiler-zig/src/abi.zig`：CIPL、`Loc`/`ArgPlan`/`CallPlan`
- `compiler-zig/src/imports.zig`：CIPI 结构与序列化
- `compiler-zig/src/cstdapi.zig` / `winmd.zig`：C 标准库/Windows API 自动链接
- `runtime/src/vm.zig`：CIVM 解析、opcode 执行、C ABI、provider 解析
- `runtime/src/ffi/plan_loader.zig`：CIPL 解析
- `runtime/src/ffi/link_loader.zig`：CIPM/CIPI 解析
- `runtime/src/ffi/platform.zig`：ABI/frame/marshal 选择与目标校验

## 1. 通用约定

- 所有多字节整数/浮点位模式均为**小端**。
- 没有对齐 padding、checksum、签名或压缩。
- `CIVM` 是虚拟机字节码，不是宿主 CPU 机器码；`CIPKG`/CIPL 的 ABI id 指示计划对应的宿主 ABI。
- v2 包的 CIPM 目标必须与运行时一致；否则在解析模块/计划前返回 `TargetMismatch`。计划表与运行时 ABI 仍必须一致（`BadAbi`）。
- CIPI 的 plan 索引必须指向本包 CIPL 中的外部计划；运行时加载时校验。
- 所有二进制长度按实际字节数写入，读取器会拒绝截断、尾随字节和越界计数。

## 2. CIPKG 外层

### 2.1 v2（当前）

```
offset  size  field
0       5     magic = "CIPKG"
5       1     version = 2
6       1     flags            # bit0=has_target, bit1=has_imports
7       2     header_size = 25 # u16 LE
9       4     module_len (u32 LE)
13      4     plan_len   (u32 LE)
17      4     meta_len   (u32 LE)
21      4     import_len (u32 LE)
25      module_len       CIVM module bytes
...     plan_len         CIPL plan table bytes
...     meta_len         CIPM target section
...     import_len       CIPI import section
```

约束：

- `header_size` 当前必须为 25；section 顺序固定。
- `25 + module_len + plan_len + meta_len + import_len` 必须精确等于文件长度；不允许 padding。
- `meta_len` 至少包含完整的 CIPM v1（29 字节头 + 字符串）。
- `import_len` 可以为 0；编译器在无外部符号时写 10 字节空 CIPI 头，不是省略。
- 运行时模块上限 `MAX_MODULE = 2097152` 字节；CLI 读取包文件上限 16 MiB。
- v2 在加载模块前执行目标校验；CIPI 在计划加载后校验 plan 索引。

### 2.2 v1（兼容）

```
offset  size  field
0       5     magic = "CIPKG"
5       1     version = 1
6       1     reserved = 0
7       4     module_len (u32 LE)
11      4     plan_len   (u32 LE)
15      module_len  CIVM module bytes
15+module_len plan_len  CIPL plan table bytes
```

v1 没有 CIPM/CIPI；运行时根据 CIPL 的 `abi_id` 做旧式校验，并保留旧的全局符号搜索/`--lib` 行为。旧包不触发自动 provider 链接。

### 2.3 CIPM：目标声明（v1）

```
offset size field
0      4    magic = "CIPM"
4      1    version = 1
5      2    header_size = 29 (u16 LE)
7      1    arch           # 1=x86_64, 2=x86, 3=aarch64
8      1    os             # 1=linux, 2=windows
9      1    abi            # 1=sysv, 2=win64, 3=win32, 4=aapcs64
10     1    ptr_bits       # 32/64
11     1    endian         # 1=little
12     1    flags
13     8    features (u64 LE)
21     2    min_runtime (u16)
23     2    triple_len
25     2    link_db_len
27     2    producer_len
29     triple_len       canonical target triple（UTF-8）
...    link_db_len      "cstdapi@<commit>;winmd@<commit>"
...    producer_len     "cinterp 0.1.0"
```

- `features` 位：bit0=f80、bit1=f128、bit2=callback、bit3=varargs、bit4=auto-link、bit5=stdcall。运行时按位检查，缺失返回 `UnsupportedFeature`。
- `min_runtime` 高于运行时版本时返回 `RuntimeTooOld`。
- `triple` 用于诊断；快速校验使用 arch/os/abi/ptr_bits/endian。
- `link_db` 记录生成 CIPI 时使用的 cstdapi/winmd 上游版本；没有 import 时可以为空。

### 2.4 CIPI：外部符号链接表（v1）

```
offset size field
0      4    magic = "CIPI"
4      1    version = 1
5      1    flags
6      2    entry_count (u16)
8      2    reserved = 0
10     entry[]
```

每个 entry：

```
2     plan_index       # CIPL 计划索引；0xffff 预留给 data 符号
1     kind             # 0=function, 1=data
1     flags            # bit0=required, bit1=lazy, bit2=allow_fallback, bit3=allow_override
1     callconv         # 0=cdecl, 1=stdcall/winapi
1     arch_mask        # bit0=x86_64, bit1=x86, bit2=aarch64; 0=all
2     min_os           # 0=unknown; Windows 编码为 (major<<8)|minor
1     name_len
N     name             # 逻辑符号名（plan 名，可能含 Win32 修饰）
1     provider_count
provider[]:
  1   kind             # 0=system library name, 1=SONAME/DLL name, 2=path（自动链接禁用）
  1   name_len
  N   name             # e.g. libc.so.6 / libm.so.6 / ucrtbase.dll / user32.dll
  1   symbol_len
  N   symbol           # provider 内真实符号，例如 _snprintf / GetTickCount64
  2   ordinal          # 0=按名；非 0=Windows ordinal
  1   version_len
  N   version          # 预留（GLIBC_2.x / API set 版本）
```

- `plan_index` 绑定 CIPL；`0xffff` 表示 data entry，`ADDR_EXTERN` 使用 entry 索引解析地址。同一符号多次调用可以有多条 entry。
- provider 按顺序尝试；成功后缓存库 handle 和符号地址。
- 自动生成的 provider 只能是系统库名/allowlist；运行时会拒绝包含 `/`、`\` 或 `:` 的自动 provider 名，避免 CIB 指定任意路径。显式 `--lib` 仍允许用户路径。
- 一个进程只执行一个 CIB；CIPI 不提供 CIB-to-CIB 链接/包间导出表，跨包请合并源码后重新生成。
- `arch_mask` 与 `min_os` 在加载时校验；不匹配返回 `ImportArchMismatch` / `ImportUnavailable`。
- `kind=data` 已支持 `stdout`/`errno` 类 external data：编译器为未知外部全局生成 data entry，运行时按 provider/`--lib` 解析地址；`ordinal` 解析在 Windows 已支持。

### 2.5 运行时符号解析顺序

对有 CIPI entry 的计划：

1. 若 entry 允许 override，先搜索用户 `--lib` 加载的库（逆序）。
2. 按 CIPI provider 顺序 `dlopen`/`LoadLibraryA` 并 `dlsym`/`GetProcAddress`；缓存成功结果。
3. 若 entry 允许 fallback，再走旧的进程默认 → `--lib` → CRT 搜索。
4. 否则返回 `SymbolNotFound`。

没有 CIPI entry 的计划（旧 v1 包或未收录的自定义符号）仍走旧搜索路径。

### 2.6 自动链接数据库

编译器按 target 自动生成 CIPI，只写实际使用的外部符号：

- **C 标准库**：`compiler-zig/src/data/cstdapi.generated.json` 由 `tools/gen_cstdapi.py` 从 cstdapi 生成并被编译器内嵌；Linux 候选 `libc.so.6`/`libm.so.6`，Windows 候选 `ucrtbase.dll`/`msvcrt.dll`/`ntdll.dll`，包含 `_snprintf` 等别名。
- **Windows API**：`compiler-zig/src/data/winmd.generated.json.gz` 由 `tools/gen_winmd.py` 从 winmd 生成；name → DLL/callconv/min_os/arch_mask，运行期按 DLL 自动加载。
- `--no-auto-link` 关闭生成；未命中的自定义符号继续使用 `--lib`/旧 fallback。

## 3. CIVM 模块（v1）

### 3.1 头部

```
offset size field
0      4    magic = "CIVM"
4      1    version = 1
5      1    arch = 1          # VM 字节码架构，不是宿主 CPU
6      2    func_count (u16)
8      2    reserved = 0
```

### 3.2 函数记录（重复 `func_count` 次）

```
size  field
1     name_len (u8)
N     name bytes (UTF-8)
2     param_count (u16)
2     local_count (u16)
4     code_len (u32)
M     code bytes
```

- `param_count` 是函数参数个数；参数占用函数局部槽的**前 `param_count` 个**。
- `local_count` 包含参数槽和后续 alloca/SSA 槽；必须 `>= param_count`。
- 函数名有效上限为运行时的 `MAX_NAME = 128` 字节；函数数上限 `MAX_FUNCS = 512`。
- code 是字节流，跳转目标是**当前函数 code 内的绝对字节偏移**。
- 入口默认是 `main`，运行时可指定其他入口。

### 3.3 槽、栈与返回值

- 每个槽/栈项是 8 字节 `Value`，按 `i64` 或 `u64` 解释。
- 函数帧：调用者先压入 `param_count` 个参数值；`OP_CALL` 以
  `callee_base = sp - param_count` 建立被调帧，清零 `callee_base+param_count`
  到 `callee_base+local_count-1`。
- `OP_RET` 弹出一个值并返回给调用者；入口/Callback 的 `RET` 直接结束执行。
- 运行时槽栈上限 `MAX_STACK = 8192`，帧上限 `MAX_FRAMES = 512`。
- 函数返回后，`OP_ALLOCA` 在 `mem_mark` 之后的线性内存会回收；调用者分配的内存保留。

### 3.4 线性内存与 globals

VM 默认有 1 MiB 线性内存（`mem`，可由 `ci_vm_config.memory_size` 配置，上限 16 MiB），`mem_top` 是 bump pointer：

- `OP_ADDR_CONST offset` 压入 `&mem[offset]` 的**宿主地址**（不是文件偏移）。
- `OP_SET_MEM_TOP size` 将 `mem_top` 设为 size。
- `OP_ALLOCA size` 在 8 字节对齐的 `mem_top` 分配并清零，压入宿主地址。
- `OP_ALLOCA_DYN` 从栈弹 size，做同样的动态分配（VLA）。
- 全局数据没有独立 section；编译器在 `main` 开头生成：
  1. `SET_MEM_TOP <global_data_size>`
  2. 对每个 8 字节 chunk 生成 `LOAD_CONST chunk; ADDR_CONST off; STORE_MEM size`
  3. 对 global 指针/函数指针重定位生成 `ADDR_CONST/FUNC_ADDR; ADDR_CONST field; STORE_MEM ptr_size`
- 因此 `.cib` 中的全局地址是**运行期 VM 内存地址**，不是可重定位文件地址；同一包应在兼容的运行时进程中执行。

## 4. Opcode

栈效果按“先压入的值在下面”描述，例如 `a, b -> result` 表示先压 `a`、再压 `b`，opcode 弹 `b` 再弹 `a`。

| code | mnemonic | 操作数 | 栈效果/说明 |
| --- | --- | --- | --- |
| 0x01 | `RET` | — | `a ->`；返回值 a |
| 0x02 | `RET_VOID` | — | 返回 0 |
| 0x10 | `LOAD_CONST_I64` | i64 (8B) | 压入常量 |
| 0x11 | `ADD` | — | `a,b -> a+b` |
| 0x12 | `SUB` | — | `a,b -> a-b` |
| 0x13 | `MUL` | — | `a,b -> a*b` |
| 0x14 | `DUP` | — | `a -> a,a` |
| 0x15 | `POP` | — | `a ->` |
| 0x16 | `SWAP` | — | `a,b -> b,a` |
| 0x17 | `XOR` | — | `a,b -> a^b` |
| 0x18 | `DIV_S` | — | 有符号整除 |
| 0x19 | `DIV_U` | — | 无符号整除 |
| 0x1A | `REM_S` | — | 有符号取余 |
| 0x1B | `REM_U` | — | 无符号取余 |
| 0x1C | `AND` | — | `a,b -> a&b` |
| 0x1D | `OR` | — | `a,b -> a|b` |
| 0x1E | `SHL` | — | `a,b -> a<<b` |
| 0x1F | `SHR_S` | — | 算术右移 |
| 0x20 | `LOAD_LOCAL` | u16 | 压入局部槽 |
| 0x21 | `STORE_LOCAL` | u16 | 弹出并写局部槽 |
| 0x24 | `SHR_U` | — | 逻辑右移 |
| 0x25 | `FPTOSI` | — | f64 bits -> i64 |
| 0x26 | `SITOFP` | — | i64 -> f64 bits |
| 0x27 | `FADD` | — | f64 |
| 0x28 | `FSUB` | — | f64 |
| 0x29 | `FMUL` | — | f64 |
| 0x2A | `FDIV` | — | f64 |
| 0x2B | `FCMP` | pred u8 | `a,b -> 0/1`，f64 谓词 |
| 0x2C | `FADD32` | — | f32 |
| 0x2D | `FSUB32` | — | f32 |
| 0x2E | `FMUL32` | — | f32 |
| 0x2F | `FDIV32` | — | f32 |
| 0x30 | `JMP` | u32 target | 绝对跳到函数 code 内 target |
| 0x31 | `JZ` | u32 target | 弹条件；为 0 跳转 |
| 0x32 | `JNZ` | u32 target | 弹条件；非 0 跳转 |
| 0x33 | `CMP_EQ` | — | `a,b -> 0/1` |
| 0x34 | `CMP_LT` | — | 有符号 `<` |
| 0x35 | `CMP_LT_U` | — | 无符号 `<` |
| 0x38 | `FCMP32` | pred u8 | f32 比较 |
| 0x39 | `FPEXT` | — | f32 -> f64 bits |
| 0x3A | `FPTRUNC` | — | f64 -> f32 bits |
| 0x3B | `FPTOSI32` | — | f32 -> i64 |
| 0x3C | `SITOFP32` | — | i64 -> f32 bits |
| 0x40 | `CALL` | u16 func | 调用内部函数 |
| 0x41 | `FUNC_ADDR` | u16 func | 压入内部函数标签 `func+1`（0 表示 null） |
| 0x42 | `CALL_INDIRECT` | — | 弹函数标签，调用对应内部函数 |
| 0x60 | `ALLOCA` | u16 size | 线性内存分配，压地址 |
| 0x61 | `LOAD_MEM` | u8 size | `addr -> value`；size 1..8，<8 时符号扩展 |
| 0x62 | `STORE_MEM` | u8 size | `value,addr ->`；写 size 1..8 低字节 |
| 0x63 | `MEMCPY` | — | `dst,src,len ->`；重叠地址按 memmove 方向复制 |
| 0x64 | `MEMSET` | — | `dst,value,len ->` |
| 0x65 | `ADDR_CONST` | u32 offset | 压 `&mem[offset]` 宿主地址 |
| 0x66 | `SET_MEM_TOP` | u32 size | 设置 `mem_top` |
| 0x70 | `CALL_NATIVE` | u16 plan | 按计划调用原生函数 |
| 0x71 | `CALL_VARARG` | u16 plan | 按计划调用 varargs 原生函数 |
| 0x72 | `CREATE_CALLBACK` | u16 slot,u16 func,u16 plan | 注册静态 callback slot，压 trampoline 地址 |
| 0x73 | `F80_CONST` | 10 bytes | x87 80-bit little-endian；压 f80 对象地址 |
| 0x74-0x77 | `F80_ADD/SUB/MUL/DIV` | — | `a,b -> result`（指针） |
| 0x78 | `F80_CMP` | pred u8 | f80 比较 |
| 0x79 | `F80_FROM_F64` | — | f64 bits -> f80 指针 |
| 0x7A | `F80_TO_F64` | — | f80 指针 -> f64 bits |
| 0x7B | `F80_FROM_I64` | — | i64 -> f80 指针 |
| 0x7C | `F80_TO_I64` | — | f80 指针 -> i64 |
| 0x7D | `F80_FROM_F32` | — | f32 bits -> f80 指针 |
| 0x7E | `F80_TO_F32` | — | f80 指针 -> f32 bits |
| 0x7F | `F80_NEG` | — | f80 取负 |
| 0x80 | `F128_CONST` | 16 bytes | IEEE 128-bit little-endian；压 f128 对象地址 |
| 0x81-0x84 | `F128_ADD/SUB/MUL/DIV` | — | f128 指针运算 |
| 0x85 | `F128_CMP` | pred u8 | f128 比较 |
| 0x86 | `F128_NEG` | — | f128 取负 |
| 0x87-0x8C | `F128_FROM_F64/TO_F64/FROM_I64/TO_I64/FROM_F32/TO_F32` | — | f128 转换 |
| 0x8D | `ALLOCA_DYN` | — | 弹 size，动态分配 VLA |
| 0x8E | `FPTOUI` | — | f64 -> u64 bits |
| 0x8F | `UITOFP` | — | u64 bits -> f64 |
| 0x90 | `FPTOUI32` | — | f32 -> u64 bits |
| 0x91 | `UITOFP32` | — | u64 bits -> f32 |
| 0x92-0x95 | `F80_TO_U64/FROM_U64/F128_TO_U64/FROM_U64` | — | long double 无符号转换 |
| 0x96 | `ADDR_EXTERN` | u16 import | 压入 CIPI data 符号地址 |
| 0x97 | `SETJMP` | u16 slot | 保存 VM 执行上下文，结果写 slot |
| 0x98 | `LONGJMP` | — | 恢复对应 jmp_buf 的上下文 |
| 0x99 | `CALL_VARIADIC` | u16 func,u16 total | 调用内部可变参数函数，保留额外参数 |
| 0x9A | `VA_START` | — | 按目标 ABI 初始化 va_list，溢出参数放到 VM 内存 |
| 0x9B | `VA_COPY` | — | 复制目标 ABI 的 va_list |
| 0x9C | `CALL_INDIRECT_NATIVE` | u16 plan | 间接调用内部函数或原生 FFI 地址 |
| 0x9D | `STACKSAVE` | — | 压入当前 `mem_top` |
| 0x9E | `STACKRESTORE` | — | 恢复 `mem_top` |
| 0x9F | `ALLOCA_ALIGNED` | u16 size,u8 align | 对齐的静态 alloca |
| 0xA0 | `ALLOCA_DYN_ALIGN` | u8 align | 对齐的动态 alloca（size 在栈顶） |
| 0xA1 | `CALL_VARIADIC_TYPED` | u16 func,u16 total,per-extra code/size | 内部 varargs 调用，携带 overflow 布局描述 |
| 0xA2 | `FPCLASS` | — (u8 width) | LLVM is.fpclass 分类并压入 i1 |

### 4.1 浮点谓词

`FCMP`/`FCMP32`/`F80_CMP`/`F128_CMP` 的 pred 字节：

| value | 谓词 |
| --- | --- |
| 0 | `oeq`（有序等于） |
| 1 | `one`（有序不等） |
| 2 | `olt` |
| 3 | `ole` |
| 4 | `ogt` |
| 5 | `oge` |
| 6 | `ord` |
| 7 | `uno` |

### 4.2 f80/f128 值表示

f80/f128 **不是** 8 字节栈值本身：

- `*_CONST` 在 VM 线性内存分配一个 16B 对象，并把**对象地址**压栈。
- 算术/比较 opcode 读取这些对象地址，结果再分配一个新对象并压地址。
- `store/load` 对 f80/f128 使用 `MEMCPY`/指针别名语义；全局/内存布局由 C 类型大小决定。
- FFI 返回 `st0`/多寄存器聚合时，`invokeFfi` 会把结果复制到运行时返回缓冲区并压入地址。

## 5. CIPL 计划表

### 5.1 头部

```
offset size field
0      4    magic = "CIPL"
4      1    version（2 或 3；编译器当前写 3）
5      1    abi_id
6      2    plan_count (u16)
8      2    reserved = 0
```

`version` 兼容：

- v2：每计划没有 `conv` 字节；
- v3：每计划包含 `conv` 字节；当前编译器写 v3，loader 同时接受 v2/v3。

### 5.2 计划记录（重复 `plan_count` 次）

```
size  field
1     name_len
N     name bytes（ASCII/UTF-8，运行时有效上限 32）
2     args_count
2     ret_count
2     stack_size
1     sret（0/1）
1     sse_count
1     conv（仅 v3；0=cdecl，1=stdcall；其他 ABI 忽略）
2     ret_size
```

随后 `args_count` 个参数记录：

```
1     loc_count
2     size
2     alignment
1     is_struct（0/1）
1     reserved
...   loc_count × Loc
```

最后 `ret_count` 个返回 `Loc`。

`Loc`：

```
1     kind
2     index
2     size
2     offset
```

`kind` 取值：

| byte | kind | 含义 |
| --- | --- | --- |
| 0 | `gpr` | 整数/指针参数寄存器槽 |
| 1 | `xmm` | SSE/vector 参数槽（AArch64 也用于 vec） |
| 2 | `stack` | 栈参数槽 |
| 3 | `sret` | 隐藏 sret 指针槽 |
| 4 | `rax` | 整数返回寄存器 |
| 5 | `rdx` | 第二整数返回寄存器 |
| 6 | `xmm0` | 第一 SSE/vector 返回槽 |
| 7 | `xmm1` | 第二 SSE/vector 返回槽 |
| 8 | `st0` | x87 ST0（long double） |
| 9 | `xmm2` | 第三 HFA 返回槽 |
| 10 | `xmm3` | 第四 HFA 返回槽 |

### 5.3 字段语义

- `name`：外部符号名。callback 计划的名称是 `callback:<vm-function>`，没有原生符号。
- `args_count`：实际传入的参数个数；上限 64。
- `loc_count`：一个参数可拆成多个位置（HFA 的 xmm0/xmm1…）；上限 8。
- `size`：参数的字节宽度。
- `offset`：
  - 参数：在 **marshal arg block** 中的偏移；
  - `stack` loc：`index` 是栈参数缓冲区内的字节偏移；
  - 返回 loc：在返回缓冲区中的偏移。
- `is_struct=1`：参数的 VM 值是“指向结构体字节的指针”；运行时从该地址拷贝 `size` 字节到 arg block（byval/HFA/大结构体）。
- `sret=1`：隐藏返回指针；`sret` loc 指示隐藏指针槽。
- `sse_count`：SysV `%al` / Win64 varargs 的向量计数；其他 ABI 通常为 0。
- `conv`：Win32 调用约定；0=cdecl，1=stdcall；其他 ABI 忽略。
- `ret_size`：sret/聚合返回缓冲区的字节数。
- `ret_count > 0`：普通返回 loc；多 loc、`st0` 或单 loc `size > 8` 时，运行时会把返回块复制到 `ret_buf` 并压入其地址（供 `extractvalue`/聚合 store）。
- `stack_size`：计划需要的栈参数字节数；运行时校验不超过 4096。

### 5.4 ABI id 与 LocKind 的对应

| id | ABI | frame/engine |
| --- | --- | --- |
| 1 | SysV x86-64 | `call_x86_64_sysv.S` |
| 2 | Win64 x86-64 | `call_x86_64_win64.S` |
| 3 | Win32 x86 | `call_x86_win32.S` |
| 4 | AArch64 AAPCS64 | `call_arm64_aapcs.S` |

计划表只描述位置，不描述实际寄存器编号映射；具体 `gpr[0]`/`xmm[0]` 由目标 ABI 的 `platform.zig` frame 和固定汇编引擎映射。计划中的 `index` 是 ABI 约定的槽位号，不是宿主绝对寄存器号。

## 6. 完整示例：`hello.cib`

运行 `./build/cinterp-cc compile examples/hello.c -o build/hello.cib --no-auto-link` 后（CIPKG v2）。下表的字段布局不变，但下面的 CIVM 指令字节是旧版示例；当前 `cinterp-cc` 的 `hello.c` 包为 189B（module 83B、plan 10B、meta 61B、import 10B），具体指令以 `xxd` 输出为准：

```
43 49 50 4b 47        CIPKG
02                    version 2
03                    flags = has_target | has_imports
19 00                 header_size = 25
35 00 00 00           module_len = 53
0a 00 00 00           plan_len = 10
3d 00 00 00           meta_len = 61
0a 00 00 00           import_len = 10

43 49 56 4d           CIVM 模块（内容与 v1 相同）
01                    version 1
01                    arch 1
01 00                 func_count = 1
00 00                 reserved
04 6d 61 69 6e         name_len=4, "main"
00 00                 param_count = 0
01 00                 local_count = 1
1e 00 00 00           code_len = 30
60 04 00              ALLOCA 4
21 00 00              STORE_LOCAL 0
10 00 00 00 00 00 00 00 00   LOAD_CONST_I64 0
20 00 00              LOAD_LOCAL 0
62 04                 STORE_MEM 4
10 2a 00 00 00 00 00 00 00   LOAD_CONST_I64 42
01                    RET

43 49 50 4c           CIPL
03                    version 3
01                    abi_id 1 (SysV)
00 00                 plan_count = 0
00 00                 reserved

43 49 50 4d           CIPM
01                    version 1
1d 00                 header_size = 29
01                    arch = x86_64
01                    os = linux
01                    abi = sysv
40                    ptr_bits = 64
01                    endian = little
00                    flags
3d 00 00 00 00 00 00 00  features = f80|callback|varargs|auto-link|stdcall
01 00                 min_runtime = 1
13 00                 triple_len = 19
00 00                 link_db_len = 0
0d 00                 producer_len = 13
"x86_64-pc-linux-gnu"
"cinterp 0.1.0"

43 49 50 49           CIPI
01                    version 1
00                    flags
00 00                 entry_count = 0
00 00                 reserved
```

该包没有外部调用，所以 CIPI 只有 10 字节头。带自动链接的包会在 CIPI 中追加 provider 记录；可用 `--dump-imports` 查看，例如：

```
>>> cinterp-run --dump-target --dump-imports --load-only build/ffi_printf.cib
target: x86_64-pc-linux-gnu arch=1 os=1 abi=1 ptr=64 endian=1 features=0x3d link_db=cstdapi@...
import[plan 0] printf: libc.so.6:printf libm.so.6:printf
```

## 7. 检查与验证

```bash
# 查看十六进制
xxd -g1 build/hello.cib

# 查看编译器生成函数/计划/import 摘要
./build/cinterp-cc compile examples/ffi_printf.c -o build/printf.cib --dump --dump-imports

# 只加载/校验，不执行；同时查看目标/import 元数据
./runtime/zig-out/bin/cinterp-run --dump-target --dump-imports --load-only build/printf.cib

# 指定入口
./runtime/zig-out/bin/cinterp-run build/hello.cib main
```

运行时加载失败会返回错误名（`BadPackage`、`BadPackageMagic`、`BadPackageVersion`、`BadPackageHeader`、`TargetMismatch`、`UnsupportedFeature`、`RuntimeTooOld`、`BadAbi`、`BadImportPlan`、`BadImportProvider`、`ImportArchMismatch`、`ImportUnavailable`、`Truncated`、`TrailingBytes`、`BadPlan` 等），CLI 输出 `load failed` / `run failed`。

### 7.1 C ABI 错误码

`ci_vm_*` 返回 `CI_OK`（0）或下列稳定负值；`ci_vm_last_error_code` 给出同一类别，`ci_vm_last_error` 给出具体错误名。

| 值 | 名称 | 覆盖的主要错误名 |
| ---: | --- | --- |
| -1 | `CI_ERROR` | `errorCode` 未归类的内部错误 |
| -2 | `CI_E_INVALID_ARGUMENT` | `InvalidArgument`、`TooManyArgs` |
| -3 | `CI_E_OUT_OF_MEMORY` | `OutOfMemory` |
| -4 | `CI_E_BAD_PACKAGE` | `BadPackage*`、`BadMagic`、`BadVersion`、`BadArch`、`BadModule`、`BadLocals`、`TooManyFunctions`、`NameTooLong`、`ModuleTooLarge`、`Truncated`、`TrailingBytes` |
| -5 | `CI_E_TARGET` | `TargetMismatch`、`UnsupportedFeature`、`RuntimeTooOld`、`UnsupportedOs`（非 Linux/Windows 运行时）、`UnsupportedLibc`（musl 运行时） |
| -6 | `CI_E_PLANS` | `NoPlans`、`BadAbi`、`BadPlan`、`BadImportPlan`、`BadImportProvider`、`ImportArchMismatch`、`ImportUnavailable` |
| -7 | `CI_E_LINK` | `SymbolNotFound`、`LibraryNotFound`、`SymbolTooLong`、`PathTooLong`、`TooManyLibraries` |
| -8 | `CI_E_ENTRY` | `EntryNotFound` |
| -9 | `CI_E_RESOURCE` | `StackOverflow`、`FrameOverflow`、`ReturnTooLarge` |
| -10 | `CI_E_RUNTIME` | `BadAddress`、`BadOpcode`、`BadFunction`、`BadArgCount`、`BadJump`、`BadCallbackSlot`、`UnsupportedCallback`、`TooManyCallbacks`、`DivisionByZero`、`BadLocal`、`TruncatedCode`、`BadMemorySize`、`NullStruct` |
| -11 | `CI_E_DESTROYED` | `VmDestroyed`（callback 执行期间 VM 被销毁） |

## 8. 限制与兼容性

- `CIVM` 当前 v1；`CIPKG` 当前 v2（接受 v1）；`CIPL` 当前 v3（接受 v2）；`CIPM`/`CIPI` 当前 v1。
- `CIVM` 函数数上限 512、函数名有效上限 128、模块上限 2097152 字节；槽栈 8192、帧 512、线性内存默认 1 MiB（可配置，上限 16 MiB，显式 32 字节对齐）。
- `CIPL` 计划上限 1024、每计划参数 64、每参数 loc 8、名称有效上限 128；FFI arg/stack/ret 缓冲区各 4096 字节。
- CIPM 目标必须匹配运行时；v1 包没有目标 triple，只能依赖 CIPL ABI 和调用方正确选择运行时。macOS/未知 OS 与 musl 运行时在 load 阶段显式返回 `UnsupportedOs`/`UnsupportedLibc`，不会回退到 Linux glibc。
- CIPI 上限 512 entry、每 entry 8 provider、名称/符号 64 字节、版本 32 字节；自动 provider 只允许库名，不允许 CIB 携带任意路径。
- 不包含校验和/签名；不可信 `.cib` 应在 OS 沙箱中运行。运行时不提供进程内沙箱或 Safe 模式。
- 自动链接覆盖函数符号和基础 external data（`stdout`/`t_status` 等，`CIPI.kind=data` + `ADDR_EXTERN`）；向量、复杂聚合全局初始化仍不在范围内。`CIPKG` 本身不携带 `.so`/`.dll` 二进制。
