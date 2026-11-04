# cinterp — 带直接 C FFI 的小型 C 字节码解释器

`cinterp` 在构建期把 C 编译成一个紧凑的栈式字节码模块，外加编译期的 FFI 计划，
然后在一个小型 Zig VM 中执行。原生调用经由固定的汇编 ABI 引擎完成；不使用 libffi，
没有 `@call` stub 矩阵，也没有运行时代码生成 / 可执行内存。

- **编译器**（Zig，构建期）：调用 `zig cc -S -emit-llvm -O0`，把 LLVM IR 文本一次性
  解析为带类型标注的 AST 并通过子集校验器校验，然后将其降低为 CIVM 字节码、FFI `CallPlan`
  表（`src/abi.zig`），以及带有目标元数据（`CIPM`）和外部符号链接元数据（`CIPI`）的
  `CIPKG` v2 包。AST 是唯一的 IR 前端；原先的字符串解析器和最初的 Python 编译器已被
  移除。Python 仅用于测试、fuzz 和基准测试框架；外部符号链接元数据在构建期从已安装的
  Zig 工具链生成（见下文）。
- **运行时**（Zig 0.13）：带线性内存的栈式 VM、C ABI（`ci_vm_*`）、编译期 ABI 选择、
  面向 SysV x86-64、Win64、Win32 cdecl/stdcall/fastcall 和 AArch64 AAPCS64 的固定汇编
  引擎、原生符号解析（Unix 上的 `dlopen`/`dlsym`，Windows 上的
  `LoadLibraryA`/`GetProcAddress`）、从 `CIPI` 自动加载 provider，以及每个 ABI 上的静态
  回调池。
- **目标平台**：Linux x64、Windows x64、Windows x86、Linux AArch64。用编译器的
  `--target` 和运行时的 `-Dtarget` 构建。

## 快速开始

环境要求：Zig 0.13（运行时和 `zig cc` 前端），另外仅测试/fuzz/基准测试框架需要
Python 3.10+。

```bash
# build the Zig compiler and release runtime
make compiler runtime

# compile and run a C file
./build/cinterp-cc compile examples/hello.c -o build/hello.cib
./runtime/zig-out/bin/cinterp-run build/hello.cib
# result: 42

./build/cinterp-cc compile examples/ffi_printf.c -o build/printf.cib
./runtime/zig-out/bin/cinterp-run build/printf.cib
# 7 2.5
# result: 0

# struct byval + sret FFI through a user shared library
cc -shared -fPIC -O0 examples/ffi_structs_helper.c -o build/libstruct_helpers.so
./build/cinterp-cc compile examples/ffi_structs.c -o build/ffi_structs.cib
./runtime/zig-out/bin/cinterp-run --lib build/libstruct_helpers.so build/ffi_structs.cib
# result: 28

# inspect target/import metadata
./runtime/zig-out/bin/cinterp-run --dump-target --dump-imports --load-only build/printf.cib

# versions
./build/cinterp-cc --version
./runtime/zig-out/bin/cinterp-run --version

# cross-target packages (build the runtime with the matching -Dtarget)
./build/cinterp-cc compile examples/hello.c \
  --target x86_64-windows -o build/hello-win64.cib
cd runtime && zig build -Dtarget=x86_64-windows-gnu && cd ..
# make cross-test        # Win64/Win32 (Wine or native Windows) + ARM64 (qemu)
# optional remote runner: HOST=user@windows-box REMOTE='C:/tmp/cinterp/' make cross-test

# local C subset suite: 17 cases in tests/csuite
make c-testsuite

# upstream c-testsuite supported set (see "C test suites" for the skip list)
git clone --depth 1 https://github.com/c-testsuite/c-testsuite /tmp/c-testsuite
python3 scripts/c_testsuite_upstream.py --dir /tmp/c-testsuite/tests/single-exec

# full local test suite (runtime + compiler unit tests, examples, error paths)
make test

# plan evidence from the structured build reports, and version consistency
make evidence
make check-version

# release-size check (runtime < 128K, qsort package < 4K)
make release-check

# fuzz: loader, execution, structured bytecode, FFI, sanitizer, and cross-ABI
make fuzz
make fuzz-exec
make fuzz-bytecode
make fuzz-ffi-exec
make fuzz-capi-asan
make fuzz-sanitizer
make fuzz-cross

# native-vs-cinterp differential check
make differential

# benchmarks and per-target size budgets
make bench
make size-cross

# release tarballs (LICENSE, SBOM, split debug, pkg-config/CMake/Rust bindings),
# SHA256SUMS and optional GPG signature
make release-artifacts
```

