---
name: c-interpreter-implementation
overview: C 解释器实施计划：x86-64 SysV 固定汇编引擎与 CallPlan 生成器已验证；下一步计划序列化、VM 核心/FFI 集成、callback、Win64/Win32/ARM64 和 C11 覆盖。架构与关键决策见 dev.md。
---

# C 解释器实施计划

> 架构、ABI 设计、调用约定和技术约束见 [dev.md](./dev.md)。

## 1. 当前状态

已完成：

- **v1 实现（SysV x64/Win64/Win32/ARM64）**：`compiler/`（C→CIVM、CIPL FFI 计划、CIPKG、`--target`）+ `runtime/`（Zig VM、线性内存、平台 ABI 选择、C ABI、`--lib`、Windows/Unix loader）+ `examples/`；`make test` 通过（runtime 3、compiler 15、端到端 15），`scripts/test_cross.sh` 33/33（Win64/Win32/ARM64 各 11）。含 MEMORY/register/mixed struct FFI、qsort callback（SysV）、float32/double 算术、bitfield。
- **x86-64 SysV 固定汇编引擎**：`spike/asm_abi_call` 5/5，`ReleaseSmall` 8.7K。
- **前端 CallPlan 生成器（x86-64 SysV 原型）**：`spike/callplan_gen` 从 clang LLVM IR 生成 15 个计划，4/4，`ReleaseSmall` 8.7K。
- **计划二进制序列化 + loader**：`spike/callplan_gen` 的 `plans.bin` 995 字节/15 计划；Zig loader round-trip、名称查找、解码后调用、错误路径全部通过；总计 6/6。
- **最小 VM 核心**：`spike/vm_core` 6/6；覆盖 `return 42`、算术、局部变量/循环、内部调用、C ABI、loader 错误；`ReleaseSmall` 17K。
- **VM FFI 集成**：`spike/vm_ffi_integration` 2/2；VM 通过 `CALL_NATIVE`/`CALL_VARARG`/`CALL_INDIRECT` 调用标量、结构体、`sret`、varargs 和 `dlopen`/`dlsym`；`ReleaseSmall` 37K。
- **Callback trampoline**：`spike/callback_trampoline` 3/3；256 槽静态 trampoline + 反向计划，qsort/结构体参数/结构体返回 callback 均执行真实 VM 函数；`ReleaseSmall` 20K。
- **LLVM IR 降级**：`spike/llvm_ir_lowering` 12/12；标量控制流、整数语义、线性内存上的数组/结构体/指针、union、memcpy/memset、globals/字符串；`sample1..12` 全部通过；`ReleaseSmall` 21K。
- **Win64 ABI**：`spike/win64_abi` 在 Windows x64 测试机 6/6；GPR/栈、混合 int/double、小/大结构体、sret、Win64 varargs；PE 34,304 字节。
- **Win32 ABI**：`spike/win32_abi` Zig 单进程连续 6/6 + 每进程 6/6，均 exit 0；C harness 6/6；根因是 harness 的 `argsFree`，已用 C shim + 保留 args 解决。
- **ARM64 AAPCS64**：`spike/arm64_aapcs` 在 qemu-aarch64 下 6/6；整数/混合/HFA/栈参数/sret；12K。
- **C11 内存/全局模型（S9 部分）**：线性内存 + ALLOCA/LOAD_MEM/STORE_MEM + GEP；数组/结构体/指针、union、memcpy/memset、globals/字符串通过（sample6..12）；剩余 bitfield（v1 排除）、float/`long double`、c-testsuite。
- **早期 `@call` ABI 参考 spike**：`spike/ffi_struct_call` 7/7、`spike/varargs_call` 5/5 + 矩阵 3/3；`@call` 矩阵方案已放弃，结果保留为 ABI 行为参考。
- **关键结论**：clang IR 已完成大部分结构体 ABI lowering（coerced/`byval`/`sret`），前端生成器只需处理 lowered 类型和 literal aggregate。

下一步：

- **编译器侧 struct/callback FFI**：MEMORY `byval`/`sret`、coerced S8、双 XMM D16、`{i64,double}` mixed、qsort callback 已集成。
- **多 ABI 计划生成/运行时选择**：Win64/Win32/ARM64 compiler plan builder + `ffi/platform.zig` + 交叉测试已完成。
- **C11 扩展**：`long double`、c-testsuite/chibicc 子集（float32/double 算术、bitfield 已完成）。
- **M11 加固/发布**：ABI 边界、体积、错误路径、CI/发布检查。

剩余：实现扩展项；无阻塞性 ABI 问题。

## 2. 实施约束（摘要）

