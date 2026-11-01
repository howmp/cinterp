---
name: production-embedding-readiness
status: completed
overview: 计划已全部完成；证据见 dev.md §20.21–§20.26。
---

# 生产嵌入剩余工作

无剩余 P0/P1 项。

- 当前基线：full 4323/4521（198 skip），standard 396/495（99 skip）。
- 保留的 dialect skip（`bitfld-3`、`pr32244-1`、`pr34971`、TCC `95_bitfields_ms`）和外部 inline/weak 等明确 non-goal 见 `dev.md §20.24`。
- 发布链、版本与兼容策略、pkg-config/CMake/Rust 绑定、内存/fuzz/cross-ABI CI 的完成证据见 `dev.md §20.26`，兼容合同见 `docs/compatibility.md`。
