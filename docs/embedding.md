# 在宿主应用中嵌入 cinterp

`libcinterp` 执行由 `cinterp` 编译器提前编译生成的包。运行时是一个带有普通 C ABI
的小型 Zig 库；它在运行期不需要 clang、Python 或可执行内存。

## 构建与安装

```bash
# release runtime + static/shared libraries + header (Linux x64 example)
cd runtime
zig build -Doptimize=ReleaseSmall
# zig-out/include/cinterp.h
# zig-out/lib/libcinterp.a
# zig-out/lib/libcinterp.so -> libcinterp.so.0 -> libcinterp.so.0.1.0
```

其他目标使用 Zig 的交叉编译：

```bash
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSmall
zig build -Dtarget=x86-windows-gnu -Doptimize=ReleaseSmall
zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseSmall
```

每个发布 tarball（sysv-x86_64、win64-x86_64、win32-x86、arm64）都附带
`cinterp.pc`、CMake 包配置和 `cinterp-sys` Rust crate。只有 Linux x86-64 tarball
还附带 `bin/cinterp-cc`（其编译器可以为全部四个目标生成包）；其余三个只含运行时，
因此请使用 Linux tarball 编译，或从源码构建编译器。

### pkg-config

```bash
export PKG_CONFIG_PATH=/path/to/cinterp/pkgconfig
cc host.c $(pkg-config --cflags --libs cinterp)
# static link against libcinterp.a / cinterp_static.lib:
cc host.c $(pkg-config --static --cflags --libs cinterp)
```

`Libs.private` 携带静态链接所需的额外系统库（Unix 上为
`-ldl -lpthread -lm`，Windows 上为空），因此 `--static` 不需要额外标志。

### CMake

```cmake
find_package(cinterp 0.1 REQUIRED)
target_link_libraries(host PRIVATE cinterp::cinterp)
```

tarball 会安装 `cinterpConfig.cmake` **和** `cinterpConfigVersion.cmake`（两者同时
位于 `cmake/` 与 `lib/cmake/cinterp/`）。版本文件实现同主版本匹配：只要请求的版本
不超过 tarball 的 `VERSION` 且属于同一主版本系列，就会匹配成功，因此
`find_package(cinterp 0.1 REQUIRED)` 对 0.1.x 成立，而
`find_package(cinterp 1.0)` 失败。

### Rust

```toml
[dependencies]
cinterp-sys = { path = "vendor/cinterp-sys" }
```

该 crate 暴露原始 `ci_vm_*` 符号以及一个小型的安全 `Vm` 包装；参见发布 tarball 中的
`rust/cinterp-sys/README.md`。`ci_process_*`、`ci_vm_busy`、`ci_vm_destroy_ex` 和
callback 池统计目前没有安全封装，需要时请在 Rust 中直接声明对应 `extern "C"`，或使用
C 宿主。`Error` 携带三个字段：

- `Error.code` 是 `ci_vm_last_error_code()` 报告的类别（一个 `CI_E_*` 值；若 VM 未
  记录任何类别，则为原始状态码）；
- `Error.status` 是失败调用返回的负值（`CI_ERROR` 或 `CI_E_*`）；
- `Error.message` 是来自 `ci_vm_last_error()` 的文本。

控制流请匹配 `code`，日志记录请使用 `status`。对于 VM 报告的错误，两者当前持有相同
的负值；`code` 是稳定的类别，而 `status` 精确记录该调用返回的内容。

## 编译包

```bash
./build/cinterp-cc compile app.c -o app.cib --target x86_64-linux
```

请使用与将来加载该包的运行时相匹配的目标。`--dump-imports` 列出包所期望的原生符号；
编译器会使用它在构建期从 Zig 工具链生成的符号索引，自动链接 C 标准库符号以及
（在 Windows 上）Windows API。索引未覆盖的符号由运行时回退解析；自定义库可以在运行
期通过 `--lib` 添加。

## C API

```c
#include <stdio.h>
#include <cinterp.h>

int main(void) {
    /* package_bytes/package_size: contents of app.cib */
    ci_vm *vm = ci_vm_create(0);      /* 0 = default 8192-slot value stack */
    if (!vm) return 1;

    if (ci_vm_load_package(vm, package_bytes, package_size) != CI_OK) {
        fprintf(stderr, "load: %s (%d)\n",
                ci_vm_last_error(vm), ci_vm_last_error_code(vm));
        ci_vm_destroy(vm);
        return 1;
    }

    const char *argv[] = { "app", "--flag" };
    if (ci_vm_run_args(vm, "main", 2, argv) != CI_OK) {
        fprintf(stderr, "run: %s\n", ci_vm_last_error(vm));
        ci_vm_destroy(vm);
        return 1;
    }

    int64_t value = ci_vm_result(vm);
    printf("result: %lld\n", (long long)value);
    ci_vm_destroy(vm);
    return 0;
}
```

