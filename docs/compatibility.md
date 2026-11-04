# 版本与兼容性策略

本文是 cinterp 发布兼容性的唯一合同。

## 单一版本源

- 仓库根目录 `VERSION` 是唯一版本源，格式为语义化版本（当前 `0.1.0`）。
- 编译器 `compiler/build.zig` 在构建时读取仓库根目录 `VERSION`；`cinterp-cc --version` 输出 `cinterp-cc <VERSION>`，CIPM `producer` 使用同一值。
- 运行时在构建时读取 `runtime/../VERSION`（即仓库根目录），写入 `cinterp-run --version`、`ci_version()` 和共享库版本号；共享库 SONAME 主版本取 `VERSION` 主版本（见下）。
- `scripts/package_release.sh` 只从 `VERSION` 取版本，不再接受硬编码副本。
- `scripts/check_version.py`（`make check-version`）是版本一致性的执行检查：它校验根 `VERSION`、`runtime/build.zig.zon`、`packaging/rust/cinterp-sys/Cargo.toml.in`、SBOM 文档以及 release tag（`--tag` 或 GitHub Actions 的 tag ref），不一致时以非零退出并打印冲突的两个值。release workflow 在打包前直接调用该脚本。

## 组件版本

| 组件 | 当前版本 | 写入方 | 读取方 |
| --- | ---: | --- | --- |
| CIPKG 包 | 2（`--cib-version 1` 可写 1） | `cinterp-cc` | 运行时读 1、2 |
| CIVM 字节码模块 | 1 | 编译器 | 运行时读 1 |
| CIPL FFI 计划表 | 3（运行时兼容 2） | 编译器 | 运行时读 2、3 |
| CIPM 目标元数据 | 1 | 编译器 | 运行时读 1 |
| CIPI 导入表 | 1 | 编译器 | 运行时读 1 |
| C ABI | 2（`CI_ABI_VERSION`） | `cinterp.h` / `libcinterp` | 嵌入方 |
| `runtime_version` | 1 | `runtime/src/ffi/platform.zig` | CIPM `min_runtime` 校验 |

## N−1 读取保证

对于 0.x 系列，运行时承诺：

1. **CIPKG**：当前版本（2）与紧邻的前一版本（1）都可加载。删除 v1 读取需要主版本升级，并在本文件记录迁移说明。
2. **CIPL**：编译器写 v3；运行时必须继续读取 v2（N−1）。新增字段只能追加，并只能在既有 `version` 分支内按“存在则读、缺省取 0”处理。
3. **CIVM**：当前只写 v1。引入 v2 时，运行时必须同时支持 v1 和 v2 读取一个完整主版本周期。
4. **CIPM / CIPI**：版本号递增时必须保持前一版本的读取路径；未知版本必须返回 `BadTargetVersion` / `BadImportVersion`，不得猜测。
5. **功能位**：CIPM `features` 中运行时不认识的位一律拒绝（`UnsupportedFeature`）。新增功能位必须先让运行时支持，再由编译器写入。
6. **`min_runtime`**：编译器写入包要求的最低 `runtime_version`；旧运行时会以 `RuntimeTooOld` 拒绝，而不是运行未验证的字节码。

每次发布前，`make test` 的 legacy v1 包测试、`CIPL` v2/v3 单元测试和跨 ABI 套件必须通过，并且 `make check-version` 必须成功。

## C ABI

- `CI_ABI_VERSION` 与包格式版本相互独立；当前为 **2**，由 `ci_abi_version()` 返回。头文件同时提供 `ci_vm_clear_error()`、`ci_abi_version()` 和 `ci_version()`。
- 在同一 ABI 主版本内，只允许**追加**函数、状态码和配置字段。带 `struct_size` 的结构体按传入大小读取，旧调用方可以继续使用较小的结构体。`ci_vm_config.memory_size` 是 append-only 字段：`struct_size` 只覆盖到 `stack_size` 的旧调用方获得默认 1 MiB 线性内存。
- 多 CIB 与每 VM 线程模型同样按追加方式扩展 C ABI 2：新增 `ci_process_create`/`ci_process_destroy`/`ci_process_load_package`/`ci_process_unload_package`/`ci_process_last_error*`、`ci_vm_busy`、`ci_vm_destroy_ex`、`ci_vm_callback_error`、`ci_callback_pool_stats`，以及状态码 `CI_E_BUSY = -12`。既有函数、参数、返回类型、结构体字段顺序和 `CI_E_*` 数值均未改变，因此**不提升** `CI_ABI_VERSION`。
- 状态码是稳定合同：`ci_vm_*` 成功返回 `CI_OK`，失败返回**具体的 `CI_E_*` 类别**；`CI_ERROR`（-1）只在错误无法归类时返回。`ci_vm_last_error_code()` 返回同一类别，`ci_vm_last_error()` 返回具体错误名（如 `BadPackageMagic`）；成功的调用会清空两者。`CI_E_*` 数值不得复用；新增错误类别只能追加新负数。
- 删除/重命名函数、改变参数或返回类型、改变结构体字段顺序属于破坏性变更，必须提升 `CI_ABI_VERSION`。
- 共享库文件名跟随 `VERSION`（当前产物为 `libcinterp.so.0.1.0`），SONAME 为 `libcinterp.so.<VERSION 主版本>`（当前 `libcinterp.so.0`），并保留未版本化的 `libcinterp.so` 链接名。**0.x 阶段 SONAME 主版本取 `VERSION` 主版本（当前 0），`CI_ABI_VERSION`（当前 2）是独立编号**：`CI_ABI_VERSION` 提升不必然立即改变 SONAME，只有 `VERSION` 主版本提升时 SONAME 主版本才随之变化。嵌入方应通过 `ci_abi_version()` 检查 ABI，而不是从 `.so` 文件名推断兼容性。
- 回调 trampoline 的进程级生命周期属于 ABI 合同：固定 **256** 个进程级静态槽，不生成可执行内存。自动 `CREATE_CALLBACK` 槽绑定到其 VM，并在 VM 销毁或计划重载后**永久退休、永不复用**；显式 `ci_callback_acquire`/`ci_callback_release` 槽在释放后回到可复用集合，未释放的显式槽在 VM 销毁/重载时退休。释放后的旧指针不得再次调用（复用后可能进入另一个 VM，属于调用方违约）。`ci_callback_pool_stats` 可查询 live/free/retired 数量。Win32 `__stdcall`、`__fastcall` 和 `__thiscall` callback 均受支持（fastcall/thiscall trampoline 保存寄存器参数，并按对应 layout 清理栈参数）。

## 编译器与运行时

- 编译器产物的 `producer` 字段记录 `cinterp <VERSION>`，用于诊断；运行时不依赖它做兼容判断。
- 运行时通过 CIPM 的 arch/OS/ABI/指针宽度/端序/features/min_runtime 校验包，不匹配时返回稳定错误（`TargetMismatch`、`UnsupportedFeature`、`RuntimeTooOld`）。
- 不支持的目标（macOS、musl、32 位 Linux、Windows ARM64 等）必须在编译或加载阶段显式拒绝并给出可诊断错误，不得静默回退到 Linux。

## 弃用周期

- 包格式和 C ABI 的弃用公告至少保留一个次版本；弃用期间旧格式保持可读。
- 主版本升级才允许移除 N−1 读取路径，并在本文件记录迁移说明和测试证据。