构建配置：

- `-Doptimize=Debug` / `-Doptimize=ReleaseSafe`：完整的诊断信息、unwind 表、帧指针和
  panic 栈回溯。
- `-Doptimize=ReleaseSmall`（`make runtime` 的默认值）：剥离 unwind 表、帧指针、panic
  跟踪和符号；ELF 发布产物还会额外去掉 `.eh_frame`/`.eh_frame_hdr`。简洁的错误码和 CLI
  消息仍然保留。
- 当前体积：Debug ≈ 8.8 MiB，ReleaseSmall 102,336 B ≈ 100 KiB（Linux x64）。

`make test` 会运行运行时与编译器的单元测试、所有端到端示例、C 嵌入 API（静态库和共享
库）以及负向路径（缺失输入、损坏/截断的包、未知符号、目标不匹配）。`make c-testsuite`
通过 `scripts/c_testsuite.sh` 运行 `tests/csuite` 中本地的 17 个 C 子集用例；设置
`C_TESTSUITE_DIR` 可让它指向另一个带有 `// expect:` 标记的目录。

## 发布压缩包

`make release-artifacts` 会把四个目标压缩包写入 `build/release/`，并生成每个目标的
SPDX SBOM 和 `SHA256SUMS`（设置了 `CINTERP_GPG_KEY` 时进行 GPG 签名）：

| 压缩包 | 内容 |
| --- | --- |
| `cinterp-<version>-sysv-x86_64` | 编译器 + 运行时，Linux x86-64（`bin/cinterp-cc`、`bin/cinterp`） |
| `cinterp-<version>-win64-x86_64` | 仅运行时，Windows x64 |
| `cinterp-<version>-win32-x86` | 仅运行时，Windows x86 |
| `cinterp-<version>-arm64` | 仅运行时，Linux AArch64 |

只有 Linux x86-64 压缩包包含 `bin/cinterp-cc`；另外三个包含运行时、头文件、
pkg-config/CMake 元数据和 Rust 绑定。每个压缩包的 `README.md` 由
[`packaging/README.release.md.in`](packaging/README.release.md.in) 渲染而来，描述的正是
该目标的布局。`THIRD_PARTY_NOTICES.md`（针对生成的符号索引，对 MinGW-w64 的 `.def` 和
glibc 的 `abilists` 的署名）只随编译器压缩包发布；仅含运行时的压缩包不携带任何派生数据。

## C 测试套件

上游套件按 commit 固定版本，并获取到 `build/suites/` 中（不 vendor 进仓库）。统一运行器读取
`tests/manifests/*.json`，记录显式的跳过项并写出 `build/test-suites-*.json`。

```bash
python3 scripts/fetch_suites.py --all --support
make test-suites-smoke      # fast local subset (csuite, 17/17)
make test-suites            # c-testsuite + TCC + chibicc + libc-test
make test-suites-full       # adds GCC torture, CompCert, LLVM subsets
make test-suites-cross      # csuite + upstream smoke on Win64/Win32/ARM64
make generate-diff          # YARPGen differential smoke
make test-winapi            # Windows API imports; needs Wine + cross runtimes
```