- **FFI**：编译期生成 ABI 计划；运行时固定汇编引擎执行；不链接 libffi，不使用 `@call` 桩矩阵，不申请动态可执行内存；callback 用固定 256 槽静态 trampoline 池。
- **平台**：v1 Linux x64；ABI 顺序为 Windows x64 → Windows x86 → Linux ARM64。
- **编译器**：Python + clang LLVM IR，仅构建期使用；发布物是 Zig 运行时 + 字节码。
- **详细设计**：见 `dev.md` 的 FFI、运行时、调用约定和结构体 FFI 章节。

## 3. 里程碑

| ID | 里程碑 | 状态 | 依赖 | 退出标准 |
| --- | --- | --- | --- | --- |
| M0 | x86-64 SysV FFI 引擎 | 完成 | — | `spike/asm_abi_call` 5/5；8.7K |
| M1 | 前端 CallPlan 生成器 | 原型完成 | M0 | 15 个计划、4/4；序列化由 M2 完成 |
| M2 | 计划序列化 + runtime loader | 完成（spike） | M1 | `plans.bin` 995B/15 计划；6/6 |
| M3 | 最小 VM 核心 | 完成（spike） | — | 6/6；17K；`return 42`/算术/循环/内部调用/C ABI |
| M4 | LLVM IR → 字节码降级 | 完成（spike） | M3 | 12/12；21K；标量+内存+globals |
| M5 | VM FFI 集成 | 完成（spike） | M2/M3 | 2/2；37K；标量/结构体/sret/varargs/dlopen |
| M6 | Callback trampoline | 完成（spike） | M5 | 3/3；20K；qsort/结构体 callback；无动态代码 |
| M7 | C11 覆盖 | 部分完成 | M4/M5 | 12/12；数组/结构体/指针/union/globals；bitfield/float 待做 |
| M8 | Windows x64 | 完成（spike） | M5 | Windows 测试机 6/6；34K PE |
| M9 | Windows x86 | 完成（spike） | M5 | Zig 连续 6/6 + 每进程 6/6，exit 0 |
| M10 | Linux ARM64 | 完成（spike） | M5 | qemu 6/6；12K |
| M11 | 加固/发布 | 待开始 | 全部 | 体积/ABI 边界/文档/发布检查 |
| M12 | v1 实现（Linux x64） | 完成（核心） | 全部 | `make test` 通过；compiler+runtime+examples |

### M0：x86-64 SysV FFI 引擎（完成）

- `SysV64Frame` 固定布局 + `ci_abi_call_sysv64` 固定汇编。
- Zig marshaler 按 `CallPlan` 填 GPR/XMM/栈/sret；捕获 RAX/RDX/XMM0/XMM1。
- 覆盖标量、混合 GPR/XMM、结构体参数/返回、`byval`、`sret`、varargs `snprintf`。
- 产出：`spike/asm_abi_call/{main.zig, call_x86_64_sysv.S, helper.c, README.md}`。
- 退出：5/5，`ReleaseSmall` 8.7K，smoke `c_add3 -> 6`。

### M1：前端 CallPlan 生成器（原型完成）

- `gen_callplan.py`：clang → LLVM IR → lowered 类型/属性 → `CallPlan`。
- 处理标量、literal aggregate、`byval`、`sret`、varargs。
- 产出：`spike/callplan_gen/{gen_callplan.py, generated_plans.zig, plans.json, main.zig, README.md}`。
- 退出：15 个计划、4/4，`ReleaseSmall` 8.7K。
- 剩余：更多 boundary case、正式集成到 `compiler/src/cinterp/ffi/`。

### M2：计划序列化 + runtime loader（完成，spike）

- 二进制计划表：magic/version/ABI、命名计划、args/locs、ret_locs、stack/sret/sse。
- `serialize_plans.py` 编码，`plan_loader.zig` 解码/校验；计划按名称查找；截断/非法 magic/version/ABI 错误。
- 产出：`spike/callplan_gen/{serialize_plans.py, plans.bin, plan_loader.zig}`。
- 结果：`plans.bin` 995 字节/15 计划；6/6 测试；解码后的 `c_add3`/`c_take_ii`/`c_return_mem`/`snprintf` 通过汇编引擎执行。
- 退出：round-trip、名称查找、错误路径均通过；正式集成到 `compiler/`/`runtime/` 骨架待做。

### M3：最小 VM 核心（完成，spike）

- 二进制模块 `CIVM` v1：函数表、代码、8 字节栈槽、帧/调用/返回、opcode 循环。
- 导出 `ci_vm_create/destroy/load_module/run/last_error`。
- 结果：`spike/vm_core` 6/6；覆盖 `return 42`、算术、局部变量/循环、内部调用、C ABI、loader 错误；`ReleaseSmall` 17K。
- 产出：`spike/vm_core/{vm.zig, main.zig, README.md}`。
- 退出：VM 执行最小模块；C ABI 可用；为 S6/S7 提供执行基础。

### M4：LLVM IR → 字节码降级（完成，spike）

