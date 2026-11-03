# C 解释器架构与关键决策

> 本文只记录当前实现、关键决策、ABI 契约、验证基线和已知边界。按日期记录的修复过程、已删除实现和历史验证不再保留；变更历史以 git 为准。

## 1. 产品与设计目标

cinterp 是一个 C 解释器系统：

- **编译器（构建期）**：Zig 程序调用 `zig cc` 生成 LLVM IR 文本，将 IR 降为紧凑的栈式字节码 CIVM，并为每个外部调用/callback 生成 ABI 计划，打包为 CIPKG。
- **运行时（发布物）**：Zig 字节码 VM，用固定汇编 ABI 引擎执行原生调用和 callback；不链接 libffi，不使用 `@call` 桩矩阵，不生成动态可执行内存。
- **FFI 模型**：编译器知道完整签名，运行时只按计划搬运寄存器/栈/sret；结构体布局与宿主 ABI 一致，VM 指针就是宿主指针。
- **平台**：Linux x86-64（SysV）、Windows x86-64、Windows x86、Linux AArch64（AAPCS64）。

## 2. 已确认决策

- **运行时语言**：Zig 0.13（pin；0.14 的 `CallingConvention` 语法变化，暂不升级）。
- **编译器**：Zig + `zig cc`（Zig 捆绑 clang 18），中间表示固定为 LLVM IR 文本（`-O0 -S -emit-llvm`）；typed AST 是唯一 IR 前端，不使用 libclang/LLVM 进程内 API。
- **C 范围**：核心 C17 + C11 常用特性 + 结构体 FFI；以 clang `-O0` IR 的实际输出为契约。
- **FFI**：编译期生成 ABI 计划，运行时用固定汇编引擎执行；callback 用静态 trampoline 池 + 反向计划。
- **Callback 池**：进程级固定 256 槽；VM 销毁或 plan 重载后槽位**永久退休、永不复用**，累计注册超过 256 个 callback 返回 `TooManyCallbacks`。
- **发布方式**：编译器只在构建期使用；发布物是运行时库/可执行文件 + 字节码。Linux x86-64 tarball 额外包含 `cinterp-cc`，其余 tarball 为 runtime-only。
- **执行模型**：一个 VM 同一时间只加载并执行一个 CIB；不支持 CIB-to-CIB 链接。运行时只执行可信构建产物，不提供进程内沙箱。

## 3. 平台与 ABI 矩阵

| ABI | 平台 | 引擎/回调 |
| --- | --- | --- |
| x86-64 System V | Linux x64 | `call_x86_64_sysv.S` / `callbacks_x86_64_sysv.S` |
| x86-64 Microsoft | Windows x64 | `call_x86_64_win64.S` / `callbacks_x86_64_win64.S` |
| x86 Microsoft 32-bit | Windows x86 | `call_x86_win32.S` / `callbacks_x86_win32.S`；支持 cdecl、stdcall、fastcall；`thiscall` 不支持 |
| AArch64 AAPCS64 | Linux ARM64 | `call_arm64_aapcs.S` / `callbacks_arm64_aapcs.S` |

Linux i386/ARM32、macOS、Windows ARM64 不在目标；macOS/musl/未知 OS 在加载阶段显式拒绝。

## 4. 总体架构

**编译器流程**

```text
C 源码
  → zig cc -S -emit-llvm -O0
  → compiler/src/ir（typed lexer/parser/AST/verifier）
  → lower_ast.zig（CIVM 字节码 + FFI 计划）
  → main.zig（CIPKG v2：CIVM + CIPL + CIPM + CIPI）
  → cinterp-cc（可选 --dump/--dump-ast/--dump-imports）
```

**运行时流程**

```text
CIPKG loader（事务性）
  → CIVM 模块 + CIPL 计划 + CIPM 目标校验 + CIPI provider
  → 字节码执行（8 字节栈槽 + 线性内存）
  → CALL_NATIVE/CALL_VARARG
  → platform.zig 按 ABI 填充 ABIFrame
  → 固定汇编引擎调用原生函数
  → 原生 callback → 静态 trampoline → Zig dispatcher → 重新进入 VM
```