`ci_vm_run`/`ci_vm_run_args` 返回状态；被解释执行的 `main` 返回值通过
`ci_vm_result` 读取。`ci_vm_run_args` 最多接受 256 个 argv 条目。

这个单 VM 流程适合一个宿主进程只跑一个 CIB 的场景。需要同时持有多个 CIB 时，使用
`ci_process_create`/`ci_process_load_package` 为每个包创建一个 VM，并用
`ci_process_unload_package` 释放借出的 `ci_vm *`；busy VM 上的卸载/`ci_process_destroy`
返回 `CI_E_BUSY`，宿主 join 运行线程后重试。完整签名、pthread 并行示例、CLI 多包
命令和 callback acquire/release 见 [`multi-cib.md`](multi-cib.md)。

`ci_vm_create_ex` 接受一个 `ci_vm_config` 以支持前向兼容的选项：`struct_size` 至少
必须覆盖到 `stack_size`（若要传入 `memory_size`，请将其设为 `sizeof(ci_vm_config)`），
并且 `flags` 必须为零。

- `stack_size` 是以 VM 值槽为单位的上界。`0` 选择默认的 **8192 个槽**，这同时也是
  最大值；大于 8192 的值会使创建失败（NULL）。它只能降低栈大小，绝不能提高。
- `memory_size` 是线性内存大小，单位为字节。`0` 选择默认的 **1 MiB**，最大值是
  **16 MiB**；更大的值会使创建失败。

`struct_size` 只延伸到 `stack_size` 为止的配置会被接受，并使用默认的 1 MiB 内存。

```c
ci_vm_config cfg = {
    .struct_size = sizeof(cfg),
    .flags = 0,
    .stack_size = 0,           /* 0 = default 8192 slots */
    .memory_size = 256 * 1024  /* 0 = default 1 MiB */
};
ci_vm *vm = ci_vm_create_ex(&cfg);
```

VM 按实例/包分配其值栈、线性内存、模块缓冲区和 FFI 计划存储。默认 VM 是一个约
0.9 MiB 的 VM 记录，加上一个 8192 槽的值栈（64 KiB）和 1 MiB 线性内存 —— 总计约
2 MiB；原先固定的约 10 MiB 占用（其中包括 6.5 MiB 的计划表）已不复存在。对于小包，
可以调低 `memory_size`。

每个 VM 每次 `ci_vm_run*` 都从全新镜像开始：值栈、线性内存、`mem_top`/帧和
`setjmp` 目标都会重置，`main` 开头的全局安装代码会重新执行；`native` 计划缓存保留，
按 run 登记的 native target 重新收集。`ci_vm_result` 返回最后一次**成功**运行的结果，
失败运行不会覆盖它。非 `main` 入口不会执行全局安装代码，这是已知限制；需要全局初始化
时请从 `main` 进入。

## 错误与所有权

- 函数返回 `CI_OK` 或**特定类别的负 `CI_E_*` 状态码**。只有当运行时无法对失败进行
  分类时才返回 `CI_ERROR`（-1）。`ci_vm_last_error_code` 返回同一类别，
  `ci_vm_last_error` 返回具体的错误名（例如 `BadPackageMagic`）。
- `CI_E_BUSY`（-12）表示另一线程正在执行该 VM，或 loader/`ci_vm_destroy_ex`
  遇到 busy；`ci_vm_run` 在同一线程嵌套调用时返回 `CI_E_RUNTIME`。
- 成功的 `ci_vm_load_*`、`ci_vm_run`、`ci_vm_run_args` 或 `ci_vm_load_library` 会
  同时清除错误文本和类别。`ci_vm_clear_error(vm)` 显式清除它们并返回 `CI_OK`。
- `ci_vm_last_error` 返回的文本位于 VM 自己拥有的 128 字节缓冲区中。该指针一直有效，
  直到在该 VM 上发生下一次设置或清除错误的调用（一次失败的 load/run、一次成功的
  调用，或 `ci_vm_clear_error`），或直到调用 `ci_vm_destroy`。不要释放它。
  `ci_vm_last_error(NULL)` 返回空字符串；`ci_vm_last_error_code(NULL)`
  返回 `CI_E_INVALID_ARGUMENT`。
- `ci_version()` 返回指向静态字符串的指针，该字符串在进程的整个生命周期内保持有效；
  不要释放它。
- 加载器是事务性的：失败的 `ci_vm_load_package` 会保持之前已加载的包完好无损。
- VM 会复制包字节；调用方可以在加载成功后释放自己的缓冲区。
- FFI 产生的原生指针（`malloc` 等）是宿主指针。包是可信的构建产物；运行时不是
  进程内沙箱。请在独立进程或容器中运行不受信任的包。

