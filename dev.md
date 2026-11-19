# C 解释器架构与关键决策

> 本文只记录当前实现、关键决策、ABI 契约、验证基线和已知边界。按日期记录的修复过程、已删除实现和历史验证不再保留；变更历史以 git 为准。

## 1. 产品与设计目标

cinterp 是一个 C 解释器系统：

- **编译器（构建期）**：Zig 程序调用 `zig cc` 生成 LLVM IR 文本，将 IR 降为紧凑的栈式字节码 CIVM，并为每个外部调用/callback 生成 ABI 计划，打包为 CIPKG。
- **运行时（发布物）**：Zig 字节码 VM，用固定汇编 ABI 引擎执行原生调用和 callback；不链接 libffi，不使用 `@call` 桩矩阵，不生成动态可执行内存。
- **FFI 模型**：编译器知道完整签名，运行时只按计划搬运寄存器/栈/sret；结构体布局与宿主 ABI 一致，VM 指针就是宿主指针。
- **进程模型**：一个 `ci_vm` 持有一个 CIB；进程通过 `ci_process_*` 持有多个 VM，不同 VM 可在不同线程并行；同一 CIB 可在其 VM 上重复运行，每次都是全新镜像。
- **平台**：Linux x86-64（SysV）、Windows x86-64、Windows x86、Linux AArch64（AAPCS64）。

## 2. 已确认决策

- **运行时语言**：Zig 0.13（pin；0.14 的 `CallingConvention` 语法变化，暂不升级）。
- **编译器**：Zig + `zig cc`（Zig 捆绑 clang 18），中间表示固定为 LLVM IR 文本（`-O0 -S -emit-llvm`）；typed AST 是唯一 IR 前端，不使用 libclang/LLVM 进程内 API。
- **C 范围**：核心 C17 + C11 常用特性 + 结构体 FFI；以 clang `-O0` IR 的实际输出为契约。
- **FFI**：编译期生成 ABI 计划，运行时用固定汇编引擎执行；callback 用静态 trampoline 池 + 反向计划。
- **Callback 池**：进程级固定 256 个静态槽，不生成可执行内存。自动 `@cb`/`OP_CREATE_CALLBACK` 槽在 VM 生命周期内保留并跨重复运行复用，VM 销毁或 plan 重载后退休；`ci_callback_acquire`/`ci_callback_release` 允许 CIB 显式归还槽位以便复用，release 后旧指针不得再调用。
- **发布方式**：编译器只在构建期使用；发布物是运行时库/可执行文件 + 字节码。Linux x86-64 tarball 额外包含 `cinterp-cc`，其余 tarball 为 runtime-only。
- **执行模型**：一个 VM 同一时间只加载并执行一个 CIB，同一 VM 只允许一个执行上下文；进程可通过 `ci_process_*` 持有多个 VM，不同 VM 可并行。不支持 CIB-to-CIB 链接。运行时只执行可信构建产物，不提供进程内沙箱。

## 3. 平台与 ABI 矩阵

| ABI | 平台 | 引擎/回调 |
| --- | --- | --- |
| x86-64 System V | Linux x64 | `call_x86_64_sysv.S` / `callbacks_x86_64_sysv.S` |
| x86-64 Microsoft | Windows x64 | `call_x86_64_win64.S` / `callbacks_x86_64_win64.S` |
| x86 Microsoft 32-bit | Windows x86 | `call_x86_win32.S` / `callbacks_x86_win32.S`；支持 cdecl、stdcall、fastcall、thiscall（原生/间接/回调） |
| AArch64 AAPCS64 | Linux ARM64 | `call_arm64_aapcs.S` / `callbacks_arm64_aapcs.S` |

Linux i386/ARM32、macOS、Windows ARM64 不在目标；macOS/musl/未知 OS 在加载阶段显式拒绝。

## 4. 总体架构

**编译器流程**

```text
C 源码
  → zig cc -S -emit-llvm -O0
  → compiler/src/ir（typed lexer/parser/AST/verifier）
  → lower_ast.zig（CIVM 字节码 + FFI 计划）
  → main.zig（CIPKG v4：CIVM v2 + CIPL + CIPI + CIPC）
  → cinterp-cc（可选 --dump/--dump-ast/--dump-imports）
```

**运行时流程**