## 5. 编译器

### 5.1 前端

固定参数：

```bash
zig cc -S -emit-llvm -O0 -fno-discard-value-names \
  -fno-sanitize=all -fno-stack-protector \
  -ffine-grained-bitfield-accesses program.c
```

Windows 目标按需加 `-fms-extensions -fdeclspec`。`-O0` 保证局部变量以 alloca/load/store 形式出现，避免在 VM 中实现 SSA 构造和优化 pass；phi 仍按分支/栈槽降级。

`compiler/src/ir/` 解析并校验支持的 LLVM IR 子集：标量/指针/数组/结构体、alloca/load/store/GEP、整数/浮点/位运算/比较/转换、br/switch/select/phi、直接/间接/tail call、常用 `llvm.*` intrinsic、byval/sret、f80/fp128、varargs、VLA 和 setjmp/longjmp。完整契约见 [`docs/ir-subset.md`](./docs/ir-subset.md)。

明确拒绝：向量可执行值、`insertvalue`、extract/insert/shuffle vector、`freeze`、atomic/fence、invoke/resume/landingpad、indirectbr/callbr、未知 intrinsic、内联汇编。

### 5.2 Lowering

- 每个 LLVM SSA 值映射到栈槽或临时栈项；`load`/`store` 生成带类型标签的内存操作。
- `getelementptr` 优先折叠为常量字节偏移，不能折叠时生成 `PTR_ADD`。
- `icmp`/`fcmp` 生成比较 + 谓词；`br` 生成 `JMP/JZ/JNZ`；`switch` 生成 `SWITCH`。
- 聚合 load 返回指向源字节的指针，聚合 store 使用 `MEMCPY`；`extractvalue` 生成字段偏移访问。
- 结构体布局按目标 clang 布局计算；结构体赋值、union、bitfield、指定初始化器由 clang 降级为 load/store/shift/mask。
- 源位置只用于编译诊断；CIVM 不携带 debug info。

### 5.3 调用约定、计划去重与上限

- 调用约定从 LLVM 的 `x86_stdcallcc`/`x86_fastcallcc` 映射为 `plan.conv`：0=cdecl、1=stdcall、2=fastcall。调用点优先，声明回退；已知 WinAPI 导出仍由构建期 MinGW 索引覆盖。
- 前端为外部调用、间接调用和 callback 生成 `CallPlan`；相同完整内容（name、args/locs、ret_locs、stack/sret/sse/ret_size/conv）的 plan 由 `internPlan` 去重。
- 序列化前执行 `validateLimits`，避免生成运行时无法加载的包：
  - 512 functions、1024 plans、每 plan 64 args、每 arg/return 8 locs；
  - 函数/plan 名 128 字节；
  - 512 imports、每 import 8 providers；
  - import/provider/symbol 名 64 字节，provider version 32 字节；
  - CIVM module ≤ 2 MiB。
- 超过上述上限返回明确的 `compiler limit: ...` 错误；compile-only 压力测试用例如超过运行时容量，在 manifest 中显式 skip，而不是放宽运行时上限。

## 6. 字节码与 VM

### 6.1 值与 opcode

- 栈槽固定 8 字节；`Value` 为 `extern union { i: i64, u: u64 }`，浮点按位存放，f32 仅在低 32 位有效，f80/f128 通过线性内存按指针传递。
- **opcode 唯一定义**：[`compiler/src/opcodes.zig`](./compiler/src/opcodes.zig)（`OP_*: u8`，0x01–0xA2）；运行时同序号常量在 `runtime/src/vm.zig`，两者必须同步。
- 当前实现覆盖常量/局部变量、内存、整数/浮点/位运算/比较/转换、控制流、指针/GEP、varargs、setjmp/longjmp、VLA、f80/f128、`llvm.is.fpclass`、`MEMCPY/MEMSET`、原生调用/callback 等。
- 操作数使用固定小端 `u8/u16/u32/u64` 编码；跳转目标是加载后的字节码偏移。CIVM/CIPL 的逐字节布局见 [`docs/cib.md`](./docs/cib.md)。

