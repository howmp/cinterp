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
`rust/cinterp-sys/README.md`。`Error` 携带三个字段：

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

## 错误与所有权

- 函数返回 `CI_OK` 或**特定类别的负 `CI_E_*` 状态码**。只有当运行时无法对失败进行
  分类时才返回 `CI_ERROR`（-1）。`ci_vm_last_error_code` 返回同一类别，
  `ci_vm_last_error` 返回具体的错误名（例如 `BadPackageMagic`）。
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

- 单个 VM 是单线程的。不要并发调用同一个 VM。
- 不同的 VM 彼此独立。回调 trampoline 是进程级的：一个固定 **256 个槽**的池，由
  进程中的每个 VM 共享。
- 当拥有该槽的 VM 被销毁或其计划被重新加载时，该槽会**永久退役**，并且**永不复用**
  （宿主可能仍持有该函数指针，复用该槽会把它重定向到另一个 VM）。因此该池是每个
  进程一次性 256 次回调注册的预算：池耗尽后，`CREATE_CALLBACK` 会以
  `TooManyCallbacks`（`CI_E_RUNTIME`）失败。在循环中反复创建和销毁带回调的 VM
  最终会耗尽它；它不是每 VM 的限制。
- `ci_vm_destroy` 会等待正在进行的回调返回后再释放 VM。
- 回调在 SysV x86-64、Win64、Win32 和 AArch64 上受支持。Win32 `__stdcall` 回调受
  支持（trampoline 会弹出 stdcall 参数）；Win32 `__fastcall` 回调在注册时即被拒绝，
  返回 `UnsupportedCallback`（`CI_E_RUNTIME`），因为 i686 trampoline 永远看不到
  ECX/EDX 参数。HFA 返回值最多使用四个向量寄存器：1-4 个元素的 AArch64 HFA 在
  `v0`-`v3` 中返回（包括四寄存器的情况）。

## 版本与兼容性

- `CI_ABI_VERSION` 当前为 **2**。`ci_abi_version()` 返回它，`ci_version()` 返回仓库
  `VERSION` 文件中的发布版本。`ci_vm_clear_error()` 属于同一个头文件/ABI。
- 包格式版本、N−1 读取保证和 C ABI 规则记录在
  [`compatibility.md`](compatibility.md) 中。
- `CI_ABI_VERSION` 与共享库 SONAME 主版本是相互独立的编号；请检查
  `ci_abi_version()`，而不要从 `.so` 文件名推断兼容性。SONAME 策略见
  `compatibility.md`。
