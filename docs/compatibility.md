# 版本与兼容性策略

本文是 cinterp 发布兼容性的唯一合同。

## 单一版本源

- 仓库根目录 `VERSION` 是唯一版本源，格式为语义化版本（当前 `0.1.0`）。
- 编译器 `compiler/build.zig` 在构建时读取仓库根目录 `VERSION`；`cinterp-cc --version` 输出 `cinterp-cc <VERSION>`，CIPM `producer` 使用同一值。
- 运行时在构建时读取 `runtime/../VERSION`（即仓库根目录），写入 `cinterp-run --version`、`ci_version()` 和共享库 SONAME 版本。
- `scripts/package_release.sh` 只从 `VERSION` 取版本，不再接受硬编码副本。

## 组件版本

| 组件 | 当前版本 | 写入方 | 读取方 |
| --- | ---: | --- | --- |
| CIPKG 包 | 2（同时可写 1） | `cinterp-cc --cib-version` | 运行时读 1、2 |
| CIVM 字节码模块 | 1 | 编译器 | 运行时读 1 |
| CIPL FFI 计划表 | 3（运行时兼容 2） | 编译器 | 运行时读 2、3 |
| CIPM 目标元数据 | 1 | 编译器 | 运行时读 1 |
| CIPI 导入表 | 1 | 编译器 | 运行时读 1 |
| C ABI | 2（`CI_ABI_VERSION`） | `cinterp.h` / `libcinterp` | 嵌入方 |
| `runtime_version` | 1 | `runtime/src/ffi/platform.zig` | CIPM `min_runtime` 校验 |

## N−1 读取保证

对于 0.x 系列，运行时承诺：

1. **CIPKG**：当前版本（2）与紧邻的前一版本（1）都可加载。删除 v1 读取需要主版本升级并在 `dev.md` 记录。
2. **CIPL**：编译器写 v3；运行时必须继续读取 v2（N−1）。新增字段只能追加，并只能在既有 `version` 分支内按“存在则读、缺省取 0”处理。
3. **CIVM**：当前只写 v1。引入 v2 时，运行时必须同时支持 v1 和 v2 读取一个完整主版本周期。
4. **CIPM / CIPI**：版本号递增时必须保持前一版本的读取路径；未知版本必须返回 `BadTargetVersion` / `BadImportVersion`，不得猜测。
5. **功能位**：CIPM `features` 中运行时不认识的位一律拒绝（`UnsupportedFeature`）。新增功能位必须先让运行时支持，再由编译器写入。
6. **`min_runtime`**：编译器写入包要求的最低 `runtime_version`；旧运行时会以 `RuntimeTooOld` 拒绝，而不是运行未验证的字节码。

每次发布前，`make test` 的 legacy v1 包测试、`CIPL` v2/v3 单元测试和跨 ABI 套件必须通过。

## C ABI

- `CI_ABI_VERSION` 与包格式版本相互独立；当前为 2。
- 在同一 ABI 主版本内，只允许**追加**函数、状态码和配置字段。带 `struct_size` 的结构体按传入大小读取，旧调用方可以继续使用较小的结构体。`ci_vm_config.memory_size` 是 append-only 字段：`struct_size` 只覆盖到 `stack_size` 的旧调用方获得默认 1 MiB 线性内存。
- 删除/重命名函数、改变参数或返回类型、改变结构体字段顺序属于破坏性变更，必须提升 `CI_ABI_VERSION` 并提升共享库 SONAME 主版本。
- 状态码是稳定合同：`CI_E_*` 数值不得复用；新增错误类别只能追加新负数。
- 共享库版本跟随 `VERSION`（`libcinterp.so.0.1.0`，SONAME `libcinterp.so.0`）；ABI 主版本变化时同步提升 SONAME 主版本。
- 回调 trampoline 在 VM 销毁后永久退役；这一行为是 ABI 的一部分，不随小版本改变。

## 编译器与运行时

- 编译器产物的 `producer` 字段记录 `cinterp <VERSION>`，用于诊断；运行时不依赖它做兼容判断。
- 运行时通过 CIPM 的 arch/OS/ABI/指针宽度/端序/features/min_runtime 校验包，不匹配时返回稳定错误（`TargetMismatch`、`UnsupportedFeature`、`RuntimeTooOld`）。
- 不支持的目标（macOS、musl、32 位 Linux、Windows ARM64 等）必须在编译或加载阶段显式拒绝并给出可诊断错误，不得静默回退到 Linux。

## 弃用周期

- 包格式和 C ABI 的弃用公告至少保留一个次版本；弃用期间旧格式保持可读。
- 主版本升级才允许移除 N−1 读取路径，并在 `dev.md` 的兼容性章节记录迁移说明和测试证据。
