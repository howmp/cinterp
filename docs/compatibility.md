# 版本与兼容性策略

本文记录 cinterp 当前的版本和二进制格式。0.1.7 已发布，但仍不保证格式兼容；
运行时只接受当前 `CIPKG` v4 trusted 格式，旧包格式和迁移路径不保留。

## 单一版本源

- 仓库根目录 `VERSION` 是唯一版本源，格式为语义化版本（当前 `0.1.7`）。
- 编译器 `compiler/build.zig` 在构建时读取仓库根目录 `VERSION`；`cinterp-cc --version`
  输出 `cinterp-cc <VERSION>`。
- 运行时在构建时读取仓库根目录 `VERSION`，写入 `ci_version()`
  和共享库版本号；共享库 SONAME 主版本取 `VERSION` 主版本（见下）。
- `scripts/release/package_release.sh` 只从 `VERSION` 取版本，不再接受硬编码副本。
- `scripts/tools/check_version.py`（`make check-version`）校验根 `VERSION`、
  `runtime/build.zig.zon`、`packaging/rust/cinterp-sys/Cargo.toml.in`、SBOM 文档以及
  release tag；不一致时以非零退出。

## 当前格式

| 组件 | 版本 | 写入方 | 读取方 |
| --- | ---: | --- | --- |
| CIPKG 包 | 4（trusted） | `cinterp-cc` | 运行时只读 4 |
| CIVM 字节码模块 | 2 | 编译器 | 运行时只读 2 |
| CIPL FFI 计划表 | 4 | 编译器 | 运行时只读 4 |
| CIPI 导入表 | 2 | 编译器 | 运行时只读 2 |
| CIPC 常量/名称池 | 2 | 编译器 | 运行时只读 2 |
| C ABI | 2（`CI_ABI_VERSION`） | `cinterp.h` / `libcinterp` | 嵌入方 |

`CIPKG` v4 只包含 22 字节头、CIVM、CIPL、CIPI 和 CIPC，不携带目标声明。包必须由与
编译目标匹配的运行时加载；运行时保留 CIPL `abi_id` 检查，用于拒绝明显的 ABI 混用。
CIPC v2 的 `name_blob`/`data` 默认 XOR 混淆；项目不保留 CIPC v1 读取、旧包迁移或兼容层。

## C ABI

- `CI_ABI_VERSION` 与包格式版本相互独立；当前为 **2**，由 `ci_abi_version()` 返回。
  头文件同时提供 `ci_vm_clear_error()`、`ci_abi_version()` 和 `ci_version()`。
- 在同一 ABI 主版本内，只允许**追加**函数、状态码和配置字段。带 `struct_size`
  的结构体按传入大小读取；`ci_vm_config.memory_size` 是 append-only 字段。
- 多 CIB 与每 VM 线程模型通过 append-only 方式扩展 C ABI 2：`ci_process_*`、
  `ci_vm_busy`、`ci_vm_destroy_ex`、`ci_vm_callback_error`、
  `ci_callback_pool_stats`，以及 `CI_E_BUSY = -12`。
- 状态码是稳定合同：`ci_vm_*` 成功返回 `CI_OK`，失败返回具体的 `CI_E_*` 类别；
  `CI_ERROR`（-1）只在错误无法归类时返回。`ci_vm_last_error_code()` 返回同一类别；
  Debug 构建的 `ci_vm_last_error()` 返回错误名，Release 构建返回空字符串。
- 删除/重命名函数、改变参数或返回类型、改变结构体字段顺序属于破坏性变更。
- 共享库文件名跟随 `VERSION`，SONAME 为 `libcinterp.so.<VERSION 主版本>`；嵌入方应
  通过 `ci_abi_version()` 检查 ABI，而不是从 `.so` 文件名推断兼容性。
- 回调 trampoline 固定为进程级 **256** 个静态槽，不生成可执行内存。自动槽绑定到 VM，
  显式 `ci_callback_acquire`/`ci_callback_release` 槽可复用；释放后的旧指针不得再次调用。
- VM 忙时其他线程的 callback **不排队、不等待**，非 sret 返回值置零、sret 缓冲区不变，
  并通过 `ci_vm_callback_error` 记录 `CI_E_BUSY`（sticky，直到 `ci_vm_clear_error`）。

## 编译器与运行时

- v4 包不记录 `producer`、`triple` 或 `link_db`；运行时不做目标声明校验。
- 不支持的目标（macOS、musl、32 位 Linux、Windows ARM64 等）在编译或加载阶段显式拒绝，
  不得静默回退到 Linux。
- 包格式或 C ABI 发生不兼容变化时，直接更新版本和文档；当前不提供旧格式读取或迁移路径。