### 6.2 帧与线性内存

- VM 使用固定槽栈（默认/上限 `MAX_STACK=8192`，`ci_vm_config.stack_size` 只能下调）、帧数 `MAX_FRAMES=512`。
- 线性内存默认 1 MiB，可由 `ci_vm_config.memory_size` 调小/调大，上限 16 MiB；`mem_top` 是 bump pointer，函数返回时回退 alloca 区域。
- `argv/envp` 位于线性内存顶部；所有 alloca/`SET_MEM_TOP`/`STACKRESTORE` 受 `memLimit()` 限制，不能覆盖参数区。
- VLA 使用 `STACKSAVE/STACKRESTORE` 恢复 `mem_top`；`alloca` 的零大小和大对象分别用固定/动态 opcode 处理。

### 6.3 varargs 与 setjmp

- 外部 varargs 的参数提升由 clang 完成；前端为实际参数生成 Loc（SysV `%al`、Win64 浮点 GPR 副本/栈 home、Win32 栈、AArch64 v0–v7/栈）。
- 内部 varargs 调用携带每个额外参数的 layout code；VM 的 `va_start/va_arg/va_end/va_copy` 覆盖四个 ABI，支持 `long double` 和聚合参数。
- `setjmp/longjmp` 是 VM 级实现（含 Windows `_setjmp3`/`__intrinsic_setjmpex`），保存/恢复 ip、栈基址、帧数、`mem_top`；slot 越界返回 `BadLocal`/`BadLongjmp`。

## 7. FFI

### 7.1 编译期 ABI 计划

clang 已经在 LLVM IR 中完成大部分 ABI lowering：

- 小结构体参数 → coerced `i64`/`double`/literal aggregate；
- MEMORY 参数 → `ptr byval(%struct.X)`；
- MEMORY 返回 → `void + ptr sret(%struct.X)`。

前端因此直接处理 lowered 类型，只分类 literal aggregate、`byval` 和 `sret`。计划模型以 [`compiler/src/abi.zig`](./compiler/src/abi.zig) 的 `Plan`/`ArgPlan`/`Loc` 为唯一来源，运行时解码视图在 [`runtime/src/ffi/abi.zig`](./runtime/src/ffi/abi.zig)：

- `Plan`：`name`、`args`、`ret_locs`、`stack_size`、`sret`、`sse_count`、`ret_size`、`conv`。
- `LocKind`：`gpr`、`xmm`、`stack`、`sret`、`rax`、`rdx`、`xmm0`、`xmm1`、`st0`、`xmm2`、`xmm3`。
- 结构体参数按目标 ABI 拆成多个 Loc；返回值覆盖标量、浮点、多寄存器聚合和 sret。
- varargs 的实际参数位置全部进入计划，不做运行时类型推断。

不使用 `@call` 的原因：它要求 comptime 已知签名，会导致 per-signature 桩矩阵；计划 + 固定汇编是数据驱动的，同一段汇编处理任意签名。

### 7.2 固定汇编引擎与 marshal

- `ffi/platform.zig` 在编译期按目标选择 Frame、marshal/readRet/invoke/validate 和 callback 表。
- `marshal` 按 `CallPlan` 把 VM 值拷贝到 GPR/XMM/vec/stack/sret，结构体按 Loc 拷贝字节，保持位模式。
- 每个 ABI 一段 `.S`：装载寄存器/栈、调用目标、捕获返回值；不解析签名，不生成动态代码。
- 返回值按 `ret_locs` 读取；Win32 i64 用 EAX:EDX 合并，float 从 ST0 读取并转 f32。
- plan 校验覆盖 loc 索引、offset/size、stack/sret 一致性、返回寄存器合法性和 4096 字节 staging block；损坏计划在调用前失败。