- 解析 `-O0` LLVM IR；SSA 值/alloca 地址映射到 local slot；alloca 使用 VM 线性内存。
- 支持标量/控制流、整数语义、数组/结构体/指针、GEP、union、memcpy/memset、globals/字符串。
- 结果：`spike/llvm_ir_lowering` 12/12；`sample1..12` 全部通过；`ReleaseSmall` 21K。
- 产出：`spike/llvm_ir_lowering/{compile_ir.py, vm.zig, sample1..12.c, *.ll, *.civm, main.zig, README.md}`。
- 退出：核心标量/内存 C 子集端到端降级并运行；bitfield/float/外部调用留给后续。

### M5：VM FFI 集成（完成，spike）

- `CALL_NATIVE`/`CALL_VARARG`/`CALL_INDIRECT`/`DLOPEN`/`DLSYM` 按计划索引查找 → marshaler → 固定汇编引擎。
- 结果：`spike/vm_ffi_integration` 2/2；覆盖标量 `c_add3`、coerced struct、byval struct、`sret`、varargs `snprintf`、`dlopen("libc.so.6")` + `dlsym` + `CALL_INDIRECT`；`ReleaseSmall` 37K。
- 产出：`spike/vm_ffi_integration/{vm.zig, main.zig, abi.zig, plan_loader.zig, plans.bin, README.md}`。
- 退出：VM 用生成的计划端到端调用原生函数；callback/frontend 后续。

### M6：Callback trampoline（完成，spike）

- 固定 256 槽静态 trampoline 池 + 公共入口；保存 GPR/XMM/栈参数。
- Zig `ci_callback_dispatch` 按反向计划读取参数、调用 `vm.runEntryWithArgs`，写回返回寄存器。
- 结果：`spike/callback_trampoline` 3/3；qsort（VM `cmp`）、结构体参数 callback、结构体返回 callback；`ReleaseSmall` 20K。
- 产出：`spike/callback_trampoline/{callbacks_x86_64_sysv.S, gen_callbacks.py, callbacks.zig, vm.zig, main.zig, README.md}`。
- 退出：qsort/结构体 callback 通过；无动态可执行内存；槽位/生命周期基础验证。
- 后续：Win32 `stdcall`/Win64/ARM64 callback、嵌套/多线程、CallbackPlan 自动生成。

### M7：C11 覆盖（部分完成）

- 标量/控制流：switch/goto、整除/取余、位运算/移位、有符号/无符号比较、trunc/zext/sext。
- 内存/全局：VM 线性内存 + `ALLOCA`/`LOAD_MEM`/`STORE_MEM` + GEP；数组、结构体、指针、union、memcpy/memset、globals/字符串。
- 结果：`sample1..12` 12/12；`ReleaseSmall` 21K。
- 剩余：bitfield（v1 排除）、float/`long double`、外部调用、c-testsuite 子集。
- 产出：`spike/llvm_ir_lowering`。

### M8：Windows x64（完成，spike）

- `call_x86_64_win64.S`：RCX/RDX/R8/R9 + XMM0-3、32 字节 shadow space、16 字节栈对齐、栈参数复制。
- 结果：`spike/win64_abi` 在 Windows x64 测试机 6/6；覆盖 `c_add5`（4 GPR + 栈）、`c_mix`（RCX/XMM1/R8/XMM3）、`c_take_small`（8 字节结构体）、`c_take_big`（24 字节按引用）、`c_return_big`（sret）、`snprintf`（varargs 浮点 GPR 副本 + AL）。
- 产出：`spike/win64_abi/{call_x86_64_win64.S, abi_win64.zig, main.zig, helper.c, README.md}`。
- 体积：ReleaseSmall PE 34,304 字节。
- 剩余：Win64 callback、异常/unwind、large-struct 拷贝语义、`__vectorcall`/COM。

### M9：Windows x86（完成，spike）

- `call_x86_win32.S`：栈参数、cdecl `add esp,N` / stdcall callee `ret N`、EAX:EDX、ST0、8 字节结构体、24 字节 sret。
- 结果：Zig 每进程 6/6 + 单进程连续 6/6，均 exit 0；C harness 6/6 且 exit 0。
- 根因：之前的崩溃在测试 harness 的 `argsFree`（Zig Windows-x86 分配器清理），不是引擎；C shim + 保留 args 后全部通过。
- 剩余：Win32 varargs、callback、WinAPI 名称修饰、`fastcall`/`thiscall`（v1 不需要）。

### M10：Linux ARM64（完成，spike）

- `call_arm64_aapcs.S`：x0–x7、v0–v7、x8 sret、16 字节栈、HFA。
- 结果：qemu-aarch64 下 6/6；整数/混合 int-double/10 参数栈/HFA 参数/HFA 返回/24 字节 sret。
- 体积：ReleaseSmall 12K（text 8,144）。
- 剩余：AAPCS64 varargs、栈上 HFA、大结构体按值、callback、`long double`。

