# cinterp — 带直接 C FFI 的小型 C 字节码解释器

## 1. 简介

`cinterp` 在构建期把 C 源码编译成紧凑的栈式字节码和 FFI 调用计划，运行时用一个
小型 Zig VM 执行。原生调用由固定汇编 ABI 引擎完成，不使用 libffi，也不生成 JIT
或可执行内存。

- **编译器**：Zig + `zig cc`，支持 C17 常用子集、结构体 FFI、varargs 和 callback。
- **运行时**：Zig 0.13，栈式 VM + 线性内存；提供 `cinterp-run` 和 C 嵌入库。
- **目标平台**：Linux x86-64、Linux AArch64、Windows x86-64、Windows x86。
- **包格式**：`CIPKG` v3（trusted），只包含字节码、FFI 计划和链接元数据。

## 2. 特性

1. **不需要动态申请可执行内存**：VM 和固定汇编 ABI 引擎不生成 JIT/stub 代码，callback
   使用进程级静态 trampoline 池。
2. **支持 FFI 和 callback**：编译期生成调用计划，支持结构体、varargs，以及
   cdecl/stdcall/fastcall/thiscall 和 AArch64 AAPCS64 上的原生调用与 callback。
3. **运行时紧凑，约 100 KiB**（ReleaseSmall）：
   1. Linux x86-64（native）：103,952 B ≈ 102 KiB
   2. Linux x86-64（static SysV）：93,152 B ≈ 91 KiB
   3. Windows x86-64：81,408 B ≈ 80 KiB
   4. Windows x86：87,040 B ≈ 85 KiB
   5. Linux AArch64：103,456 B ≈ 101 KiB

4. **可用于替代 BOF 场景**：直接编译普通 C 源文件（包括直接 `#include <windows.h>`），
   不再需要手动声明 WinAPI 函数原型。参见 [`examples/bof`](examples/bof/) 和
   [`examples/windows`](examples/windows/)。

## 3. 原理（编译 → 执行）

```text
C 源码
  → cinterp-cc（构建期）
       → zig cc -S -emit-llvm -O0
       → typed LLVM IR parser / AST / 子集校验
       → CIVM 字节码 + CIPL FFI 调用计划
       → CIPKG v3（CIVM + CIPL + CIPI）

CIPKG
  → cinterp-run / libcinterp（运行时）
       → 事务性加载与目标校验
       → 栈式 VM + 线性内存
       → 固定汇编 ABI 引擎 → 原生函数 / callback
```

- 编译期知道完整的 C 函数签名，提前生成寄存器、栈和 sret 布局；运行时只按计划搬运参数。
- 原生符号通过 CIPI provider、显式 `--lib` 或进程/CRT 回退解析。
- callback 使用进程级静态 trampoline 池，不生成可执行内存。
- 一个 VM 一次持有一个 CIB；同一进程可通过 `ci_process_*` 持有多个 VM 并行运行。

## 4. 现状

### 4.1 测试覆盖情况

- `make test` 覆盖运行时/编译器单元测试、全部示例、C 嵌入 API（静态库和共享库）以及
  损坏包、未知符号、目标不匹配等负向路径。
- 完整上游 manifest 基线：**4318/4521 通过，203 跳过**；标准层级为 395/495。通过用例中
  约 55% 是仅编译检查，详细统计见 [`dev.md` §12](./dev.md#12-构建测试与发布)。
- 本地 c-testsuite 17/17；上游 c-testsuite manifest 为 218 通过 / 2 跳过。
- 交叉测试覆盖 Win64、Win32 和 ARM64，共 62 个示例；Windows 目标通过 Wine 运行。
  `make test-winapi` 会运行全部 Windows `<windows.h>` 示例。
- 另有 `make differential`、fuzz（loader/执行/字节码/FFI/sanitizer）和结构化报告校验
  （`make evidence`）。

### 4.2 不支持的特性

- **平台**：macOS、musl、Windows ARM64、Linux i386/ARM32。
- **C/ABI**：向量类型和向量参数、`_Complex`、Win64 `__vectorcall`/COM、SysV `i128`、
  内联汇编、`_Atomic`/`_Thread_local`，以及 GCC builtin 和外部 inline/weak 语义。
- **链接**：不支持 CIB 到 CIB 的链接或包间导出/依赖；跨包复用需合并源码重新生成 CIB，
  或通过 `--lib` 调用普通共享库。
- **执行模型**：一个 VM 一次执行一个 CIB，不提供进程内沙箱；不可信包应由宿主隔离运行。
- **Windows CRT**：`long double` 的 `%Lf` 输出沿用本机 MinGW/CRT 行为，不提供精确格式化 shim。

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

# FFI：加载一个用户共享库
cc -shared -fPIC -O0 examples/ffi/ffi_structs_helper.c -o build/libstruct_helpers.so
./build/cinterp-cc compile examples/ffi/ffi_structs.c -o build/ffi_structs.cib
./runtime/zig-out/bin/cinterp-run --lib build/libstruct_helpers.so build/ffi_structs.cib
# result: 28
```

常用运行选项：

```bash
# 同一 VM 重复运行，每次使用全新镜像
./runtime/zig-out/bin/cinterp-run --repeat 3 build/hello.cib

# 每个包一个 VM；--jobs 并行运行不同 VM
./runtime/zig-out/bin/cinterp-run --run-all --jobs 2 build/hello.cib build/hello.cib

# 只加载校验，不执行
./runtime/zig-out/bin/cinterp-run --load-only build/hello.cib
```

`cinterp-run` 成功退出码为 0，加载/运行失败为 1，用法或 I/O 错误为 2；C `main` 的返回值
以 `result: N` 输出，不充当进程退出码。完整 CLI 参数见 `cinterp-cc --help` /
`cinterp-run --help`。

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
make c-testsuite        # 本地 17 个 C 子集用例
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
- [`examples/README.md`](examples/README.md) — 分类示例索引
- [`tests/manifests/README.md`](tests/manifests/README.md) — 测试套件 manifest 和跳过策略