### 7.3 Callback

- 每个 callback 函数生成反向计划；trampoline 把槽位号放入非参数寄存器，跳到公共入口，保存参数寄存器/栈后调用 `ci_callback_dispatch`。
- dispatcher 按计划重建参数（含多 Loc 聚合/HFA）、运行 VM 函数、按 `ret_locs` 写回返回值；可重入，不要求外层帧展开。
- Win32 cdecl/stdcall callback 支持；stdcall 使用 `Win32CbFrame.cleanup` 在返回时跳过参数。fastcall callback 不支持（trampoline 不捕获 ECX/EDX），注册前返回 `UnsupportedCallback`。
- 槽位永久退休，不复用；单进程累计上限 256。

### 7.4 结构体 FFI

- `byval` 参数复制原始字节到栈；`sret` 通过隐藏指针写回调用方缓冲区。
- register-class 聚合按 eightbyte 分类为 GPR/XMM；混合类（如 `{ i64, double }`）支持 RAX+XMM0。
- HFA 1–4 个 float/double 使用连续 v 寄存器，HFA 3/4、栈上 HFA、4 个返回向量和 fp128 均已覆盖。
- 没有代表类型矩阵：计划里直接是位置和字节数。

## 8. 调用约定要点

### 8.1 x86-64 System V

- 整数：RDI、RSI、RDX、RCX、R8、R9；浮点：XMM0–XMM7。
- varargs：`%al` = 使用的 XMM 数量；栈 16 字节对齐；调用者清理。
- 返回：RAX/RDX 或 XMM0/XMM1；大结构体 sret。

### 8.2 x86-64 Microsoft

- 整数：RCX、RDX、R8、R9；浮点：XMM0–XMM3。
- 寄存器编号按参数位置，不是独立浮点计数器（`f(int,double,int,double)` → RCX/XMM1/R8/XMM3）。
- sret 占位置 0，GPR/XMM 两个文件整体后移；32 字节 shadow space；超过 4 个位置用栈。
- varargs 浮点在位置 XMM、GPR 副本和栈 home 中按计划复制；`sse_count` 写 AL。
- 返回：RAX/XMM0；>8B 结构体 sret；1/2/4/8B 结构体按整数返回。

### 8.3 Windows x86

- cdecl/stdcall 参数全部在栈上，4 字节对齐；fastcall 前两个 4 字节标量走 ECX/EDX，其余在栈上。
- byval 结构体复制原始字节；sret 隐藏指针在栈首。
- 返回：≤4B EAX；i64 合并为 8B rax loc；float/double 在 ST0；小结构体 EAX:EDX；大结构体 sret。
- `conv` 沿用 CIPL 字节：0=cdecl、1=stdcall、2=fastcall；`thiscall` 不支持。

### 8.4 AArch64 AAPCS64

- 整数/指针 x0–x7；浮点/向量 v0–v7；栈 16 字节对齐。
- 返回 x0/x1 或 v0–v3；大结构体 sret 指针在 x8。
- HFA 1–4 个同类型成员使用连续 v 寄存器；栈上 HFA 和 4 返回向量已覆盖。

## 9. 外部符号解析与链接元数据

- 编译器在构建期由 [`compiler/tools/gen_link_index.zig`](./compiler/tools/gen_link_index.zig) 从已安装 Zig 工具链生成索引：
  - Windows：Zig 自带的 MinGW `.def` 文件 → DLL、符号、x86 stdcall 装饰/调用约定；
  - Linux：Zig 自带的 glibc `abilists` → 符号所属 soname。
