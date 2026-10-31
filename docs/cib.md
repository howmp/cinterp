# `.cib` 文件结构

`.cib` 是 `cinterp compile` 生成的**发布包**，外层格式为 `CIPKG`，内部由：

1. `CIVM`：字节码模块（函数表 + 每个函数的 code）；
2. `CIPL`：FFI/callback 计划表（每个外部符号的参数/返回位置）。

运行时按“包 → 模块 → 函数 → 计划 → 固定汇编引擎”的顺序工作。本文描述的是**当前实现**的二进制格式；代码是最终事实来源：

- `compiler/src/cinterp/codegen/binary_writer.py`：`CIPKG`
- `compiler/src/cinterp/llvm_ir/lower.py`：CIVM、opcode、globals 初始化
- `compiler/src/cinterp/ffi/plan.py`：CIPL、`Loc`/`ArgPlan`/`CallPlan`
- `runtime/src/vm.zig`：CIVM 解析、opcode 执行、C ABI
- `runtime/src/ffi/plan_loader.zig`：CIPL 解析
- `runtime/src/ffi/platform.zig`：ABI/frame/marshal 选择

## 1. 通用约定

- 所有多字节整数/浮点位模式均为**小端**。
- 没有对齐 padding、checksum、签名或压缩。
- `CIVM` 是虚拟机字节码，不是宿主 CPU 机器码；`CIPKG`/CIPL 的 ABI id 指示计划对应的宿主 ABI。
- 计划表与运行时目标 ABI 必须一致；否则 `loadPlans` 返回 `BadAbi`。
- 所有二进制长度按实际字节数写入，读取器会拒绝截断、尾随字节和越界计数。

## 2. CIPKG 外层

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

约束：

- `module_len`、`plan_len` 必须与剩余字节精确匹配；不允许 padding。
- 运行时模块上限 `MAX_MODULE = 262144` 字节。
- CLI 读取包文件上限 16 MiB（`cinterp-run`），加载器还会按模块/计划自身限制检查。
- 计划表即使为空也写入 10 字节 CIPL 头。

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
- 函数名有效上限为运行时的 `MAX_NAME = 32` 字节；函数数上限 `MAX_FUNCS = 8`。
- code 是字节流，跳转目标是**当前函数 code 内的绝对字节偏移**。
- 入口默认是 `main`，运行时可指定其他入口。

### 3.3 槽、栈与返回值

- 每个槽/栈项是 8 字节 `Value`，按 `i64` 或 `u64` 解释。
- 函数帧：调用者先压入 `param_count` 个参数值；`OP_CALL` 以
  `callee_base = sp - param_count` 建立被调帧，清零 `callee_base+param_count`
  到 `callee_base+local_count-1`。
- `OP_RET` 弹出一个值并返回给调用者；入口/Callback 的 `RET` 直接结束执行。
- 运行时槽栈上限 `MAX_STACK = 1024`，帧上限 `MAX_FRAMES = 64`。
- 函数返回后，`OP_ALLOCA` 在 `mem_mark` 之后的线性内存会回收；调用者分配的内存保留。

### 3.4 线性内存与 globals

VM 有 1 MiB 线性内存（`mem`），`mem_top` 是 bump pointer：

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
- `args_count`：实际传入的参数个数；上限 16。
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

运行 `cinterp compile examples/hello.c -o build/hello.cib` 后（78 字节）：

```
43 49 50 4b 47        CIPKG
01                    version 1
00                    reserved
35 00 00 00           module_len = 53
0a 00 00 00           plan_len = 10

43 49 56 4d           CIVM
01                    version 1
01                    arch 1
01 00                 func_count = 1
00 00                 reserved

04                    name_len = 4
6d 61 69 6e           "main"
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
```

该包没有外部调用，所以 CIPL 只包含 10 字节头。

## 7. 检查与验证

```bash
# 查看十六进制
xxd -g1 build/hello.cib

# 查看编译器生成函数/计划摘要
PYTHONPATH=compiler/src python3 -m cinterp compile examples/ffi_printf.c -o build/printf.cib --dump

# 只加载/校验，不执行
./runtime/zig-out/bin/cinterp-run --load-only build/printf.cib

# safe 模式：禁止原生调用/宿主越界内存操作（fuzz 用）
./runtime/zig-out/bin/cinterp-run --safe build/hello.cib

# 指定入口
./runtime/zig-out/bin/cinterp-run build/hello.cib main
```

运行时加载失败会返回错误名（`BadPackage`、`BadMagic`、`BadVersion`、`BadAbi`、`Truncated`、`TrailingBytes`、`BadPlan` 等），CLI 输出 `load failed` / `run failed`。

## 8. 限制与兼容性

- `CIVM` 当前 v1，`CIPKG` 当前 v1，`CIPL` 当前 v3（接受 v2）。
- `CIVM` 函数数上限 8、函数名有效上限 32、模块上限 262144 字节；槽栈 1024、帧 64、线性内存 1 MiB。
- `CIPL` 计划上限 256、每计划参数 16、每参数 loc 8、名称有效上限 32；FFI arg/stack/ret 缓冲区各 4096 字节。
- 没有目标 triple 字段；计划表只有 ABI id，应用必须用匹配目标构建的运行时加载。
- 不包含校验和/签名；不可信 `.cib` 应在 OS 沙箱中运行。`--safe` 只用于 fuzz，不允许原生调用和越界 VM 内存访问。
- 原生指针/外部数据符号仍依赖宿主运行时；`CIPKG` 本身不携带 `.so`/`.dll` 依赖。