当前原生基线（`build/test-suites-full.json`）：在 4521 个 manifest 用例中
**4319 个通过 / 202 个显式跳过**，另有 1034 个被刻意排除的非目标用例。标准层级
（`build/test-suites.json`）则是 495 个用例中 **396 个通过 / 99 个跳过**。

通过用例中约 55% 是**仅编译**（gcc-torture-compile 1408 + llvm-regression-c 934 +
compcert-compile 30 = 2372）：它们只检查编译器是否接受源码并产出一个包，而不检查程序的
输出是否与原生执行一致。可执行基线是其余 1862 个通过用例（4319 − 2457 个编译模式通过）。
现在有四个仅编译的压力用例以显式的 `compiler limit:` 原因跳过，因为产出的包会超出运行时
512 个 import、64 个参数或 2 MiB 模块的限制。跳过文件记录不受支持的特性和已知失败；它们
从不由 CI 自动更新。见 [`tests/manifests/README.md`](tests/manifests/README.md)。

上游 c-testsuite：`tests/manifests/c-testsuite.json` 有 220 个 single-exec 用例，其中
包含两个内联跳过（`00204` 向量类型、`00216` 复杂聚合全局初始化器），即
**218 运行 / 218 通过 / 2 跳过**。独立的 `scripts/c_testsuite_upstream.py` 仍默认使用较旧
的 `tests/csuite/cinterp.skip` 列表，该列表还列了 `00189`（外部数据符号），因此得到
**217/217，另有 3 个跳过**；`tests/manifests/c-testsuite.skip` 存在，但没有被任何 manifest
引用。这两个跳过列表尚未统一 —— 在统一之前，manifest 运行请引用 218/2，只有独立脚本才引
用 217/3。

在完整报告中，`llvm-regression-c` 里重复的 support 文件 ID 已用 `*-support` 后缀重命名，
因此唯一用例数保持 935，上面的基线也保持稳定。

## 验证与信任

运行时会先校验包长度、目标元数据（arch/OS/ABI/指针宽度/特性）、CIPI 的 plan/provider
引用、函数/plan 数量、plan 参数数量、ABI 位置索引以及 marshal 偏移/大小，然后才调用原生
代码；格式错误的包会干净地失败。`cinterp-run --load-only` 在不解执行的情况下校验包；
`make fuzz` 会对种子包做变异/截断并检查是否崩溃。自动 provider 必须是库名（不能是路径），
并且从系统加载器加载。指向原生分配内存的 C 指针必然是受信任的，因此请在操作系统沙箱中运行
不受信任的包。

`scripts/check_plan_evidence.py` 读取结构化产物（`build/test-suites*.json`、
`build/generate-diff-nightly.json`、`build/release/*.tar.gz`、`SHA256SUMS`、各交叉运行时），
而不是去 grep 文本日志。`make evidence` 会生成本地子集并运行它；完整、交叉和 nightly 报告
在本地会报告为 "not provided"，并由 CI 产物补齐。

格式参考：[`docs/cib.md`](docs/cib.md) 涵盖 CIPKG v2、CIPM、CIPI、CIPL 和操作码表。

## 编译器

```bash
./build/cinterp-cc compile source.c -o out.cib \
  [--dump] [--dump-ast] [--dump-imports] [--keep-ir] [--target TARGET] \
  [--cc zig] [--cc-path PATH] [--cib-version 1|2] [--no-auto-link]
```

`--dump` 打印函数和 FFI 计划（包括每个计划的 `conv`）；`--dump-ast` 打印解析后的带类型
AST；`--dump-imports` 打印 CIB provider 绑定；`--keep-ir` 把生成的 LLVM IR 保留在包旁边。
`--cc-path` 选择用作 C 前端的 `zig` 可执行文件，`--cc` 目前只接受 `zig`。
`--cib-version 1` 生成不含 CIPM/CIPI 的旧版包。`--no-auto-link` 关闭对
C 标准库/Windows API 的自动绑定。目标：`x86_64-linux`（默认，原生）、`x86_64-windows`、
`i686-windows`、`aarch64-linux`。Windows 目标在可用时会自动使用 Zig 自带的 MinGW 头文件
（`libc/include/any-windows-any`）；设置 `ZIG_LIB_DIR` 可覆盖。

