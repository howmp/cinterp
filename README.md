# cinterp — 带直接 C FFI 的小型 C 字节码解释器

## 1. 简介

`cinterp` 在构建期把 C 源码编译成紧凑的栈式字节码和 FFI 调用计划，运行时用一个
小型 Zig VM 执行。原生调用由固定汇编 ABI 引擎完成，不使用 libffi，也不生成 JIT
或可执行内存。

- **编译器**：Zig + `zig cc`，支持 C17 常用子集、结构体 FFI、varargs 和 callback。
- **运行时**：Zig 0.13，栈式 VM + 线性内存；提供 `cinterp-run` 和 C 嵌入库。
- **目标平台**：Linux x86-64、Linux AArch64、Windows x86-64、Windows x86。
- **包格式**：`CIPKG` v4（trusted），由 CIVM v3、CIPL、CIPI 和 CIPC 常量/字符串池组成。
  0.1.7 已发布，但仍不保证 CIB 格式兼容，可能随实现直接调整。

## 2. 特性

1. **不需要动态申请可执行内存**：VM 和固定汇编 ABI 引擎不生成 JIT/stub 代码，callback
   使用进程级固定 256 槽的静态 trampoline 池。自动 callback 槽在 VM 销毁/计划重载时永久退休，
   显式 `ci_callback_acquire`/`ci_callback_release` 槽可复用；这是进程级硬上限。
