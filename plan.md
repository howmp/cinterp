---
name: compiler-performance
overview: Plan 1–4（excluded/skip 审计、GCC execute、TCC/CompCert triage）已完成，结论见 dev.md §20.20；本文件只保留编译器 batch/daemon 性能工作。
---

# 编译器 batch/daemon 性能

## 1. 现状

- Python 进程内编译 `--inprocess` 和内容寻址 `--cib-cache` 已实现；小套件约 1.7x，full/standard 仍受 clang/runtime/调度限制。

## 2. 工作项

- 增加 batch 模式：一次进程处理多个源文件，批量 clang IR、逐个 lowering。
- 或长驻 compiler daemon（JSON request/response），复用解释器、link DB、正则缓存。
- 支持 target、CPATH、错误隔离、超时和 CIB 输出；保持 CIB 格式。
- 保留 `--inprocess`/`--cib-cache` 作为回退；Rust 重写暂不启动。

## 3. 验收

- full/standard wall time 明显下降，通过数/输出与 **4292/4519（227 skip）**基线一致。
- 不改变 expected、不改变 CIB 格式；4 ABI cross suites 保持通过。
- 单个源编译失败不能拖垮整个 batch。
