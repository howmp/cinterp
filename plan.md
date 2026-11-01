---
name: remaining-c-features
overview: 仅保留尚未完成的 C/ABI 和运行时工作；_Complex、GCC builtins、VM 级 atexit/signal 已明确不作为目标。
---

# 剩余特性计划

## 1. P1：外部 `inline` 链接与弱符号

- 外部 `inline`/weak 符号地址（TCC 104/104+）缺少完整链接语义。
- 评估 weak symbol 表、COMDAT 与 external function pointer 的结合。
- 验收：标准 inline 用例通过；weak 地址语义有明确实现或范围说明。

## 2. P2：重新分诊 excluded 与跨 ABI

- 重新运行 `.excluded` 中已具备条件的 varargs/vector 用例，能通过则回收；GCC builtin 相关不回收。
- 跨 ABI 从 17-case csuite + 12-case upstream smoke 扩到可移植上游子集。
- 每个 excluded/skip 保留原因；不自动更新 expected。

## 3. P2：生成式失败最小化

- YARPGen/Csmith artifact 做 creduce/内置 delta-debugging。
- 修复共同根因后加入固定回归；nightly 100 seeds 保持 0 未分类 failure。

## 4. 明确非目标

- `_Complex`：明确不支持。
- GCC builtins：明确放弃，不纳入计划。
- 可增长线性内存与配额：明确放弃；继续使用固定 `MAX_MEM`/`MAX_STACK`/`MAX_FRAMES`/`MAX_MODULE` 和现有 OOM/资源错误码。
- 多线程、原子操作、汇编/asm goto、向量类型、i128/vector ABI。
- Win64 vectorcall/COM、Win32 thiscall。
- 完整 GCC/LLVM 测试集和 SPEC 等商业 benchmark。