2. **支持 FFI 和 callback**：编译期生成调用计划，支持结构体、varargs，以及
   cdecl/stdcall/fastcall/thiscall 和 AArch64 AAPCS64 上的原生调用与 callback；
   `CI_NATIVE_PLAN(T)` 可为 dlsym 等动态函数指针声明可调用的 native 计划；
   用法见 [`dev.md`](dev.md#ci-native-plan)。
3. **运行时紧凑，约 100 KiB**（ReleaseSmall，各目标略有差异）。

4. **可用于替代 BOF 场景**：直接编译普通 C 源文件（包括直接 `#include <windows.h>`），
   不再需要手动声明 WinAPI 函数原型。参见 [`examples/bof`](examples/bof/) 和
   [`examples/windows`](examples/windows/)。
5. **CIPC 常量/名称池默认 XOR 混淆**：编译时使用每包随机 16 字节 key，运行时加载时解密
   名称池、每次 run 时解密 data；`cinterp-cc --no-xor-const-pool` 可输出明文以便调试。
   key 随包分发，只用于避免 `strings` 直接读出字符串，不是安全/完整性边界。

## 3. 原理（编译 → 执行）

```text
C 源码
  → cinterp-cc（构建期）
       → zig cc -S -emit-llvm -O2
       → typed LLVM IR parser / AST / 子集校验
       → CIVM 字节码 + CIPL FFI 调用计划 + CIPC 常量/名称池
       → CIPKG v4（CIVM + CIPL + CIPI + CIPC）

CIPKG
  → cinterp-run / libcinterp（运行时）
       → 事务性加载与 CIPC/计划/导入校验
       → 栈式 VM + 线性内存
       → 固定汇编 ABI 引擎 → 原生函数 / callback
```

- 编译期知道完整的 C 函数签名，提前生成寄存器、栈和 sret 布局；运行时只按计划搬运参数。
- 原生符号通过 CIPI provider、宿主 C API `ci_vm_load_library` 或进程/CRT 回退解析。
- callback 使用进程级静态 trampoline 池，不生成可执行内存。
- 一个 VM 一次持有一个 CIB；同一进程可通过 `ci_process_*` 持有多个 VM 并行运行。

## 4. 现状

### 4.1 测试覆盖情况

- `make test` 覆盖运行时/编译器单元测试、全部示例、C 嵌入 API（静态库和共享库）以及
  损坏包、未知符号、目标不匹配等负向路径。
- 完整上游 manifest 基线：**4331/4522 通过，191 跳过**。通过用例中约 57% 是仅编译
  检查，详细统计见 [`dev.md` §12](./dev.md#12-构建测试与发布)。
- 本地 c-testsuite 18/18；上游 c-testsuite manifest 为 218 通过 / 2 跳过。
- 交叉测试覆盖 Win64、Win32 和 ARM64，共 62 个示例；Windows 目标通过 Wine 运行。
  `make test-winapi` 会运行全部 Windows `<windows.h>` 示例。
- 另有 `make differential`、fuzz（loader/执行/字节码/FFI/sanitizer）和结构化报告校验
  （`make evidence`）。

### 4.2 不支持的特性

- **平台**：macOS、musl、Windows ARM64、Linux i386/ARM32。
- **C/ABI**：向量类型和向量参数、`_Complex`、Win64 `__vectorcall`/COM、SysV `i128`、
  内联汇编、`_Atomic`/`_Thread_local`，以及 GCC builtin 和外部 inline/weak 语义。
- **链接**：不支持 CIB 到 CIB 的链接或包间导出/依赖；跨包复用需合并源码重新生成 CIB，
  或由宿主通过 `ci_vm_load_library` 加载普通共享库。
- **执行模型**：一个 VM 一次执行一个 CIB；运行时不为 CIB 提供进程内沙箱。
- **F80/F128**：`long double` / `__float128` 不再支持；编译器在 IR 类型解析阶段直接报错。

### 4.3 安全与资源边界（非目标）

- **不做沙箱、不做隔离**：CIB 可以通过 FFI 调用宿主可见的原生函数和库；运行时不在进程内限制文件、网络、进程、权限或库加载。CIB 是构建产物，安全等价于原生 C 代码，只能运行可信包。
- **不做执行超时/取消/抢占**：没有 deadline、cancel 或 opcode/指令配额；运行线程的生命周期由宿主管理。
- **不做宿主内存限额/内存配额**：`ci_vm_config.memory_size` 只控制 VM 线性内存容量，不是宿主分配或原生 FFI 的安全限额，也不构成不可信包的内存隔离。
- **不保证 CIB 格式兼容**：0.1.7 已发布，但格式仍可能随实现调整；不维护旧格式读取、迁移或兼容层。

完整的 ABI 边界、暂缓功能和已知限制见 [`dev.md` §13/§14](./dev.md#13-当前边界与明确不支持)。

## 5. 用法

环境要求：Zig 0.13；测试、fuzz 和基准脚本还需要 Python 3.10+。

### 构建

```bash
make compiler runtime
```

`make runtime` 默认生成 ReleaseSmall 运行时；`make debug-runtime` 生成带完整诊断信息的版本。

### 编译和运行

```bash
./build/cinterp-cc compile examples/basics/hello.c -o build/hello.cib
./runtime/zig-out/bin/cinterp-run build/hello.cib
# result: 42

# 传递 C argv：包路径是 argv[0]，-- 后是 argv[1..]
./runtime/zig-out/bin/cinterp-run build/capi_argv.cib -- x 7
# result: 7
```

`cinterp-run` 只接受 `<package.cib> [-- arg...]`：单包、单次运行，参数必须放在 `--`
之后。用户共享库、重复运行、多 VM/并行和仅加载校验由 C API
（`ci_vm_load_library`/`ci_vm_run*`/`ci_vm_load_package`）承担。

成功退出码为 0，加载/运行失败为 1，用法或 I/O 错误为 2；C `main` 的返回值以
`result: N` 输出，不充当进程退出码。

### 交叉编译

```bash
./build/cinterp-cc compile examples/basics/hello.c \
  --target x86_64-windows -o build/hello-win64.cib
cd runtime && zig build -Dtarget=x86_64-windows-gnu && cd ..

make test-winapi   # 通过 Wine 运行 Windows 示例
```

支持的目标：`x86_64-linux`（默认）、`aarch64-linux`、`x86_64-windows`、`i686-windows`。

### 测试和发布

```bash
make test               # 单元测试、示例、C API、负向路径
make c-testsuite        # 本地 18 个 C 子集用例
make test-suites-smoke  # 快速上游套件
make test-suites-full   # 完整上游套件
make test-winapi        # Windows 示例（Wine）
make release-artifacts  # tarball + SBOM + SHA256SUMS
```

C 嵌入 API、错误码和链接方式见 [`docs/embedding.md`](docs/embedding.md)。

## 6. 文档引用

- [`dev.md`](dev.md) — 架构、实现决策、ABI、构建/测试/发布细节和已知限制
- [`docs/README.md`](docs/README.md) — 文档索引
- [`docs/cib.md`](docs/cib.md) — CIB 包格式、字节码、FFI 计划和链接元数据
- [`docs/embedding.md`](docs/embedding.md) — C 宿主嵌入和 `ci_vm_*` API
- [`docs/multi-cib.md`](docs/multi-cib.md) — 多 CIB、重复运行、线程和 callback 生命周期
- [`docs/compatibility.md`](docs/compatibility.md) — 版本、ABI 和兼容性策略
- [`docs/ir-subset.md`](docs/ir-subset.md) — 支持的 LLVM IR 子集
- [`docs/zig-frontend.md`](docs/zig-frontend.md) — `zig cc` 前端和编译器 CLI 契约
- [`docs/ir-parser-differences.md`](docs/ir-parser-differences.md) — IR 前端回归和历史差异
- [`docs/unsupported-cases.md`](docs/unsupported-cases.md) — 当前 191 个 unsupported 用例及原因
- [`scripts/tools/cib_dump.py`](scripts/tools/cib_dump.py) — CIB 头信息与 CIVM 反汇编工具
- [`examples/README.md`](examples/README.md) — 分类示例索引
- [`tests/manifests/README.md`](tests/manifests/README.md) — 测试套件 manifest 和跳过策略