```text
CIPKG loader（事务性）
  → CIVM 模块 + CIPL 计划 + CIPI provider
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

明确拒绝：`insertvalue`、extractelement/insertelement/shufflevector、atomicrmw/cmpxchg/fence、invoke/resume/landingpad、indirectbr，以及作为指令的 `va_arg`。`freeze` 按恒等操作降低；`callbr` 可以解析并按普通 call 降低（标签列表忽略）；未知 `llvm.*` intrinsic 作为外部调用计划在运行期失败；内联汇编调用由 lowering 拒绝。

### 5.2 Lowering

- 每个 LLVM SSA 值映射到栈槽或临时栈项；`load`/`store` 生成带类型标签的内存操作。
- `getelementptr` 优先折叠为常量字节偏移，不能折叠时生成 `PTR_ADD`。
- `icmp`/`fcmp` 生成比较 + 谓词；`br` 生成 `JMP/JZ/JNZ`；`switch` 生成 `SWITCH`。
- 聚合 load 返回指向源字节的指针，聚合 store 使用 `MEMCPY`；`extractvalue` 生成字段偏移访问。
- 结构体布局按目标 clang 布局计算；结构体赋值、union、bitfield、指定初始化器由 clang 降级为 load/store/shift/mask。
- 源位置只用于编译诊断；CIVM 不携带 debug info。

### 5.3 调用约定、计划去重与上限

- 调用约定从 LLVM 的 `x86_stdcallcc`/`x86_fastcallcc`/`x86_thiscallcc` 映射为 `plan.conv`：0=cdecl、1=stdcall、2=fastcall、3=thiscall。调用点优先，声明回退；已知 WinAPI 导出仍由构建期 MinGW 索引覆盖。
- 前端为外部调用、间接调用和 callback 生成 `CallPlan`；相同完整内容（name、args/locs、ret_locs、stack/sret/sse/ret_size/conv）的 plan 由 `internPlan` 去重。
- 序列化前执行 `validateLimits`，避免生成运行时无法加载的包：
  - 512 functions、1024 plans、每 plan 64 args、每 arg/return 8 locs；
  - plan/data/provider 名称 128 字节；CIVM 不序列化内部函数名；
  - 512 imports、每 import 8 providers；
  - import/provider/symbol 名 64 字节；
  - CIVM module ≤ 2 MiB。
- 超过上述上限返回明确的 `compiler limit: ...` 错误；compile-only 压力测试用例如超过运行时容量，在 manifest 中显式 skip，而不是放宽运行时上限。

## 6. 字节码与 VM

### 6.1 值与 opcode

- 栈槽固定 8 字节；`Value` 为 `extern union { i: i64, u: u64 }`，浮点按位存放，f32 仅在低 32 位有效，f80/f128 通过线性内存按指针传递。
- **opcode 唯一定义**：[`compiler/src/opcodes.zig`](./compiler/src/opcodes.zig)（`OP_*: u8`，0x01–0xA5）；运行时同序号常量在 `runtime/src/vm.zig`，两者必须同步。
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

### 6.4 重复运行、全新镜像与每 VM 线程

- `ci_vm_run`/`ci_vm_run_args` 每次进入都调用 `resetRunImage`：清零值栈槽位/`sp`/`mem_top`/`arg_area_start`/`frame_count`，清零整块线性内存，清空 `jumps`（上一次运行的 `setjmp` 目标不能复活），清空按 run 收集的 `native_targets`；`native_plan_cache` 保留（plan 索引不变）。
- `result` 不参与重置：只有成功运行才写入，`ci_vm_result` 始终返回最后一次成功结果。
- 全局安装代码由编译器生成在 `main` 开头（`SET_MEM_TOP` + 全局镜像），因此重复运行 `main` 会重新安装 globals。运行时只接受 `main` 别名；其他入口名返回 `CI_E_ENTRY`。
- 每 VM 有独立执行权（owner/depth/条件变量）：另一线程 `ci_vm_run` 返回 `CI_E_BUSY`；同一线程嵌套（callback 内再次 run）返回 `CI_E_RUNTIME`，避免清空外层镜像。
- loader（`ci_vm_load_module`/`load_plans`/`load_package`/`load_library`）在执行期间返回 `CI_E_BUSY`。`ci_vm_busy` 查询状态；`ci_vm_destroy` 等待空闲，`ci_vm_destroy_ex(vm, CI_DESTROY_TRY)` 在 busy 时返回 `CI_E_BUSY`。
- 不同 VM 使用不同锁，可并行；进程级只有 callback 槽位锁和 `ci_process` 注册表锁。
- callback dispatch 的线程规则：同线程重入；空闲 VM 尝试取得执行权（并发 `ci_vm_run` 可能先取得，随后仍走 skip）；另一线程正在运行 VM 时 fail-fast，不排队、不阻塞，非 sret 返回值置零、sret 缓冲区保持不变，并记录 `CI_E_BUSY`（`ci_vm_callback_error` 可读，sticky 到 `ci_vm_clear_error`）。`libc-test/pthread_tsd` 因此显式 skip。

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
- 槽位是进程级固定 256 个静态 trampoline，不生成可执行内存。自动槽（`OP_CREATE_CALLBACK`，把 `@cb` 传给原生调用）绑定到所属 VM，跨重复运行复用，VM 销毁/plan 重载时退休，避免宿主保留的旧函数指针进入另一个 VM。
- 显式槽使用 `ci_callback_acquire(fn)`/`ci_callback_release(fn)` 宏：`cinterp-cc` 通过 `zig cc -include` 强制包含内嵌的 `compiler/src/data/cinterp_callbacks.h`，CIB 源码不需要 `#include` 或 include path。编译器把 `__ci_callback_acquire`/`__ci_callback_release` 降为 CIVM 0xA3/0xA4，不生成 CIPI import。
- acquire 只接受直接函数引用（可带 cast；运行期函数指针变量在编译期报 `ci_callback_acquire requires a direct function reference`），返回 trampoline 或 NULL（池耗尽）；release 成功返回 0、callback 仍在执行返回 `CI_E_BUSY`、指针不属于当前 VM/已释放返回 `CI_E_INVALID_ARGUMENT`。释放后的槽回到可复用集合，旧指针不得再调用；未释放的显式槽在 VM 销毁/plan 重载时退休。
- `ci_callback_pool_stats(total, live, free_slots, retired)` 提供诊断；`ci_vm_callback_error` 记录因 VM 正被另一线程运行而跳过的 dispatch（`CI_E_BUSY`），`ci_vm_clear_error` 一并清除。
- Win32 cdecl/stdcall/fastcall/thiscall callback 支持；stdcall/fastcall/thiscall 使用 `Win32CbFrame.cleanup` 在返回时跳过 callee-owned 栈参数。fastcall trampoline 在入口保存 ECX/EDX，thiscall 保存 ECX；dispatcher 按对应 layout 读取寄存器/栈参数。