### M11：加固/发布（待开始）

- ABI 边界（packed/未对齐/栈参数边界）、体积/性能、错误路径、文档。
- 跨平台构建/CI；ReleaseSmall；发布检查。

### M12：v1 实现（Linux x64，完成核心）

- `compiler/`：Python 包 + `cinterp compile`；LLVM IR 降级、线性内存、globals/字符串、CIPL FFI 计划、CIPKG 包。
- `runtime/`：Zig VM、线性内存、`ci_vm_*` C ABI、SysV 固定汇编 FFI 引擎、`dlsym`/`libc` 解析、CIPKG 加载。
- `examples/`：hello、arrays、structs、puts、printf、snprintf、malloc/free、MEMORY/register/mixed struct FFI、qsort callback、float32/double math/FFI、bitfields。
- `make test`：runtime 3 单测 + compiler 11 单测 + 15 个端到端用例通过；`ffi_structs=28`、`ffi_regstruct=102`、`ffi_mixedstruct=11`、`ffi_qsort=1`、`math=8`、`float_math=8`、`ffi_float=5`、`bitfields=12`。
- 后续：fuzz/外部 CI。

## 4. Spike 计划

### 4.1 Spike 总表

| ID | Spike | 状态 | 目标 | 结果/退出标准 |
| --- | --- | --- | --- | --- |
| S0 | `ffi_struct_call` | 完成（历史） | 验证 SysV 结构体 ABI（Zig `@call`） | 7/7；ABI 参考 |
| S1 | `varargs_call` | 完成（历史） | 验证 varargs `@call`/8 槽矩阵 | 5/5 + 3/3；63K；矩阵不采用 |
| S2 | `asm_abi_call` | 完成 | 固定 x86-64 SysV 汇编 + `CallPlan` | 5/5；8.7K |
| S3 | `callplan_gen` | 原型完成 | Python 从 clang IR 生成 `CallPlan` | 15 计划；4/4；8.7K |
| S4 | `plan_serialization` | 完成 | 计划二进制编码 + runtime loader | `plans.bin` 995B/15；6/6 |
| S5 | `vm_core` | 完成 | 最小 VM 核心 | 6/6；17K；`return 42`/循环/调用/C ABI |
| S6 | `llvm_ir_lowering` | 完成 | LLVM IR → 字节码 | 12/12；21K；标量+内存+globals |
| S7 | `vm_ffi_integration` | 完成 | VM 调用计划/引擎 | 2/2；37K；scalar/struct/sret/varargs/dlopen |
| S8 | `callback_trampoline` | 完成 | 静态 trampoline + 反向计划 | 3/3；20K；qsort/结构体 callback |
| S9 | `c11_semantics` | 部分完成 | 核心 C11 子集 | 12/12；数组/结构体/指针/union/globals；bitfield/float 待做 |
| S10 | `win64_abi` | 完成 | Windows x64 ABI | Windows 6/6；34K PE |
| S11 | `win32_abi` | 完成 | Windows x86 cdecl/stdcall | Zig 连续 6/6 + 每进程 6/6，exit 0 |
| S12 | `arm64_aapcs` | 完成 | Linux ARM64 AAPCS64 | qemu 6/6；12K |

### 4.2 已完成的 Spike

#### S0 `spike/ffi_struct_call`（历史参考）

- **目标**：在改用固定汇编前，用 Zig `@call` 验证 SysV 结构体按值参数/返回和 callback。
- **结果**：7/7 通过；覆盖 `S_I`、`S_II`、`S_SS`、`S_IS`、`S_SI`、`S_MEM`（含 MEMORY/sret）、混合寄存器类别、结构体 callback；smoke 8.0K。
- **结论**：ABI 行为参考；`@call` 已不用于运行时。详见 `spike/ffi_struct_call/README.md`。

#### S1 `spike/varargs_call`（历史参考）

- **目标**：验证 Zig 0.13 变长函数指针 + `@call`，以及 8 槽 mask 矩阵。
- **结果**：5/5 核心测试 + 3/3 矩阵测试；`%al`、混合 int/float、纯 float、纯 int、运行期 mask dispatch；256 桩矩阵 `ReleaseSmall` 63K。
- **结论**：varargs ABI 行为参考；256 桩矩阵不采用，改为计划驱动。详见 `spike/varargs_call/README.md`。

#### S2 `spike/asm_abi_call`（当前架构）

- **目标**：验证固定 x86-64 SysV 汇编引擎 + 手写 `CallPlan`。
- **结果**：5/5 通过；覆盖标量 GPR、混合 GPR/XMM、结构体按值参数/返回（含 MEMORY/`sret`）、varargs `snprintf`（`%al` + 混合参数）；`ReleaseSmall` 8.7K；smoke `c_add3 -> 6`。
- **产出**：`main.zig`、`call_x86_64_sysv.S`、`helper.c`、`README.md`。
- **结论**：固定汇编路线可行；作为 M0 基线。详见 `spike/asm_abi_call/README.md`。