编译器在 plan 中建模调用约定：对原生、间接和回调计划，`x86_stdcallcc` 映射为 `conv=1`，
`x86_fastcallcc` 映射为 `conv=2`（调用点的约定优先；声明是回退值）。已知的 Windows API
import 仍然采用 `win_defs` 中记录的 DLL/符号/callconv，对于 i686 stdcall 导出，这会覆盖
plan 字节。

完全相同的计划会按完整内容（名称、参数/位置、返回位置、stack/sret/sse/ret 大小和 conv）
去重，因此对同一签名的重复调用共享同一个 CIPL 条目。在序列化之前，编译器会检查每一项
运行时限制，并以 `compiler limit: ...` 失败，而不是产出一个会被加载器拒绝的包：512 个
函数、1024 个计划、每个计划 64 个参数、每个参数/返回值 8 个位置、128 字节的函数/计划名、
512 个 import、每个 import 8 个 provider、64 字节的 import/provider/符号名、32 字节的
provider 版本，以及 2 MiB 的 CIVM 模块。

编译器会自动链接用到的 C 标准库符号和 Windows API；这些不需要 `--lib`。符号 -> provider
表在构建期从已安装的 Zig 工具链生成，因此没有签入仓库的链接数据库，也没有 `--link-db`
选项（该选项已被移除）：

- **Linux**（`compiler/src/libc_defs.zig`）：Zig 自带的 glibc `abilists` 给出导出方
  soname（`printf` -> `libc.so.6`，`sin` -> `libm.so.6`，`pthread_create` ->
  `libc.so.6`/`libpthread.so.0`）。
- **Windows**（`compiler/src/win_defs.zig`）：Zig 自带的 MinGW `.def` 文件给出 DLL、
  x86 stdcall 修饰和调用约定（`GetTickCount64` -> `kernel32.dll`，`GetSystemMetrics` ->
  `user32.dll`，`MessageBoxA@16` -> `user32.dll`，带 `conv=1`）。
- **运行时回退**：索引未描述的符号（UCRT 的 `printf`、自定义库）在运行时从进程、
  `--lib` 库和默认 C 运行时（Linux 上的 `libc.so.6`/`libm.so.6`/...，Windows 上的
  `msvcrt.dll`/`ucrtbase.dll`/`ntdll.dll`）解析。

由于 Windows 索引不再携带最低 OS 字段，新包声明 `min_os=0`；调用在较旧 Windows 上缺失的
API 会在运行时而非加载时失败。自定义库仍然使用 `--lib`，并优先于 CIB provider。一次只执行
一个 CIB；CIB 到 CIB 的链接被明确判定为不支持。

编译器目前支持：

- 标量 `i1/i8/i16/i32/i64`，整数算术/除/取余/位运算/移位
- 有符号/无符号比较，trunc/zext/sext，switch/goto
- 线性内存上的 alloca/load/store、数组、结构体、指针参数、GEP、union 别名、
  `memcpy`/`memset`、全局变量和字符串字面量
- 外部标量/指针/varargs 调用（FFI 计划），例如 `puts`、`printf`、`malloc`、`free`、
  `snprintf`
- 通过基础 CIPI 数据 provider 和运行时回退访问外部数据符号（`stdout`、`errno`、
  `environ`、`stdin`、`tzname`、`opt*`，以及 Windows UCRT 的
  `_errno`/`__acrt_iob_func`/`__p__environ` 辅助函数）
- 跨四种 ABI 的 C varargs 函数（`va_start`/`va_arg`/`va_end`/`va_copy`），包括对
  `long double` 和聚合参数的复制