#### 7.3.1 Callback 自动槽与显式槽

把 VM 函数直接传给原生函数时，编译器自动生成反向计划并占用一个进程级
trampoline 槽：

```c
void on_event(int x);

native_set_handler(on_event);  // 自动槽；槽随 VM/plan 生命周期退休
```

需要手动控制槽的生命周期时，使用：

```c
typedef int (*sum_cb)(int);

sum_cb cb = (sum_cb)ci_callback_acquire((ci_callback_fn)on_sum);
if (cb != 0) {
    int r = cb(3);             // 原生代码或 VM 都可以调用
    ci_callback_release((ci_callback_fn)cb);  // 成功后指针失效
}
```

约束：

- `ci_callback_acquire` 只接受**直接函数引用**，不能传运行期函数变量；
  可以带 cast。返回 `NULL` 表示 256 个进程级槽已耗尽。
- 自动槽在 VM 销毁/plan 重载时退休，不会在重复运行间泄漏。
- 显式槽在 `ci_callback_release` 成功后回到可复用集合；旧函数指针不得再调用。
- callback 执行期间释放同一槽返回 `CI_E_BUSY`；不属于当前 VM/已释放的指针
  返回 `CI_E_INVALID_ARGUMENT`。
- 另一线程正在运行 VM 时，外部线程发起的 callback 默认 fail-fast，不排队、
  不阻塞；应使用空闲 VM 或同线程 callback。
- callback 的签名由 VM 函数的定义决定；原生调用方必须按相同 ABI 调用。

<a id="ci-native-plan"></a>
#### 7.3.2 `CI_NATIVE_PLAN`：从 dlsym 动态调用 native 函数

`ci_callback_acquire` 解决的是“原生代码调用 VM 函数”。反向场景是 VM 通过
`dlsym` 取得一个原生函数指针并调用它。此时需要先声明函数指针类型的 ABI：

```c
#include <dlfcn.h>

typedef int (*add_t)(int, int);
CI_NATIVE_PLAN(add_t);        // 必须放在文件作用域

int main(void) {
    void *h = dlopen("libfoo.so", RTLD_LAZY | RTLD_LOCAL);
    add_t f = (add_t)dlsym(h, "add");
    add_t f1 = f;
    f(2, 3);                   // 普通函数指针调用
    f1(1, 1);                  // 复制后仍可调用
    return 0;
}
```

语义：

- `CI_NATIVE_PLAN(T)` 生成一个带完整签名的 compile-time stub；编译器把它
  转成 CIPL plan 的 `native` 位（flags bit7），并从 CIPI/全局数据中过滤掉
  stub 和引用符号。
- 带 `native` 位的 plan 允许间接调用任意**非零 host address**；不要求地址
  在 `native_targets` 注册表中。没有该声明的调用仍返回 `BadAddress`。
- 声明是类型级的：`f1 = f; f1()`、重复调用、作为参数传递都使用同一签名计划。
- `dlsym` 返回的**数据指针**不需要 `CI_NATIVE_PLAN`；VM 的 `LOAD_MEM`/
  `STORE_MEM` 接受非零宿主地址。
- `CI_NATIVE_PLAN` 只对通过函数指针的间接调用生效，不改变直接调用的 CIPI
  符号解析。
- 项目不是沙箱：错误的 host address 会直接触发宿主故障；调用者必须保证
  `dlsym` 结果非空、签名匹配，并在 `dlclose` 后不再调用该指针。
- `dlsym(0, "main")` 不应与 VM 的 `&main` 比较：前者是宿主进程地址，后者是
  CIVM 函数索引。该身份映射不在当前支持范围内。