- 索引以二进制形式内嵌到 `cinterp-cc`；没有签入的 cstdapi/winmd 数据库，也没有 `--link-db`。
- 唯一保留的签入链接元数据是 [`compiler/src/data/link_wrappers.json`](./compiler/src/data/link_wrappers.json)，只描述同签名别名（Windows `snprintf -> _snprintf`、`vsnprintf -> _vsnprintf`）。`atexit -> __cxa_atexit` 的参数适配在 `lower_ast.zig` 中处理；`signal` 按普通 callback 使用。
- 编译器把命中的 provider 写入 CIPI；未命中的符号不写 entry，留给运行期 fallback。
- 运行期解析顺序：显式 `--lib` → CIPI provider（缓存 handle）→ 进程符号/默认 CRT。自动 provider 只接受库名，拒绝路径分隔符；绝对路径只允许显式 `--lib`。直接原生调用目标按 plan index 在首次调用后缓存；包/plan 重载会清空 provider/target 缓存。
- CIPM 的 `link_db` 只记录索引来源（`mingw-defs@<zig version>` / `glibc-abilists@<zig version>`）。
- MinGW defs 不含 `min_os`，新包统一写 0，旧包仍按原字段校验；glibc abilists 的 `ld` 库、objects/TLS 段不进入 Linux provider 索引。构建需要 Zig 0.13 自带的 `libc/mingw` 与 `libc/glibc/abilists`，缺失时 `zig build` 直接失败。

## 10. 包格式、C ABI 与上限

### 10.1 包格式

- **CIVM v1**：magic/版本/arch、函数表、代码；模块上限 2 MiB，函数上限 512，函数名上限 128。
- **CIPL v3**：命名 CallPlan 表；运行时兼容 v2。计划上限 1024，每 plan 64 args、8 ret locs、每 arg 8 locs，名称上限 128。
- **CIPKG v2**：25 字节头 + CIVM + CIPL + CIPM + CIPI；v1 旧包仍可读。
- **CIPM v1**：arch/OS/ABI/指针宽度/端序/features/min_runtime/triple/link_db/producer；加载前校验目标。
- **CIPI v1**：plan index → provider 库/真实符号/别名/ordinal/callconv/arch_mask/min_os；上限 512 entry、每 entry 8 provider，名称/符号 64 字节。
- 详细字段和错误码见 [`docs/cib.md`](./docs/cib.md)；版本兼容策略见 [`docs/compatibility.md`](./docs/compatibility.md)。

### 10.2 C ABI

公开头文件 `runtime/include/cinterp.h`；`zig build` 安装可执行文件、静态/共享库和头文件。`CI_ABI_VERSION=2`。

```c
ci_vm *ci_vm_create(size_t stack_size);
ci_vm *ci_vm_create_ex(const ci_vm_config *config);
void ci_vm_destroy(ci_vm *vm);
int ci_vm_load_module(ci_vm *, const uint8_t *, size_t);
int ci_vm_load_plans(ci_vm *, const uint8_t *, size_t);
int ci_vm_load_package(ci_vm *, const uint8_t *, size_t);
int ci_vm_load_library(ci_vm *, const char *);
int ci_vm_run(ci_vm *, const char *entry);
int ci_vm_run_args(ci_vm *, const char *entry, int argc, const char *const *argv);
int64_t ci_vm_result(const ci_vm *);
const char *ci_vm_last_error(const ci_vm *);
int ci_vm_last_error_code(const ci_vm *);
int ci_vm_clear_error(ci_vm *vm);
int ci_abi_version(void);
const char *ci_version(void);
```

- 返回 `int` 的接口成功返回 `CI_OK`，失败返回具体负值 `CI_E_*`；`CI_ERROR` (-1) 仅用于无法归类的错误。
- `ci_vm_last_error_code()` 返回同一类别，`ci_vm_last_error()` 返回具体错误名，`ci_vm_clear_error()` 清除两者。
- `ci_vm_run`/`ci_vm_run_args` 返回状态而不是 C `main` 返回值；结果用 `ci_vm_result` 读取。
- loader 是事务性的；失败不会替换已加载包。
- `ci_vm_config` 的 `struct_size` 兼容旧调用方；`stack_size=0` 使用默认 8192 槽，`memory_size=0` 使用默认 1 MiB（最大 16 MiB）。
- 一个 VM 单线程使用；callback 边界可重入。callback 注册表按 VM 隔离，trampoline 槽进程级永久退休。

