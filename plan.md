---
name: production-embedding-readiness
overview: 只保留未完成项；P0 1–3、Safe 移除、P0 5 大部分和 alloca 已完成，状态与证据见 dev.md §20.21–§20.24。
---

# 生产嵌入剩余工作

## 已完成的结论

完成项、当前基线和证据已移至 `dev.md §20.24`；当前基线为 full 4319/4519（200 skip）、standard 395/495（100 skip）。

## P0：正式生产前剩余

### 1. 正确性边角

- `20040709-3`：`testF()` 后的嵌套 aggregate-return 状态污染；最小复现、回退实验和子代理结论见 `dev.md §20.22`。在修复前保持 skip，不修改 expected。
- `bitfld-3`、`pr32244-1`、`pr34971`：GCC 期望与 Clang IR 的 bitfield 表达式宽度差异；保持 dialect skip。
- 外部 inline/weak、GCC builtins 等明确 non-goal，不作为回收目标。

### 2. 发布与法律合同

- 增加 LICENSE 与第三方声明，并放进 release tarball。
- 建立单一版本源，明确 `runtime_version`、CIPKG/CIPL/CIVM、C ABI 的兼容策略和 N−1 读取保证。
- 增加正式 release workflow、SBOM、SHA256/签名、split debug 产物。
- 补 pkg-config/CMake/Rust 绑定；当前已有 `libcinterp.a`、`libcinterp.so`、`cinterp.h` 和 Windows 静态/导入库。

## P1：生产质量

- 将 plan store 改为按包大小分配；让 stack/memory 可配置；降低约 10 MB/实例的固定占用。
- 支持 musl，或在 load/compile 时明确拒绝并给出可诊断错误；当前 Linux provider 硬编码 `libc.so.6`/`libm.so.6`。
- 增加 sanitizer、结构化 bytecode fuzz、启用 FFI 的 exec fuzz、跨 ABI fuzz。
- 把 cross-ABI 测试放进 CI，去掉手工 LAN IP 依赖。
- 修正 `docs/cib.md` 与代码的容量限制、错误码表，补英文嵌入指南。
- 修正 macOS/未知 OS 被静默映射为 Linux 的目标校验问题。
- `95_bitfields_ms`/`119_random_stuff` 等 TCC 资源/输出差异继续分诊；`119_random_stuff` 的 `@st_pack` 字符串异常优先定位。

## 明确非目标

- 不提供 Safe 模式、进程内沙箱或资源配额；CIB 只应运行可信构建产物。
- 不可信输入由宿主通过进程/容器隔离，本项目不承担该边界。
- 不支持 MCU、裸机、macOS、musl、Windows ARM64、Linux 32 位/ARM32、线程/atomics/`_Complex`/SIMD/外部 inline/weak 语义。
- 一个进程内同一个 VM 不支持多线程并发；多 VM 已有 callback 隔离，但同一 VM 为单线程串行。