- `CI_NATIVE_PLAN` 要求文件作用域的 typedef 名称，不支持把裸的
  `void (*)(void)` 类型表达式直接作为宏参数。


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

- cdecl/stdcall 参数全部在栈上，4 字节对齐；fastcall 前两个 4 字节标量走 ECX/EDX，thiscall 第一个 4 字节标量走 ECX，其余在栈上；fastcall/thiscall 的栈参数由 callee 清理。
- byval 结构体复制原始字节；sret 隐藏指针在栈首。
- 返回：≤4B EAX；i64 合并为 8B rax loc；float/double 在 ST0；小结构体 EAX:EDX；大结构体 sret。
- `conv` 沿用 CIPL 字节：0=cdecl、1=stdcall、2=fastcall、3=thiscall；thiscall 只支持 Win32 原生/间接调用和 callback。

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
- 运行期解析顺序：宿主 `ci_vm_load_library` → CIPI provider（缓存 handle）→ 进程符号/默认 CRT。自动 provider 只接受库名，拒绝路径分隔符；绝对路径只允许宿主显式加载。直接原生调用目标按 plan index 在首次调用后缓存；包/plan 重载会清空 provider/target 缓存。
- MinGW defs 不含 `min_os`，新包统一写 0，旧包仍按原字段校验；glibc abilists 的 `ld` 库、objects/TLS 段不进入 Linux provider 索引。构建需要 Zig 0.13 自带的 `libc/mingw` 与 `libc/glibc/abilists`，缺失时 `zig build` 直接失败。

## 10. 包格式、C ABI 与上限

### 10.1 包格式

- **CIVM v2**：magic/版本/arch、函数表、代码、入口函数索引；不保存函数名；模块上限 2 MiB，函数上限 512。
- **CIPL v4**：CallPlan 表，计划名通过 CIPC 名称引用；CIPC 头含 data_base。计划上限 1024，每 plan 64 args、8 ret locs、每 arg 8 locs，名称上限 128。
- **CIPKG v4（trusted）**：22 字节头（magic + version + module/plan/import/const 四个 u32 长度）+ CIVM + CIPL + CIPI + CIPC；不写目标元数据，运行时不做目标校验，包必须由匹配的运行时加载。
- **CIPC v2**：名称池 + data（只读 globals、字符串、标量/宽浮点常量、mutable 初始化 chunk 值）；默认用包内随机 16 字节 key XOR `name_blob`/`data`，key 在 CIPC 头内；名称在加载时解密，data 在每次 run 拷贝时整块解密。`cinterp-cc --no-xor-const-pool` 输出明文。mutable globals 镜像仍在 VM 内存 `0..data_base` 由 `main` 安装。XOR 只是防 `strings` 的混淆，key 随包，不构成保密/完整性边界。
- **CIPI v2**：plan index → provider 库/真实符号/ordinal；名称通过 CIPC 引用；上限 512 entry、每 entry 8 provider，名称/符号 64 字节。
- 详细字段和错误码见 [`docs/cib.md`](./docs/cib.md)；版本兼容策略见 [`docs/compatibility.md`](./docs/compatibility.md)。

### 10.2 C ABI

公开头文件 `runtime/include/cinterp.h`；`zig build` 安装可执行文件、静态/共享库和头文件。`CI_ABI_VERSION=2`。多 CIB/线程/callback 扩展全部按 append-only 追加：新增函数、`CI_E_BUSY = -12`，既有签名与数值不变，不提升 ABI 版本。

```c
ci_vm *ci_vm_create(size_t stack_size);
ci_vm *ci_vm_create_ex(const ci_vm_config *config);
void ci_vm_destroy(ci_vm *vm);
int ci_vm_destroy_ex(ci_vm *vm, unsigned flags);          /* CI_DESTROY_TRY */
int ci_vm_load_module(ci_vm *, const uint8_t *, size_t);
/* deprecated for v4: CIPL names live in CIPC; use load_package */
int ci_vm_load_plans(ci_vm *, const uint8_t *, size_t);
int ci_vm_load_package(ci_vm *, const uint8_t *, size_t);
int ci_vm_load_library(ci_vm *, const char *);
int ci_vm_run(ci_vm *, const char *entry);
int ci_vm_run_args(ci_vm *, const char *entry, int argc, const char *const *argv);
int64_t ci_vm_result(const ci_vm *);
int ci_vm_busy(const ci_vm *);
const char *ci_vm_last_error(const ci_vm *);
int ci_vm_last_error_code(const ci_vm *);
int ci_vm_clear_error(ci_vm *vm);
int ci_vm_callback_error(const ci_vm *vm);
void ci_callback_pool_stats(uint32_t *total, uint32_t *live,
                            uint32_t *free_slots, uint32_t *retired);
ci_process *ci_process_create(const ci_vm_config *vm_config);
void ci_process_destroy(ci_process *process);
int ci_process_load_package(ci_process *, const uint8_t *, size_t, ci_vm **out);
int ci_process_unload_package(ci_process *, ci_vm *vm);
const char *ci_process_last_error(const ci_process *);
int ci_process_last_error_code(const ci_process *);
int ci_abi_version(void);
const char *ci_version(void);
```