#### S3 `spike/callplan_gen`（当前架构原型）

- **目标**：验证 Python 从 clang LLVM IR 生成 `CallPlan`，并驱动 S2 的引擎。
- **结果**：15 个计划；4/4 通过；覆盖标量、混合 GPR/XMM、结构体参数/返回、`byval`、`sret`、varargs `snprintf`；`ReleaseSmall` 8.7K。
- **关键发现**：clang IR 已完成大部分结构体 ABI lowering（coerced / `byval` / `sret`），生成器只需处理 lowered 类型和 literal aggregate。
- **产出**：`gen_callplan.py`、`generated_plans.zig`、`plans.json`、`main.zig`、`abi.zig`、`README.md`。
- **结论**：前端计划生成原型可行；二进制序列化已由 S4 完成。详见 `spike/callplan_gen/README.md`。

#### S4 `plan_serialization`（完成）

- **目标**：把 `CallPlan` 编码进二进制模块；Zig runtime 解码/校验；按名称/ID 查找。
- **结果**：
  - `serialize_plans.py` 生成 `plans.bin`：995 字节/15 计划，含 magic/version/ABI、名称、args/locs、ret_locs、stack/sret/sse。
  - `plan_loader.zig` 解码/校验、名称查找；解码后的 `c_add3`、`c_take_ii`、`c_return_mem`、`snprintf` 通过固定汇编引擎执行。
  - 总计 6/6 测试；截断/非法 magic/version/ABI 错误路径通过。
- **产出**：`spike/callplan_gen/{serialize_plans.py, plans.bin, plan_loader.zig}`。
- **结论**：计划二进制格式可行；正式集成到 `compiler/`/`runtime/` 骨架待后续。
- **风险**：后续 ABI 字段扩展（`cleanup_bytes`/`st0/st1`）需要 schema 版本兼容。

#### S5 `vm_core`（完成）

- **目标**：最小 VM 核心——二进制模块 loader、8 字节栈槽、帧/调用/返回、基础 opcode 循环、`ci_vm_*` C ABI。
- **结果**：
  - `CIVM` v1 模块格式；opcode：RET/RET_VOID/LOAD_CONST_I64/ADD/SUB/MUL/DUP/POP/SWAP/LOAD_LOCAL/STORE_LOCAL/JMP/JZ/JNZ/CMP_EQ/CMP_LT/CALL。
  - 6/6 测试：`return 42`、算术、局部变量/循环（1..10=55）、内部调用（20+22=42）、C ABI create/load/run/destroy、loader 错误。
  - `ReleaseSmall` 17K（text 14,301）。
- **产出**：`spike/vm_core/{vm.zig, main.zig, README.md}`。
- **结论**：VM 核心可行；为 S6/S7 提供执行基础。
- **风险**：完整 opcode/加载器/错误状态后续补齐；先不做 FFI/callback。

#### S6 `llvm_ir_lowering`（完成）

- **目标**：解析 `-O0` LLVM IR，降级为 `CIVM` 字节码，在 VM 端到端运行。
- **结果**：
  - local-slot SSA lowering：每个 SSA 值/alloca 映射到 VM local slot，避免 phi/栈合并。
  - 支持标量 alloca/load/store、add/sub/mul、icmp eq/ne/slt/sle/sgt/sge、br/ret、内部调用。
  - 2/2 测试：`sample1=42`、`sample2`（循环 1..10 + `add(sum,0)`）=55。
  - `ReleaseSmall` 17K（text 14,377）。
- **产出**：`spike/llvm_ir_lowering/{compile_ir.py, vm.zig, sample1.c, sample2.c, sample1.ll, sample2.ll, sample1.civm, sample2.civm, main.zig, README.md}`。
- **结论**：标量前端降级可行；指针/数组/结构体/全局/字符串/memcpy/switch/float/外部调用留给 S9/S7。
- **风险**：`-O0` 以 alloca+load/store 为前提；-O1 需要 phi 处理。

#### S7 `vm_ffi_integration`（完成）

- **目标**：把 VM 的 `CALL_NATIVE`/`CALL_VARARG`/`CALL_INDIRECT`/`DLOPEN`/`DLSYM` 接到 S4 计划 + S2 引擎。
- **结果**：
  - 2/2 测试：标量 `c_add3=6`、coerced struct `c_take_ii=4321`、byval struct `c_take_mem=321`、`sret` `c_return_mem={1,2,3}`、varargs `snprintf="1 2.5 3"`。
  - `dlopen("libc.so.6")` + `dlsym("snprintf")` + `CALL_INDIRECT` 同样通过。
  - `ReleaseSmall` 37K（text 33,836）。