### 10.3 运行时上限

`MAX_FUNCS=512`、`MAX_FRAMES=512`、`MAX_STACK=8192`、`MAX_MODULE=2 MiB`、`MAX_PLANS=1024`、`MAX_ARGS=64`、`MAX_LOCS=8`、`MAX_NAME=128`、`MAX_IMPORTS=512`、`MAX_PROVIDERS=8`；native target 注册表 256，超出返回 `TooManyNativeTargets`。

## 11. 目录与关键文件

```text
compiler/
  build.zig                    # 构建期运行 gen_link_index
  tools/gen_link_index.zig     # MinGW defs / glibc abilists → 内嵌索引
  src/main.zig                 # CLI、CIPKG/CIPM/CIPI writer、validateLimits
  src/opcodes.zig              # CIVM opcode 唯一定义
  src/abi.zig                  # Plan/ArgPlan/Loc、buildPlanForAbi、convFromName
  src/lower_ast.zig            # AST → CIVM、internPlan、callback 计划
  src/imports.zig              # CIPI 结构与序列化
  src/link_index.zig           # 生成符号索引的二进制格式
  src/win_defs.zig             # Windows provider（Zig MinGW defs）
  src/libc_defs.zig            # Linux provider（Zig glibc abilists）
  src/link_wrappers.zig        # target ABI 别名
  src/data/link_wrappers.json  # 唯一签入链接元数据
  src/ir/                      # lexer/ast/parser/verify/dump/tests
  src/testdata/lower_ast/      # lowering fixtures + goldens

runtime/
  build.zig                    # 可执行文件、static/shared 库、头文件
  include/cinterp.h            # C ABI 2
  src/main.zig                 # cinterp-run CLI
  src/vm.zig                   # VM、线性内存、C ABI、callback dispatcher
  src/vm_test.zig              # 运行时单测
  src/ffi/abi.zig              # 运行时 Loc/ArgPlan/CallPlan
  src/ffi/plan_loader.zig      # CIPL 解码与 plan store
  src/ffi/link_loader.zig      # CIPM/CIPI 解析与校验
  src/ffi/native.zig           # dlopen/LoadLibrary 符号解析
  src/ffi/platform.zig         # ABI 选择、frame、marshal、invoke、validate
  src/ffi/asm/                 # 四个调用引擎 + 四个 callback trampoline
  tests/                       # C API smoke/argv/fuzz host

examples/                      # hello、FFI、HFA、callback、long double、Win32 约定等
docs/                          # 格式、嵌入、兼容性、IR 子集、Zig 前端
packaging/                     # pkg-config、CMake、Rust binding、release README
scripts/                       # test/fuzz/differential/release harness
tests/                         # csuite、manifests、known failures
```

## 12. 构建、测试与发布

```bash
make compiler runtime
make test                 # runtime + compiler 单测、端到端、错误路径、C API
make c-testsuite          # 本地 17 例
make lint                 # civm_lint.py 校验包结构
make differential         # native vs cinterp 返回值
make test-suites-smoke    # csuite 17/17
make test-suites          # standard
make test-suites-full     # full
make test-suites-nightly  # nightly + 100-seed 生成式差分
make fuzz                 # load-only 变异
make fuzz-exec            # 执行变异；崩溃失败，变异无限循环超时计数并保存
make fuzz-bytecode        # 结构化 CIVM 变异
make fuzz-ffi-exec
make fuzz-capi-asan
make fuzz-sanitizer
make size                 # Runtime ReleaseSmall 体积
make size-cross           # 四个目标体积
make release-artifacts    # tarball + SBOM + SHA256SUMS
make evidence             # test/lint/size/smoke/differential + checker
make check-version        # VERSION 单一来源校验
```

当前基线：