- 返回 `int` 的接口成功返回 `CI_OK`，失败返回具体负值 `CI_E_*`；`CI_ERROR` (-1) 仅用于无法归类的错误。`CI_E_BUSY = -12` 是 ABI 2 的追加值，用于另一线程正在执行同一 VM、loader 遇到 busy、`CI_DESTROY_TRY` 等场景。
- `ci_vm_last_error_code()` 返回同一类别；`ci_vm_last_error()` 只在 Debug 构建返回具体错误名，Release 构建返回空字符串并仅使用状态码；`ci_vm_clear_error()` 清除两者（以及 callback dispatch 错误）。
- `ci_vm_run`/`ci_vm_run_args` 返回状态而不是 C `main` 返回值；结果用 `ci_vm_result` 读取。另一线程运行中返回 `CI_E_BUSY`，同线程嵌套返回 `CI_E_RUNTIME`。
- loader 是事务性的；失败不会替换已加载包。loader 和 `ci_vm_load_library` 在 VM 执行期间返回 `CI_E_BUSY`。
- `ci_vm_config` 的 `struct_size` 兼容旧调用方；`stack_size=0` 使用默认 8192 槽，`memory_size=0` 使用默认 1 MiB（最大 16 MiB）。
- 每个 VM 单执行上下文；不同 VM 可在不同线程并行。`ci_vm_busy` 查询状态，`ci_vm_destroy` 等待空闲，`ci_vm_destroy_ex(vm, CI_DESTROY_TRY)` 在另一线程运行期间立即返回 `CI_E_BUSY`。
- `ci_process_*` 是进程级注册表：每个 `ci_process_load_package` 创建独立 VM，返回的句柄是借出的，必须用 `ci_process_unload_package` 释放；busy VM 上的卸载和 `ci_process_destroy` 返回 `CI_E_BUSY`，宿主 join 线程后重试。

### 10.3 运行时上限

`MAX_FUNCS=512`、`MAX_FRAMES=512`、`MAX_STACK=8192`、`MAX_MODULE=2 MiB`、`MAX_PLANS=1024`、`MAX_ARGS=64`、`MAX_LOCS=8`、`MAX_NAME=128`、`MAX_IMPORTS=512`、`MAX_PROVIDERS=8`；编译期还会拒绝 `local_count > 8192` 和 `data_base + const_data > 16 MiB`，避免生成运行时必然 OOM 的包。native target 注册表 256，超出返回 `TooManyNativeTargets`。进程级 `MAX_PROCESS_VMS=64`，超出返回 `ProcessFull`（`CI_E_RESOURCE`）。callback trampoline 池固定 256 个进程级静态槽。

## 11. 目录与关键文件

```text
compiler/
  build.zig                    # 构建期运行 gen_link_index
  tools/gen_link_index.zig     # MinGW defs / glibc abilists → 内嵌索引
  src/main.zig                 # CLI、CIPKG/CIPC writer、validateLimits
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
  src/ffi/link_loader.zig      # CIPI 解析与校验
  src/ffi/native.zig           # dlopen/LoadLibrary 符号解析
  src/ffi/platform.zig         # ABI 选择、frame、marshal、invoke、validate
  src/ffi/asm/                 # 四个调用引擎 + 四个 callback trampoline
  tests/                       # C API smoke/argv/fuzz host

examples/                      # 按类别：basics/、ffi/、linux/、windows/、bof/
                               # windows 示例直接 include <windows.h>
docs/                          # 格式、嵌入、多 CIB/线程、兼容性、IR 子集、Zig 前端
packaging/                     # pkg-config、CMake、Rust binding、release README
scripts/                       # tools/、test/、fuzz/、release/；索引见 scripts/README.md
tests/                         # csuite、manifests、known failures
```

## 12. 构建、测试与发布

```bash
make compiler runtime
make test                 # runtime + compiler 单测、端到端、错误路径、C API
make c-testsuite          # 本地 18 例
make lint                 # civm_lint.py 校验包结构
make differential         # native vs cinterp 返回值
make test-suites-smoke    # csuite 18/18
make test-suites          # standard
make test-suites-full     # full
make test-suites-nightly  # nightly + 100-seed 生成式差分
make fuzz                 # load-only 变异
make fuzz-exec            # 执行变异；崩溃失败，变异无限循环超时计数并保存
make fuzz-bytecode        # 结构化 CIVM 变异
make fuzz-ffi-exec
make fuzz-capi-asan
make fuzz-sanitizer
make bench                 # 本机进程级基准，输出 build/benchmark.json
make size                  # Runtime ReleaseSmall 体积
make size-cross           # 四个目标体积
make test-winapi          # Windows <windows.h> 示例（Wine）
make test-suites-cross    # Win64/Win32/ARM64 交叉套件
make release-artifacts    # tarball + SBOM + SHA256SUMS
make evidence             # test/lint/size/smoke/differential + checker
make check-version        # VERSION 单一来源校验
```