- `main(argc, argv, envp)` 配合 `cinterp-run package -- arg...`
- VM 层面的 `setjmp`/`longjmp`（包括 Windows 的 `_setjmp3`/`__intrinsic_setjmpex`）
- 外部 MEMORY 结构体按值传递（`byval`）以及通过 `sret` 返回结构体（见
  `examples/ffi_structs.c` + `--lib`）
- 寄存器类的小结构体：强制转换的 8 字节（S8）和 16 字节 double-HFA 聚合返回值（D16），
  包括 `extractvalue` 和 `fptosi`（见 `examples/ffi_regstruct.c`）
- 回调：作为 C 函数指针传入的 VM 函数会在 SysV x64、Win64、Win32（cdecl 和 stdcall）和
  AArch64 上变成一个静态 trampoline；dispatcher 重新进入 VM 时不展开外层栈帧（见
  `examples/ffi_qsort.c`、`examples/ffi_callback*.c`、`examples/ffi_callback_stdcall.c`）
- 两个 eightbyte 的混合类别寄存器聚合（例如 `{ i64, double }` 在 RAX + XMM0 中返回；见
  `examples/ffi_mixedstruct.c`）
- float32/double 算术：`fadd`/`fsub`/`fmul`/`fdiv`、`fcmp`、`fpext`/`fptrunc`、
  `sitofp`/`fptosi`（见 `examples/math.c`、`examples/float_math.c`、
  `examples/ffi_float.c`）
- 位域：经由 clang 的整数移位/掩码降低（见 `examples/bitfields.c`）
- 内部精确的 `long double`：x86 目标上为 x86 `f80`，AArch64 上为 IEEE `f128`；
  算术/比较/转换以及 FFI/varargs 路径（`examples/longdouble.c`、
  `examples/ffi_longdouble.c`）。Windows CRT 的 `%Lf` 行为与原生 MinGW 运行时一致。
- 内部函数指针、间接调用、`phi`、VLA、packed 结构体、全局指针/函数指针重定位、
  HFA 3/4 和栈上 HFA（`examples/ffi_hfa.c`、`examples/ffi_hfa_stack.c`）
- Win32 `__fastcall` 原生/间接调用（ECX/EDX + 栈，见 `examples/ffi_fastcall.c`）以及
  Win32 `__stdcall` 调用/回调

明确不在当前 C/ABI 子集内的：向量类型、`_Complex` 和复杂/空结构体聚合的全局初始化器、
Win64 的 `__vectorcall`/COM、Win32 `thiscall`、Win32 `__fastcall` 回调、SysV
`i128`/向量参数、内联汇编、`_Atomic`/`_Thread_local`，以及 CIB 到 CIB 的链接。Windows CRT
的 `long double` printf 输出与原生 MinGW 运行时一致（后者本身在测试主机上并未实现 `%Lf`）。
GCC builtin、外部 inline/weak 地址语义以及可增长的线性内存同样不在范围内。

## 二进制格式

- `CIVM`：字节码模块（头部、函数表、代码）。VM 线性内存由 `main` 开头为全局变量/字符串
  生成的代码初始化。
- `CIPL` v3：FFI 计划表（magic/version/ABI、具名的 `CallPlan`、arg/ret 位置、
  stack/sret/sse/ret_size/conv）。
- `CIPKG` v2：25 字节头部 + `CIVM` + `CIPL` + `CIPM` 目标元数据 + `CIPI` import 表。
  旧版 v1 包仍可加载。
- `CIPM`：arch/OS/ABI/指针宽度/字节序/特性/triple/min-runtime，外加 `link_db` 来源字符串，
  它指明构建期的符号索引（`mingw-defs@<zig version>` / `glibc-abilists@<zig version>`）。
- `CIPI`：plan 索引 → provider 库、真实符号/别名、ordinal、callconv、架构掩码和最低 OS。

