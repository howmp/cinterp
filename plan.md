---
name: remaining-c-features
overview: 仅保留尚未完成的 C/ABI 和运行时工作；_Complex、GCC builtins、VM 级 atexit/signal 已明确不作为目标。
---

# 剩余特性计划

## 1. P2：重新分诊 excluded 与跨 ABI

- 重新运行 `.excluded` 中已具备条件的 varargs/vector 用例，能通过则回收；GCC builtin 相关不回收。
- 跨 ABI 从 17-case csuite + 12-case upstream smoke 扩到可移植上游子集。
- 每个 excluded/skip 保留原因；不自动更新 expected。

## 2. 明确非目标

- `_Complex`：明确不支持。
- GCC builtins：明确放弃，不纳入计划。
- 可增长线性内存与配额：明确放弃；继续使用固定 `MAX_MEM`/`MAX_STACK`/`MAX_FRAMES`/`MAX_MODULE` 和现有 OOM/资源错误码。
- 生成式失败最小化已实现（P2）：见 `dev.md` §20.10；不再列为计划项。
- 外部 `inline`/weak 符号地址语义：不作为目标。产品只要求调用真实导出的外部符号；`static inline`/IR 中已有函数体继续解释执行。weak 未定义=0、COMDAT 选择、跨 TU inline 链接和函数地址身份不实现。
- CIB-to-CIB 链接：明确不支持。运行时只执行单个 CIB，外部符号仅来自系统库、`CIPI` provider 或显式 `--lib`；不把另一个 CIB 当目标文件/共享库解析。
- 多线程、原子操作、汇编/asm goto、向量类型、i128/vector ABI。
- Win64 vectorcall/COM、Win32 thiscall。
- 完整 GCC/LLVM 测试集和 SPEC 等商业 benchmark。