### 12.0 性能基准

`make bench` 在当前主机上编译并预热 7 个示例，再为每个示例记录 20 次独立
`cinterp-run` 进程的耗时，结果写入 `build/benchmark.json`。当前 native Linux x64
ReleaseSmall 基线约为 **5.25–5.51 ms/run**（median；mean 5.27–5.61 ms，当前
`build/benchmark.json` 采样）；这个数字包含进程启动、包加载和一次执行，
适合做同一机器上的前后回归比较，不是纯 VM 指令吞吐。

### 12.1 命令行与构建选项

编译器：

```bash
./build/cinterp-cc compile source.c -o out.cib \
  [--dump] [--dump-ast] [--dump-imports] [--keep-ir] [--target TARGET] \
  [--cc zig] [--cc-path PATH] [--cc-flag FLAG]... [--no-auto-link]
```

`--dump` 打印函数和 FFI 计划（包括 `conv`）；`--dump-ast` 打印解析后的 typed AST；
`--dump-imports` 打印 CIB provider 绑定；`--keep-ir` 保留生成的 LLVM IR。
`--cc-path` 选择作为 C 前端的 `zig`，`--cc` 目前只接受 `zig`；输出固定为 CIPKG v4 trusted 包，`--no-auto-link` 关闭 C 标准库/Windows API 自动绑定。
目标为 `x86_64-linux`（默认）、`x86_64-windows`、`i686-windows`、`aarch64-linux`。
Windows 目标使用 Zig 自带的 MinGW 头文件，可用 `ZIG_LIB_DIR` 覆盖；Windows exe 使用
`WinStartup`/TLS 入口而不链接 MinGW CRT，静态库/共享库仍保留 CRT。

运行时：

```bash
./runtime/zig-out/bin/cinterp-run <package.cib> [-- arg...]
```

单包、单次运行输出一行 `result: <i32>`；`--` 后的参数进入 C `argv[1..]`，包路径是
`argv[0]`。用户库、重复运行、多 VM 和仅加载校验只通过 C API 使用。成功退出码 0，
加载/运行失败 1，用法或 I/O 错误 2；C `main` 的返回值只通过 `result:` 输出。

构建配置：`Debug`/`ReleaseSafe` 保留完整诊断、unwind 表、帧指针和 panic 栈回溯；
`ReleaseSmall`（`make runtime` 的默认值）剥离 unwind 表、帧指针、panic 跟踪和符号，
ELF 发布产物还会去掉 `.eh_frame`/`.eh_frame_hdr`。错误名表仅 Debug 构建保留；
ReleaseSafe/ReleaseSmall/ReleaseFast 只用 `CI_E_*` 状态码表示错误。ReleaseSmall
运行时约 100 KiB；Debug 构建保留诊断信息，体积更大。详细 post-link 处理见下文。

### 12.2 当前基线

- `make test-suites-full`：**4331/4522 通过，191 skip**；当前 skip 全部为 `unsupported`，没有 `known-failure`。
- 通过用例中 gcc-torture-compile 1403 + llvm-regression-c 933 + compcert-compile 30 = 2366 个是仅编译（另有 llvm-singlesource 85 个也是 `mode: compile`，所有编译模式合计 2451）；可执行基线是其余 1880 个通过用例。
- `make test-suites` / `make test-suites-nightly` 的数字随 manifest 和当次 report 变化；请以对应 `build/test-suites*.json` 为准，不在本文固定易漂移的总数。
- 最近一次 nightly 的已知结果：YARPGen 100 seeds 为 93 通过 / 7 skip / 0 failure；nightly 固定 suite 的通过/跳过数以当次 report 为准。
- 并发：`test_suites.py --jobs` 默认 CPU 核数，且所有选中 suite 共用一个全局 worker 池；`SUITE_JOBS` 可覆盖。nightly 由 `scripts/test/test_nightly.sh` 并行执行 suite 与 `generate_diff`，`GEN_JOBS`/`MINIMIZE_JOBS` 控制差分并发，日志为 `build/nightly-suite.log` 和 `build/nightly-diff.log`；顺序模式为 `make test-suites-nightly-serial`，`NIGHTLY_MINIMIZE=0` 跳过最小化。
- `scripts/test/test_cross.sh`：62 个示例用例（Win64 20 / Win32 23 / ARM64 19），Wine、真实 Windows 和 qemu 均可运行；`make test-winapi` 另外在 Win64/Win32 下运行 4 个 `<windows.h>` 示例（共 8 次）。
- 多 CIB/线程：`scripts/test/test.sh` 覆盖 `runtime/tests/capi_multi.c`（静态/共享链接、3 个 VM 并行、busy 语义）；重复 callback 运行由 C API 测试承担。
- 本地 c-testsuite 18/18；上游 manifest 为 218/2，独立脚本默认旧 skip 列表为 217/3（`00189` 已可通过），引用时需注明来源。
- ReleaseSmall：native Linux x64 及各交叉目标约 100 KiB，低于默认 size budget（可用 `SIZE_BUDGET` 覆盖）。Windows 可执行文件使用 Zig 的 `WinStartup`/TLS 入口，不链接 MinGW CRT；静态库/共享库仍保留 CRT。PE 运行时通过汇编 `.drectve` 合并 `.rdata` 到 `.text`；`size-cross`/release 再 post-link 调用 `scripts/release/strip_runtime.sh`：ELF 删除 `.eh_frame*`，PE 删除 `.eh_fram`。ReleaseSafe/ReleaseSmall/ReleaseFast 不保留 Zig 错误名表，错误只通过 `CI_E_*` 状态码表达；Debug 构建保留错误名并输出到 stderr。

