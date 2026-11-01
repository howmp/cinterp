---
name: remaining-c-features
overview: VLA/柔性数组、C11 编译期特性、external data 和可修复的 stdio 行为已完成；本文件只保留剩余未完成项和 host-libc reference 差异。
---

# 剩余特性计划

> **状态（2026-10-31）：VLA/FAM、C11 编译期特性、external data、stdio 可修 bug 已完成。**
> 完成证据见 `dev.md` §20.4。当前 full 4221/4457（236 skip），standard 396/495。

## 0. 当前基线

- full：4221/4457 通过，236 skip；standard：396/495。
- csuite 17/17；Win64/Win32/ARM64 的 csuite 17/17，upstream smoke 12/12。
- 已完成：VLA/FAM、`_Generic`/`_Static_assert`/`_Alignas`/`_Alignof`/static inline、external data 基础/Windows UCRT 辅助、`strtol/wcstol` 非法 base shim。
- host-libc reference 差异：`fscanf/sscanf/fnmatch/strftime/mbc/clocale` 的剩余 musl expected 与原生 glibc 一致地不同；只有在提供 musl provider 时才应重新纳入语义比对。

## 1. P0：`_Complex`

- float/double/long double complex 表示、大小/对齐。
- `+ - * /`、一元负号、实虚部访问、转换。
- SysV/Win64/Win32/AArch64 参数和返回 ABI；NaN/Inf/混合类型测试。
- 验收：四 ABI csuite complex 回归；GCC/CompCert complex skip 清零或明确范围外。

## 2. P1：`atexit` 与退出清理

- VM 退出时 LIFO 执行 `atexit` 回调。
- 覆盖 main return、显式 `exit`；构造函数/析构函数作为独立 GNU 扩展评估。
- 验收：TCC `128_run_atexit` 标准部分通过；退出码/stdout 顺序正确。

## 3. P1：`signal` 基础

- 使用现有静态 trampoline 支持 `signal`/`raise` 的进程内同步信号。
- 不做线程、异步信号安全扩展；明确与 `--safe` 的互斥。
- 验收：TCC `114_bound_signal` 可支持部分通过或明确排除。

## 4. P1：非汇编 builtins

- `__builtin_expect`、`__builtin_constant_p`、`__builtin_unreachable`。
- `bswap/ffs/clz/ctz/popcount`、`alloca`、`trap`（产品语义允许时）、`prefetch`（no-op）。
- 验收：GCC builtin 运行失败下降；不支持的 builtin 编译期明确报错。

## 5. P1：`inline` 链接边界与弱符号

- 当前 static inline 已支持；外部 `inline`/weak 符号地址（TCC 104/104+）仍不具备完整链接语义。
- 评估 weak symbol 表、COMDAT 和 external function pointer 的结合；不引入动态链接器改动以外的平台假设。
- 验收：标准 inline 用例通过；weak 地址语义有明确实现或范围说明。

## 6. P2：ABI callback 边角

- HFA callback >2 向量、long double callback、复杂聚合参数/返回。
- 验收：四 ABI callback 回归；不支持组合明确报错。

## 7. P2：可增长线性内存与配额

- 固定 1 MiB 线性内存改为可配置/可增长模型。
- per-package stack/frame/plan/import/callback/库句柄配额；保留 `--safe` 边界。
- 验收：OOM/配额压力测试和恶意 CIB 负路径。

## 8. P2：重新分诊 excluded 与跨 ABI

- 重新运行 `.excluded` 中已具备条件的 varargs/vector/builtin 用例，能通过则回收。
- 跨 ABI 从 17-case csuite + 12-case upstream smoke 扩到可移植上游子集。
- 每个 excluded/skip 保留原因；不自动更新 expected。

## 9. P2：生成式失败最小化

- YARPGen/Csmith artifact 做 creduce/内置 delta-debugging。
- 修复共同根因后加入固定回归；nightly 100 seeds 保持 0 未分类 failure。

## 10. host-libc reference 决策

- `fscanf/sscanf/fnmatch/strftime/mbc/clocale` 的剩余差异已由原生 glibc 复现，当前不作为 cinterp bug 修复。
- 若产品要求 musl 语义，应引入显式 musl provider/参考目标，而不是改 expected 或改 skip 冒充通过。

## 11. 非目标

- 多线程、原子操作、汇编/asm goto、向量类型、i128/vector ABI。
- Win64 vectorcall/COM、Win32 thiscall。
- 完整 GCC/LLVM 测试集和 SPEC 等商业 benchmark。