- **产出**：`spike/vm_ffi_integration/{vm.zig, main.zig, abi.zig, plan_loader.zig, plans.bin, helper.c, call_x86_64_sysv.S, README.md}`。
- **结论**：VM 端到端 FFI 可行；callback 复用同一 marshaler/计划机制。
- **风险**：VM 栈 ↔ ABIFrame 字节布局、`ret_size`/sret 的边界后续补齐。

#### S8 `callback_trampoline`（完成）

- **目标**：固定 256 槽静态 trampoline + 反向计划；`qsort`/结构体 callback；可重入。
- **结果**：
  - 3/3 测试：qsort（VM `cmp` 加载两个 int 指针）、结构体参数 callback（VM `cb_i`）、结构体返回 callback（VM `cb_ret`）。
  - 256 个静态 trampoline + `ci_cb_sysv_table`；公共入口保存 GPR/XMM/栈参数，调用 `ci_callback_dispatch`，写回返回寄存器。
  - `ReleaseSmall` 20K（text 14,521；data 2,536）。
- **产出**：`spike/callback_trampoline/{gen_callbacks.py, callbacks_x86_64_sysv.S, callbacks.zig, vm.zig, main.zig, helper.c, README.md}`。
- **结论**：静态 callback trampoline + VM 回调可行；无动态可执行内存。
- **风险/后续**：Win32 `stdcall`/Win64/ARM64 callback、嵌套/多线程、CallbackPlan 自动生成。

#### S10 `win64_abi`（完成）

- **目标**：Windows x64 的 `CallPlan` + `call_x86_64_win64.S`；shadow space、varargs 浮点 GPR 副本、结构体小/按引用/sret。
- **结果**：
  - Windows x64 测试机 6/6：`c_add5`（4 GPR + 栈）、`c_mix`（RCX/XMM1/R8/XMM3）、`c_take_small`（8 字节结构体）、`c_take_big`（24 字节按引用）、`c_return_big`（sret）、`snprintf`（varargs 浮点 GPR 副本 + AL）。
  - ReleaseSmall PE 34,304 字节。
- **产出**：`spike/win64_abi/{call_x86_64_win64.S, abi_win64.zig, main.zig, helper.c, README.md}`。
- **结论**：Win64 ABI 引擎可行；Windows 测试链路（Linux 交叉编译 → scp → SSH 运行）可用。
- **剩余**：Win64 callback、异常/unwind、large-struct 拷贝语义、`__vectorcall`/COM。

#### S11 `win32_abi`（完成）

- **目标**：Win32 cdecl/stdcall 计划 + `call_x86_win32.S`；栈参数、清理约定、EAX:EDX、ST0、结构体/sret。
- **结果**：
  - Zig 每进程 6/6 + 单进程连续 6/6（`win32_abi.exe 7`），全部 exit 0。
  - C harness（`harness.c`）在 Windows x64 WoW64 下 6/6 且 exit 0。
  - 覆盖 cdecl/stdcall 3 参数、int64 EAX:EDX、double ST0、8 字节结构体、24 字节 sret。
- **根因**：之前的崩溃在测试 harness 的 `argsFree`（Zig Windows-x86 分配器清理路径），不是引擎；C shim `c_call_engine` + 保留 args 后全部通过。
- **产出**：`spike/win32_abi/{call_x86_win32.S, main.zig, helper.c, harness.c, README.md}`。
- **剩余**：Win32 varargs、callback、WinAPI 名称修饰、`fastcall`/`thiscall`（v1 不需要）。

#### S12 `arm64_aapcs`（完成）

- **目标**：AAPCS64 计划 + `call_arm64_aapcs.S`；x0–x7/v0–v7、HFA、x8 sret、16 字节栈。
- **结果**：qemu-aarch64 下 6/6；整数、混合 int/double、10 参数栈、HFA 参数/返回、24 字节 sret；`ReleaseSmall` 12K（text 8,144）。
- **产出**：`spike/arm64_aapcs/{call_arm64_aapcs.S, abi_arm64.zig, main.zig, helper.c, README.md}`。
- **剩余**：AAPCS64 varargs、栈上 HFA、大结构体按值、callback、`long double`。

#### S9 `c11_semantics`（部分完成）

- **目标**：核心 C11 子集的前端降级/VM 语义覆盖，接入 c-testsuite/chibicc。
- **结果**：
  - 12/12：`sample1=42`、`sample2=55`、`sample3` switch=159、`sample4` 整数语义=301、`sample5` goto=15、`sample6` 数组+循环=10、`sample7` 结构体+指针=34、`sample8` 指针参数 swap=21、`sample9` union=4、`sample10` memcpy/memset=10、`sample11` global int=8、`sample12` 字符串=98。
  - 标量/控制流：`sdiv/udiv/srem/urem`、`and/or/xor`、`shl/lshr/ashr`、有符号/无符号 `icmp`、`trunc/zext/sext`、`switch`、`goto`。
  - 内存/全局：VM 线性内存 + `ALLOCA`/`LOAD_MEM`/`STORE_MEM` + GEP；数组、结构体、指针、union、memcpy/memset、globals/字符串。
  - `ReleaseSmall` 21K（text 16,905）。