### 12.3 发布压缩包

`make release-artifacts` 会把四个目标压缩包写入 `build/release/`，并生成每个目标的
SPDX SBOM 和 `SHA256SUMS`。CI 在打包后用 Sigstore keyless 签名 `SHA256SUMS`，
产出 `SHA256SUMS.sigstore.json`（无需 GPG 密钥）：

| 压缩包 | 内容 |
| --- | --- |
| `cinterp-<version>-sysv-x86_64` | 编译器 + 运行时，Linux x86-64（`bin/cinterp-cc`、`bin/cinterp`） |
| `cinterp-<version>-win64-x86_64` | 仅运行时，Windows x64 |
| `cinterp-<version>-win32-x86` | 仅运行时，Windows x86 |
| `cinterp-<version>-arm64` | 仅运行时，Linux AArch64 |

只有 Linux x86-64 压缩包包含 `bin/cinterp-cc`；另外三个包含运行时、头文件、
pkg-config/CMake 元数据和 Rust 绑定。每个压缩包的 `README.md` 由
[`packaging/README.release.md.in`](./packaging/README.release.md.in) 渲染。
`THIRD_PARTY_NOTICES.md` 只随编译器压缩包发布；runtime-only 包不携带派生符号索引。

### 12.4 验证与证据

运行时在调用原生代码前校验包长度、ABI id、CIPI 的
plan/provider 引用、函数/plan 数量、plan 参数数量、ABI 位置索引以及 marshal 偏移/大小；
格式错误的包会干净地失败。C API `ci_vm_load_package` 可在不执行包的情况下校验包，`make fuzz` 对种子包
做变异/截断并检查崩溃。自动 provider 只接受库名，不接受路径；指向原生分配内存的 C 指针
属于受信任边界，不可信包应由宿主隔离。

`scripts/tools/check_plan_evidence.py` 读取结构化产物（`build/test-suites*.json`、
`build/generate-diff-nightly.json`、`build/release/*.tar.gz`、`SHA256SUMS` 和各交叉运行时），
不依赖文本日志。`make evidence` 会生成本地子集并运行 checker；完整、交叉和 nightly 报告在
本地报告为 "not provided"，由 CI 产物补齐。

## 13. 当前边界与明确不支持

- **平台**：仅 Linux x86-64/AArch64（glibc）与 Windows x64/x86；不提供 macOS、musl、Windows ARM64、Linux i386/ARM32。
- **C/ABI**：`_Complex`、GCC builtins、外部 inline/weak 语义、Win64 `__vectorcall`/COM、SysV `i128`/向量参数、向量类型、内联汇编、`_Atomic`/`_Thread_local` 不支持。
- **链接**：不支持 CIB-to-CIB 链接、包间导出/依赖；跨包复用需合并源码后重新生成 CIB，或由宿主通过 `ci_vm_load_library` 加载普通共享库。
- **执行模型**：一个 VM 单执行上下文、单 CIB；进程可通过 `ci_process_*` 持有最多 64 个 VM，不同 VM 可并行。无进程内沙箱、无 Safe 模式；不可信输入由宿主隔离。
- **Windows CRT**：`%Lf` 行为与原生 MinGW 一致，不额外提供格式化 shim；`examples/ffi/ffi_printf_longdouble.c` 只锁定 smoke 行为。
- **外部数据符号**：基础 provider（`stdout`/`errno`/`environ`/`stdin`/`tzname`/`opt*`、Windows `_environ`/`_fmode`/`_tzname` 等）已支持；Windows UCRT 的 `_errno`/`__acrt_iob_func`/`__p__environ` 是函数计划。更冷门的数据符号走 provider/fallback。

## 14. 已知限制与后续方向