详细的字节布局、操作码表、CIPL/CIPM/CIPI 字段以及带注释的 `hello.cib` 都在
[docs/cib.md](./docs/cib.md) 中。

## 运行时

```bash
./runtime/zig-out/bin/cinterp-run <package.cib> [entry] [-- arg...]
```

`cinterp-run` 成功时退出码为 0，加载/运行失败为 1，用法或 I/O 错误为 2；C `main` 的返回值
会以 `result: N` 打印，不会成为进程退出码。

运行时还附带一个嵌入库：

```bash
cd runtime && zig build -Doptimize=ReleaseSmall
# zig-out/include/cinterp.h
# zig-out/lib/libcinterp.a, libcinterp.so[.0]
# zig-out/bin/cinterp.dll and lib/cinterp_static.lib on Windows
```

```c
#include <cinterp.h>

ci_vm *vm = ci_vm_create(0);
int rc = ci_vm_load_package(vm, cib_bytes, cib_size);
if (rc == CI_OK) rc = ci_vm_run_args(vm, "main", argc, argv);
int64_t value = ci_vm_result(vm);
ci_vm_destroy(vm);
```

C ABI 版本是 `CI_ABI_VERSION = 2`；`ci_abi_version()` 返回它，`ci_version()` 返回运行时
版本字符串。`ci_vm_run`/`ci_vm_run_args` 返回的是状态，而不是 C `main` 的结果：`CI_OK`
或一个**负数、按类别划分的 `CI_E_*` 码**（`CI_E_INVALID_ARGUMENT`、`CI_E_BAD_PACKAGE`、
`CI_E_TARGET`、`CI_E_PLANS`、`CI_E_LINK`、`CI_E_ENTRY`、`CI_E_RESOURCE`、
`CI_E_RUNTIME`、`CI_E_OUT_OF_MEMORY`、`CI_E_DESTROYED`）。只有当失败无法归类时才会返回
`CI_ERROR`（-1）。同一类别可通过 `ci_vm_last_error_code()` 获取，文本则来自
`ci_vm_last_error()`；`ci_vm_clear_error()` 会重置两者并返回 `CI_OK`。`CI_E_DESTROYED`
与其他运行时错误不同。加载器是事务性的。

`ci_vm_create(stack_size)` 接受一个值栈槽位上限：`0` 选择默认的 8192 个槽位（同时也是
最大值）。`ci_vm_create_ex` 还额外接受 `memory_size`（`0` = 默认 1 MiB，最大 16 MiB）以及
一个必须为 0 的保留 `flags` 字段；`struct_size` 止于 `stack_size` 的旧调用方仍被接受。
包仍然需要构建期用 `cinterp` 编译；运行时不需要 clang。

默认 VM 会分配约 0.9 MiB 的 VM 记录（主要是固定的 512 项 CIPI import 表和 512 个帧记录）、
一个 8192 槽位的值栈（64 KiB）以及默认 1 MiB 线性内存 —— 合计约 2 MiB。模块缓冲区和
FFI 计划存储按加载的包分配，而不是固定的 6.5 MiB 计划表。对小包可以调低 `memory_size`。
不同的 VM 实例不共享解释器状态。

VM 每个实例是单线程的，并在宿主回调边界处可重入。回调 trampoline 位于进程级、共 256 个
固定槽位的池中。当所属 VM 被销毁或其计划被重新加载时，槽位会被永久退役，且**永不重用**
（宿主可能仍持有该函数指针），因此该池是每进程 256 次回调注册的一次性预算；之后的
`CREATE_CALLBACK` 操作会以 `TooManyCallbacks`（`CI_E_RUNTIME`）失败。