- **产出**：`spike/llvm_ir_lowering/{compile_ir.py, vm.zig, sample1..12.c, *.ll, *.civm, main.zig, README.md}`。
- **剩余**：bitfield（v1 排除）、float/`long double`、外部调用、c-testsuite/chibicc 子集。

### 4.3 待执行的 Spike

无。计划内 spike 已全部执行；剩余项见“风险与阻塞”。

## 5. 下一步与待办

**P0（下一批）**

1. **S4 计划序列化 + loader（已完成）**：`plans.bin` 995B/15 计划；Zig loader 6/6。
2. **S5 最小 VM 核心（已完成）**：6/6；17K。
3. **S7 VM FFI 集成（已完成）**：2/2；37K。

**P1**

- **S8 Callback trampoline（已完成）**：3/3；20K。
- **S6 LLVM IR 降级（已完成）**：2/2；17K。

**P2（按确认的 ABI 顺序）**

- **S10 Windows x64（已完成）**：Windows 6/6；34K。
- **S11 Windows x86（已完成）**：Zig 连续 6/6 + 每进程 6/6，exit 0；C harness 6/6。
- **S12 Linux ARM64（已完成）**：qemu 6/6；12K。
- **S9 C11 覆盖（部分完成）**：12/12；数组/结构体/指针/union/globals/字符串已通过；bitfield/float/c-testsuite 待扩展。

**Checklist**

- [x] S0 `ffi_struct_call`
- [x] S1 `varargs_call`
- [x] S2 `asm_abi_call`
- [x] S3 `callplan_gen`
- [x] S4 `plan_serialization`
- [x] S5 `vm_core`
- [x] S6 `llvm_ir_lowering`
- [x] S7 `vm_ffi_integration`
- [x] S8 `callback_trampoline`
- [x] S9 `c11_semantics`（12/12；数组/结构体/指针/union/globals；bitfield/float 待做）
- [x] S10 `win64_abi`
- [x] S11 `win32_abi`（Zig 连续 6/6 + 每进程 6/6，exit 0）
- [x] S12 `arm64_aapcs`

**v1 实现 checklist**

- [x] compiler Python 包 + CLI（C→CIVM/CIPL/CIPKG）
- [x] runtime Zig VM + 线性内存 + SysV FFI + C ABI
- [x] examples + 集成测试（`make test`）
- [x] 编译器侧 MEMORY struct `byval`/`sret` FFI 计划
- [x] register-class S8（coerced i64）与 D16（双 XMM 聚合返回）
- [x] callback 静态 trampoline + 可重入 VM（qsort）
- [x] mixed-class register aggregate（`{i64,double}`）
- [x] Win64/Win32/ARM64 计划生成与运行时选择（`scripts/test_cross.sh` 33/33）
- [x] float32/double 算术/比较（fadd/fsub/fmul/fdiv、fcmp、fpext/fptrunc、sitofp/fptosi）
- [x] bitfield（clang shift/mask lowering）
- [x] long double（16B 存储、64-bit 精度、内部算术/转换；FFI/printf 未覆盖）
- [x] c-testsuite 子集（`make c-testsuite` 9/9；支持外部 `C_TESTSUITE_DIR`）
- [x] M11 基础加固：plan/package 边界校验、错误路径、CLI version/help
- [x] M11 体积检查：`make size`（runtime 40K、qsort.cib 460B）；README 沙箱说明
- [x] M11 本地发布检查：`make release-check`、package 截断 smoke
- [ ] fuzz / 外部 CI

## 6. 风险与阻塞

- **S11 已解决**：原崩溃在测试 harness 的 `argsFree`；C shim + 保留 args 后，Zig 每进程/单进程连续 6/6，exit 0。Win32 引擎/ABI 已验证。
- **S9 部分完成**：标量/控制流、线性内存数组/结构体/指针、union、memcpy/memset、globals/字符串已通过（12/12）；剩余 bitfield（v1 排除）、float/`long double`、外部调用、c-testsuite。
- **计划序列化 schema**：已升级为 v2（`ret_size`）；`plans.bin` 仍 995B/15 计划。
- **VM 核心与 FFI 集成耦合**：S5 先保持最小；S7 只接计划/引擎，不把 FFI 逻辑塞进 opcode 循环。
- **Callback 可重入/槽位生命周期**：S8 专门验证；v1 单线程。
- **工具链**：Zig 0.13 + `.S` 汇编/链接；Windows COFF 符号修饰；ARM64 交叉编译。
- 架构级风险与备选方案见 `dev.md` 第 16 节。