- `make test-suites-full`：**4319/4521 通过，202 skip**；其中 4 个 compile-only 压力用例因超过运行时上限显式 skip（512 imports / 64 args / 2 MiB module）。
- `make test-suites`：396/495（99 skip）。
- `make test-suites-nightly`：4447/4649（202 skip）；YARPGen 100 seeds 为 93 通过 / 7 skip / 0 failure。
- `scripts/test_cross.sh`：62 个示例用例（Win64 20 / Win32 23 / ARM64 19），Wine、真实 Windows 和 qemu 均可运行。
- 本地 c-testsuite 17/17；上游 manifest 为 218/2，独立脚本默认旧 skip 列表为 217/3（`00189` 已可通过），引用时需注明来源。
- ReleaseSmall：native Linux x64 102,336 B；size-cross static sysv 41,328 B、Win64 100,352 B、Win32 116,224 B、ARM64 101,968 B（均 < 128 KiB）。
- release tarball：Linux x86-64 含 `bin/cinterp-cc` 和 `bin/cinterp`，其余为 runtime-only；每个 tarball 带自己的 README、SBOM，compiler tarball 额外带 `THIRD_PARTY_NOTICES.md`。

## 13. 当前边界与明确不支持

- **平台**：仅 Linux x86-64/AArch64（glibc）与 Windows x64/x86；不提供 macOS、musl、Windows ARM64、Linux i386/ARM32。
- **C/ABI**：`_Complex`、GCC builtins、外部 inline/weak 语义、Win32 `thiscall`、Win64 `__vectorcall`/COM、SysV `i128`/向量参数、向量类型、内联汇编、`_Atomic`/`_Thread_local` 不支持。
- **链接**：不支持 CIB-to-CIB 链接、包间导出/依赖；跨包复用需合并源码后重新生成 CIB，或通过 `--lib` 使用普通共享库。
- **执行模型**：单线程、单 VM、单 CIB；无进程内沙箱、无 Safe 模式；不可信输入由宿主隔离。
- **Windows CRT**：`%Lf` 行为与原生 MinGW 一致，不额外提供格式化 shim。
- **外部数据符号**：基础 provider（`stdout`/`errno`/`environ`/`stdin`/`tzname`/`opt*`、Windows UCRT helper 等）已支持；更冷门的数据符号走 provider/fallback。

## 14. 已知限制与后续方向

- **聚合返回值共享 `ret_buf`**：VM 只有一个 4 KiB 返回缓冲区；两个聚合返回值同时存活时会互相覆盖。修复需要结果所有权/生命周期重构，当前由宿主在跨调用保存聚合指针时自行复制。
- **Win32 `__fastcall` callback 不支持**：trampoline 只保存出参栈区，ECX/EDX 参数会丢失；注册前返回 `UnsupportedCallback`。原生/间接 fastcall 调用支持。
- **原生库句柄不卸载**：`--lib` 与 CIPI provider 的 `dlopen`/`LoadLibrary` 句柄随 VM 生命周期保留，没有 `dlclose`/`FreeLibrary`；长期多包宿主应自建进程边界。
- **callback 槽位是一次性预算**：256 槽永久退休，累计注册超过 256 个 callback 返回 `TooManyCallbacks`。
- **生成式差分**：YARPGen whitelist 已清空；nightly 的 7 个 skip 是 native 拒绝/超时或 `compiler limit:` 引擎上限。Csmith 仍有 3 条 known failure；报告保留 stale 检测，whitelist 条目开始通过会失败。
- **后续方向**：向量/复杂 ABI、更多 external data、精确 Windows `%Lf` shim、跨 ABI 执行 fuzz 等按需扩展；不以放宽运行时上限或修改 expected 的方式“修复”。

## 15. 参考资料

- chibicc / c-testsuite：C 测试用例和编译器结构参考。
- LLVM IR 指令语义与 clang `-O0` 输出模式。
- System V AMD64、Microsoft x64/x86 调用约定、AArch64 AAPCS64。
- libffi / dyncall：ABI 分类和栈布局参考（不引入依赖）。
