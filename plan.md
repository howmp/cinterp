---
name: compiler-performance
overview: Plan 1–4 和 batch/daemon 性能工作已完成并验证；当前 full 4292/4519、standard 394/495。
---

# 编译器 batch/daemon 性能（已完成）

## 已完成

- Python `--inprocess`：复用解释器/link DB；csuite 约1.7x。
- 内容寻址 `--cib-cache`：修复 cache-hit 仍走子进程编译的问题；Makefile native suite 默认启用 `--inprocess --cib-cache`。
- `--batch`：批量 clang IR + 分 chunk 进程内 lowering；warm cache 跳过预编译，冷启动作为实验路径。
- 验收：full/standard 通过数不变（4292/4519、394/495），CIB 格式/expected 未改，4 ABI cross suites 保持通过。

## 后续（非当前目标）

- 若继续性能工作，进入 compiler daemon 或 Rust lowering；不再重复 Python 热循环优化。