## 7. 执行支持

### SubAgent

- **code-explorer**
- Purpose: 在实现过程中探索参考实现和 ABI 细节：
  - chibicc / c-testsuite 的 C 测试用例和编译器结构
  - LLVM IR 指令语义和 clang 的 `-O0` 输出模式
  - System V AMD64、Microsoft x64/x86 调用约定、AArch64 AAPCS64
  - libffi / dyncall 的 ABI 分类和栈布局实现（仅作参考，不引入依赖）
- Expected outcome: 减少 ABI 计划/汇编引擎的试错，优先复用成熟测试集。

## 8. 变更记录

- **2026-10-30**：拆分文档：架构/关键决策移到 `dev.md`，本文件保留实施计划与 spike 清单。
- **2026-10-30**：FFI 架构从 `@call` 桩矩阵切换为“编译期 ABI 计划 + 固定汇编引擎”；`@call` spike 保留为 ABI 参考，256 桩矩阵不采用。
- **2026-10-30**：验证完成 S2（固定汇编引擎，5/5，8.7K）和 S3（前端计划生成器，15 计划/4/4，8.7K）。
- **2026-10-30**：完成 S4（计划二进制序列化 + Zig loader，`plans.bin` 995B/15 计划，6/6）。
- **2026-10-30**：完成 S5（最小 VM 核心，6/6，17K）。
- **2026-10-30**：完成 S7（VM FFI 集成，标量/结构体/sret/varargs/dlopen，2/2，37K）。
- **2026-10-30**：完成 S8（静态 callback trampoline + 反向计划，qsort/结构体 callback，3/3，20K）。
- **2026-10-30**：完成 S6（LLVM IR 标量降级，sample1=42/sample2=55，2/2，17K）。
- **2026-10-30**：完成 S10（Win64 ABI，Windows 测试机 6/6，34K PE）。
- **2026-10-30**：S11 Win32 阻塞解决（根因 harness `argsFree`；C shim + 保留 args；Zig 连续/每进程 6/6，exit 0）。
- **2026-10-30**：S9 线性内存/数组/结构体/指针/union/memcpy/memset/globals/字符串通过（sample1..12 12/12，21K）。
- **2026-10-30**：完成 S12（ARM64 AAPCS64，qemu 6/6，12K）。
- **2026-10-30**：S9 剩余扩展：bitfield（v1 排除）、float/`long double`、外部调用、c-testsuite。
- **2026-10-30**：v1 Linux x64 首版落地：`compiler/` + `runtime/` + `examples/`；`make test`（runtime 2、compiler 7、端到端 8）通过。
- **2026-10-30**：编译器侧 MEMORY struct `byval`/`sret` FFI + runtime `--lib` 加载；`ffi_structs` 结果 28。
- **2026-10-30**：register-class S8（coerced i64）+ D16（双 XMM 聚合返回，extractvalue/fptosi）；`ffi_regstruct` 结果 102。
- **2026-10-30**：callback 静态 trampoline + 可重入 VM（executeLoop/runCallback）；qsort 示例结果 1。
- **2026-10-30**：mixed-class `{i64,double}` 聚合返回/参数（RAX+XMM0）；`ffi_mixedstruct` 结果 11。
- **2026-10-30**：double 算术/比较（fadd/fsub/fmul/fdiv、fcmp、裸浮点常量、fneg）；`math` 结果 8。
- **2026-10-31（周六）**：float32 算术/FCmp/fpext/fptrunc/fptosi/sitofp + float FFI；`float_math=8`、`ffi_float=5`。
- **2026-10-31（周六）**：bitfield（clang shift/mask lowering）；`bitfields=12`；`make test` runtime 3 / compiler 11 / 端到端 15。
- **2026-10-31（周六）**：M11 基础加固——plan 数量/ABI 位置/offset/size 校验，错误路径测试（缺失输入、坏 package、未知符号），`--version`/`--help`。
- **2026-10-31（周六）**：`make size`/`make release-check`；ReleaseSmall runtime 40K、hello.cib 78B、qsort.cib 460B。
- **2026-10-31（周六）**：package 截断 smoke（0/4/5/14/15/30/100 字节）全部干净失败，无崩溃。
- **2026-10-31（周六）**：c-testsuite 子集 harness（9/9）+ `select` 降级。
- **2026-10-31（周六）**：long double 支持（16B 存储、64-bit 精度）；`longdouble=8`。
- **2026-10-31（周六）**：多 ABI 落地——compiler `--target`、Win64/Win32/AAPCS64 plan builder、runtime `ffi/platform.zig`/`ffi/native.zig`、Win64/Win32/ARM64 frame/engine；交叉测试 33/33（Win64 11、Win32 11、ARM64 11）。