对于 v2 包，运行时通过 CIPI provider 解析原生符号（`--lib` 作为用户覆盖）；未列出的自定义
符号回退到进程、已加载的 `--lib` 库和平台 C 运行时。解析出的目标在首次调用时按 plan 索引
缓存，当包或计划表被替换时会清空 provider/target 缓存（显式的 `--lib` 句柄在包替换后仍然
有效）。一个 VM 中超过 256 个不同的原生目标会返回 `TooManyNativeTargets`（`CI_E_LINK`）。
库句柄永不卸载：`--lib` 和 provider 库会一直保持映射直到进程退出。静态回调 trampoline 可用于
SysV x64、Win64、Win32 和 AArch64。

运行时执行受信任的 CIB 包，不提供进程内沙箱；`--load-only` 在不解执行的情况下校验包。
不受支持的运行时（macOS/未知 OS 和 musl）会在加载时以 `UnsupportedOs`/`UnsupportedLibc`
拒绝包。

## 仓库结构

```text
compiler/          Zig compiler (build-time)
  src/main.zig         cinterp-cc CLI, CIPKG/CIPM/CIPI writer, limit checks
  src/opcodes.zig      CIVM opcode definitions (single source)
  src/ir/              typed LLVM IR lexer/parser/AST/verifier/dump
  src/lower_ast.zig    AST -> CIVM lowering, plan interning
  src/abi.zig          CallPlan model and per-ABI plan builders
  src/imports.zig      structured CIPI table and serializer
  src/link_index.zig   binary format of the generated symbol indexes
  src/win_defs.zig     Windows providers from Zig's bundled MinGW .def files
  src/libc_defs.zig    Linux providers from Zig's bundled glibc abilists
  src/link_wrappers.zig  target link-ABI aliases (snprintf -> _snprintf)
  src/data/link_wrappers.json  the only checked-in link metadata
  tools/gen_link_index.zig     build-time generator for win_defs/libc_defs
docs/                  format, embedding, compatibility, IR subset, Zig frontend
runtime/               Zig VM/runtime (shipped)
  src/vm.zig           VM, linear memory, C ABI, callback dispatcher
  src/vm_test.zig      runtime unit tests
  src/main.zig         cinterp-run CLI
  src/ffi/abi.zig      plan/loc types shared with the loader and asm engines
  src/ffi/plan_loader.zig  CIPL decoder and plan store
  src/ffi/platform.zig compile-time ABI/frame/marshal/invoke selection
  src/ffi/native.zig   dlopen/LoadLibrary symbol resolution
  src/ffi/link_loader.zig  CIPM/CIPI parser and target/import validation
  src/ffi/asm/         SysV, Win64, Win32, AArch64 engines and trampolines
  include/cinterp.h    public C ABI header
  tests/               C API smoke/argv/fuzz hosts
examples/              hello, arrays, structs, puts/printf/snprintf, malloc/free,
                       MEMORY/register/mixed/HFA struct FFI, qsort/callback,
                       fastcall/stdcall, math, float32 FFI, bitfields, long double
scripts/               Python test/fuzz/benchmark/release harnesses
packaging/             pkg-config, CMake, Rust binding, release README template
tests/                 local csuite, manifests and generator known failures
spike/                 validated ABI/VM/callback feasibility spikes (gitignored)
```

## 文档

- [docs/README.md](docs/README.md) — 文档索引
- [docs/cib.md](docs/cib.md) — CIB 包格式、链接元数据、状态码
- [docs/embedding.md](docs/embedding.md) — 在 C 宿主中嵌入运行时
- [docs/compatibility.md](docs/compatibility.md) — ABI、SONAME 与版本策略
- [docs/ir-subset.md](docs/ir-subset.md) — 可接受的 LLVM IR 子集
- [docs/ir-parser-differences.md](docs/ir-parser-differences.md) — 原字符串解析器的差异
  （保留作为 AST 正确性测试）
- [docs/zig-frontend.md](docs/zig-frontend.md) — Zig/`zig cc` 前端契约
- [tests/manifests/README.md](tests/manifests/README.md) — 套件 manifest 与跳过策略

架构、实现决策、ABI 细节、验证证据和已知边界见 `dev.md`。