## 线程、回调与多个 VM

- 每个 VM 同一时间只允许一个执行上下文。`ci_vm_run`/`ci_vm_run_args` 在另一线程正在
  运行该 VM 时返回 `CI_E_BUSY`；同一线程从 callback 内再次调用返回 `CI_E_RUNTIME`
  （避免清空外层运行的值栈和线性内存）。`ci_vm_busy(vm)` 返回 1/0。
- 不同 VM 彼此独立，可以同时在不同线程上运行；每个 VM 有自己的执行锁。
- loader（`ci_vm_load_module`/`load_plans`/`load_package`/`load_library`）在 VM 执行
  期间返回 `CI_E_BUSY`，不会替换正在使用的模块或计划。
- `ci_vm_destroy(vm)` 等待另一线程的运行结束；由正在运行的线程调用时延迟到最外层
  运行返回后释放。`ci_vm_destroy_ex(vm, CI_DESTROY_TRY)` 在 busy 时立即返回
  `CI_E_BUSY` 并保持 VM 不变。
- 一个进程需要多个 CIB 时，用 `ci_process_*` 注册表：`ci_process_load_package` 为
  每个包创建一个新 VM，返回的 `ci_vm *` 是借出的句柄，必须用
  `ci_process_unload_package` 释放。`ci_process_destroy` 在仍有 VM 运行时报告
  `CI_E_BUSY` 并保持注册表存活，宿主应 join 线程后重试。详见
  [`multi-cib.md`](multi-cib.md)。
- 回调 trampoline 是进程级的：一个固定 **256 个槽**的静态池，由进程中的每个 VM
  共享，不生成可执行内存。存在两种生命周期：
  - 自动 callback（把 `@cb` 传给原生调用）的槽位绑定到所属 VM，跨重复运行保留，
    直到 VM 被销毁或其计划被重新加载时**永久退休**。因此它不是每次运行消耗一个新槽。
  - `ci_callback_acquire(fn)`/`ci_callback_release(fn)` 允许 CIB 显式管理：acquire
    返回 trampoline 或 NULL（池耗尽），release 成功返回 0 并把槽位放回可复用集合；
    callback 仍在执行时返回 `CI_E_BUSY`，指针不属于当前 VM/已释放时返回
    `CI_E_INVALID_ARGUMENT`。这两个宏由 `cinterp-cc` 强制包含的头文件提供，CIB
    源码不需要 `#include`。释放后的旧指针不得再次调用；未释放的显式槽在 VM 销毁或
    计划重载时退休。
  - `ci_callback_pool_stats(&total, &live, &free_slots, &retired)` 报告池使用情况；
    `ci_vm_callback_error(vm)` 报告被跳过的 callback dispatch（例如 `CI_E_BUSY`），
    `ci_vm_clear_error(vm)` 会一并清除。
- 原生代码在外部线程调用 callback 时：同一线程正在运行 VM 则重入；VM 空闲则 dispatch
  自行取得执行权；另一线程正在运行 VM 时 fail-fast，callback 被跳过、返回值置零并
  记录 `CI_E_BUSY`。不要通过 callback 等待 busy VM，否则可能与运行线程死锁。
- 回调在 SysV x86-64、Win64、Win32 和 AArch64 上受支持。Win32 cdecl/stdcall/fastcall/
  thiscall 回调都受支持：stdcall/fastcall/thiscall trampoline 会按 callee-owned 栈参数
  清理；fastcall 保存 ECX/EDX 供前两个 4 字节标量参数使用，thiscall 保存 ECX 供第一个
  4 字节标量（`this`）使用。HFA 返回值最多使用四个向量寄存器：1-4 个元素的 AArch64 HFA
  在 `v0`-`v3` 中返回（包括四寄存器的情况）。

## 版本与兼容性

- `CI_ABI_VERSION` 当前为 **2**。`ci_abi_version()` 返回它，`ci_version()` 返回仓库
  `VERSION` 文件中的发布版本。`ci_vm_clear_error()` 属于同一个头文件/ABI。
- C ABI 2 是 append-only 的：`CI_E_BUSY = -12`、`ci_vm_busy`、`ci_vm_destroy_ex`、
  `ci_vm_callback_error`、`ci_callback_pool_stats` 和 `ci_process_*` 都是追加项，
  既有函数、数值和语义不变，因此不需要提升 `CI_ABI_VERSION`。
- 包格式版本、N−1 读取保证和 C ABI 规则记录在
  [`compatibility.md`](compatibility.md) 中。
- `CI_ABI_VERSION` 与共享库 SONAME 主版本是相互独立的编号；请检查
  `ci_abi_version()`，而不要从 `.so` 文件名推断兼容性。SONAME 策略见
  `compatibility.md`。