- **FFI 返回块生命周期**：宽值/多 loc 返回值现在按调用从调用方 VM 线性内存分配，存活到当前帧返回；不再共享 `ret_buf`。长循环中大量宽返回会按 `ret_size` 增长，最终受线性内存上限约束（与 f80/f128 临时值一致）。VM→VM 寄存器返回聚合仍依赖 callee 内存未被改写，属于后续独立 ownership 工作。
- **Win32 `thiscall` 支持范围**：原生/间接调用和 callback 均支持；第一个 4 字节标量（`this`）走 ECX，其余走 callee 清理的栈。Win64 的 `__vectorcall`/COM 仍不支持。
- **原生库句柄不卸载**：`ci_vm_load_library` 与 CIPI provider 的 `dlopen`/`LoadLibrary` 句柄随进程保留，没有 `dlclose`/`FreeLibrary`；长期多包宿主应自建进程边界。
- **宿主堆、atexit/signal 与全局初始化**：`malloc` 等宿主堆分配跨 run 累积，不随 VM 线性内存重置；`atexit`/`signal` 是进程全局状态，多 VM/重复运行共享；全局安装代码只出现在 `main`，运行时也只接受 `main` 入口。
- **callback 槽位**：固定 256 个进程级静态槽。自动 `CREATE_CALLBACK` 槽在 VM 销毁/plan 重载前一直占用（跨 run 复用）；显式 `ci_callback_acquire` 槽在 release 后回到可复用集合，未 release 的显式槽随 VM 销毁/重载退休。自动槽耗尽后返回 `TooManyCallbacks`。
- **外部线程异步 callback**：VM 正在运行时，另一线程调用的 callback 默认 fail-fast（非 sret 返回值置零、sret 缓冲区不变，并记录 `CI_E_BUSY`），不排队、不阻塞；`libc-test/pthread_tsd` 因此显式 skip。需要异步回调的库应在 VM 空闲时调用，或改成同步 callback 设计。
- **生成式差分**：YARPGen whitelist 已清空；nightly 的 7 个 skip 是 native 拒绝/超时或 `compiler limit:` 引擎上限。Csmith 仍有 3 条 known failure；报告保留 stale 检测，whitelist 条目开始通过会失败。

### 14.1 暂缓的大功能（第 5 项）

以下均**暂缓**，不进入当前批次，也不代表版本承诺；需要时按实际场景单独设计、评审和拆分：

- **CIB-to-CIB 链接**：包间导出/依赖、跨包函数调用、版本/ABI 匹配；需要改 CIPKG/CIPI 模型和加载顺序。
- **Win64 `__vectorcall`/COM**：`__vectorcall` ABI 分类、寄存器/栈布局、callback，以及 COM vtable/`this` 调用路径。
- **SysV `i128`/向量参数**：AMD64 SysV 的 128 位整数和向量参数分类、传递与返回。
- **向量类型/向量算术**：元素操作、shuffle、比较和算术；当前只把向量当数据块搬运。
- **`_Complex`**：复数类型、算术、FFI ABI 以及全局初始化器。
- **`_Atomic` / `_Thread_local`**：原子 load/store/RMW、内存序，以及每线程/每 VM 的 TLS 语义。
- **原生库卸载**：`dlclose`/`FreeLibrary`、按包/VM 的句柄引用计数，以及卸载与仍存活的函数指针之间的关系。
- **宿主堆生命周期**：跨 run 的 `malloc` 累积、宿主分配跟踪/释放策略；`atexit`/`signal` 目前仍是进程全局状态。
- **进程内沙箱 / Safe 模式**：不可信 CIB 的隔离；如果要支持，还需配套包校验/签名和资源限额。
- **平台扩展**：macOS、musl、Windows ARM64、Linux i386/ARM32；当前这些平台在编译或加载阶段显式拒绝。

### 14.2 已完成项留下的尾巴

- **VM→VM 寄存器聚合返回 ownership**：FFI 宽/多 loc 返回值已改为调用方 VM 临时块，但 VM 内部函数返回的寄存器聚合仍只是指向 callee 线性内存的指针，依赖该区域在下一次分配前未被改写。需要时再单独设计调用点复制或 hidden return pointer 协议。
- **精确 Windows `%Lf` shim**：本轮 `examples/ffi/ffi_printf_longdouble.c` 只锁定当前 MinGW/CRT 的 smoke 行为，没有实现 80-bit `long double` 的精确格式化层。
- **更多 external data / 跨 ABI 执行 fuzz**：继续按真实用例扩充 provider；跨 ABI fuzz 目前以 load-only 为主，执行级 fuzz 仍是后续方向。

后续工作仍遵守现有约束：不以放宽运行时上限、修改 expected 或跳过失败用例的方式“修复”。

## 15. 参考资料

- chibicc / c-testsuite：C 测试用例和编译器结构参考。
- LLVM IR 指令语义与 clang `-O0` 输出模式。
- System V AMD64、Microsoft x64/x86 调用约定、AArch64 AAPCS64。
- libffi / dyncall：ABI 分类和栈布局参考（不引入依赖）。
- [`docs/multi-cib.md`](./docs/multi-cib.md)：进程/VM 模型、每 VM 线程和 callback acquire/release 的完整说明；CLI 只运行单包一次。
