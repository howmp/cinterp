---
name: remaining-c-features
overview: 在已完成的支持集基线上，补 VLA/柔性数组、_Complex、C11 编译期特性、atexit/signal、非汇编 builtins、external data 和 ABI 边角；并扩大跨目标测试与生成式失败最小化。
---

# 未补齐特性计划

> **状态（2026-10-31）：计划中。** 已完成的支持集基线、测试基础设施、已补齐特性
> 和排除边界已迁移到 `dev.md` §20.2。本文件只记录尚未完成的特性。

## 0. 当前基线

- `make test-suites-full`：4172/4454 通过，282 skip（93.7%）；另有 1098 个显式排除的非目标用例。
- `make test-suites`：376/492；`make test` 通过。
- csuite 14/14；Win64/Win32/ARM64 的 c-testsuite/TCC/GCC/CompCert smoke 各 12/12。
- 已支持：SysV/Win64/Win32/AArch64、结构体/varargs FFI、callback、long double、fastcall、internal va_list、argv/envp、setjmp/longjmp、external data 基础。
- 明确不做：多线程、原子操作、汇编、向量、Win64 vectorcall/COM、Win32 thiscall。

## 1. 优先级总览

| 优先级 | 特性 | 主要价值 | 验收 |
| --- | --- | --- | --- |
| P0 | VLA + flexible array member | TCC 79/122、GCC/CompCert 常见 C99 | 对应用例通过，作用域/生命周期无回归 |
| P0 | `_Complex` | 标准 C11 数值类型 | 四 ABI 的算术、参数和返回通过 |
| P0 | C11 编译期特性 | `_Generic`/`_Static_assert`/`_Alignas`/`inline` | TCC/GCC 相关编译 skip 消除 |
| P1 | `atexit` 和退出清理 | 标准 C 生命周期 | TCC 128 等通过 |
| P1 | `signal` 基础 | 标准 C，非线程/非汇编 | TCC 114 等通过 |
| P1 | 非汇编 builtins | GCC 剩余运行失败 | builtins 子集通过 |
| P1 | external data 完整化 | `errno`/`environ`/`FILE*` | libc/stdio 用例提升 |
| P1 | stdio/wide char/locale | libc-test mismatch | 逐项分类修复 |
| P2 | ABI callback 边角 | long double/HFA callback | 多 ABI 回归 |
| P2 | 可增长线性内存/配额 | 真实程序资源 | 可配置上限且无回归 |
| P2 | 重新分诊 excluded | 回收已支持用例 | 排除清单缩小 |
| P2 | 完整跨 ABI 上游子集 | 质量保证 | 四目标真实子集 |
| P2 | 生成式失败最小化 | 可维护差分 | artifact + reducer + 固定回归 |

## 2. P0：VLA 与 flexible array member

### 工作项

- 补齐 VLA 的创建、`stacksave/stackrestore`、作用域退出和 reuse 语义。
- 支持结构体末尾 flexible array member 的布局、初始化、指针运算和 `sizeof`。
- 修正 VLA 在循环/分支/setjmp 中的生命周期；确保 `mem_top` 恢复正确。
- 覆盖数组声明、VLA 参数退化、`sizeof(VLA)`、多维 VLA。

### 验收

- TCC `79_vla_continue`、`122_vla_reuse` 通过。
- GCC/CompCert 中 VLA/柔性数组相关 skip 清除或明确分类。
- `make test`、csuite 四目标、full 无回归。

## 3. P0：`_Complex`

### 工作项

- 定义 float/double/long double complex 的表示和大小/对齐。
- 实现 `+ - * /`、一元负号、比较、实部/虚部访问和转换。
- 按 SysV/Win64/Win32/AArch64 ABI 处理参数和返回值（必要时用结构体/寄存器分类）。
- 添加复数边界测试：NaN/Inf、混合 real/complex、函数返回。

### 验收

- 四 ABI 的 complex 回归全部通过。
- GCC/CompCert 相关 complex skip 清零或有明确范围说明。
- 不引入 vector/asm 依赖。

## 4. P0：C11 编译期特性

### 工作项

- `_Generic` 选择和类型分支 lowering。
- `_Static_assert` 编译期错误。
- `_Alignas`/`_Alignof` 与 struct/union/global 对齐。
- `inline`/`static inline`/`extern inline` 链接语义；`_Noreturn`。
- 保持 clang 预处理输入，不引入完整 C 前端。

### 验收

- TCC 104 系列、GCC/LLVM 相关 compile skip 消除。
- 对齐/链接语义不破坏现有 struct/global/FFI 用例。

## 5. P1：`atexit` 与退出清理

### 工作项

- 实现 VM 退出时的 `atexit` LIFO 回调。
- 处理 `return from main`、显式 `exit` 和 native `exit` 的边界。
- 构造函数/析构函数只作为 GNU 扩展另行评估，不混入标准 `atexit`。

### 验收

- TCC `128_run_atexit`（标准部分）通过。
- 退出码、stdout 顺序和 callback 生命周期符合 C 语义。

## 6. P1：`signal` 基础

### 工作项

- 支持 `signal`/`raise` 的 C 回调注册，使用现有静态 trampoline 机制。
- 仅处理进程内同步信号/测试场景；不实现线程、信号安全或 async-signal-safe 扩展。
- 明确与 `--safe` 的互斥关系。

### 验收

- TCC `114_bound_signal` 的可支持部分通过或明确排除。
- 回调 trampoline 生命周期和重复注册无崩溃。

## 7. P1：非汇编 builtins

### 工作项

- `__builtin_expect`、`__builtin_constant_p`、`__builtin_unreachable`。
- `__builtin_bswap*`、`__builtin_ffs*`、`__builtin_clz*`、`__builtin_ctz*`、`__builtin_popcount*`。
- `__builtin_alloca`、`__builtin_trap`（若产品语义允许）、`__builtin_prefetch`（no-op）。
- 将可映射的 builtin 降为现有 opcode/内建函数，不引入汇编。

### 验收

- GCC 剩余 run failure 中的 builtin 类别下降。
- 新增 builtin 边界测试；不支持的 builtin 编译期报错并登记。

## 8. P1：external data 完整化

### 工作项

- `errno`/`__errno_location`、`environ`、`stdin/stdout/stderr`、`optarg/optind`、locale/时区全局。
- 对可写数据符号保持 `CIPI.kind=data` provider/`--lib` 解析和写权限语义。
- 区分系统数据符号与 harness 自定义全局，避免把未解析符号误判为外部数据。

### 验收

- libc-test/TCC 中 external data 相关用例明显提升。
- 外部数据地址在 load/store 中保持正确，`--safe` 仍拒绝。

## 9. P1：stdio / wide char / locale mismatch

### 工作项

- 优先处理 `snprintf/sscanf/strtol/wcstol` 等 libc-test mismatch。
- 区分 cinterp 语义 bug、libc 行为差异、格式化和 expected 差异。
- 补齐 `%Lf`/long double/NaN/±0/宽字符格式的 target-specific expected。

### 验收

- libc-test 剩余 mismatch 有类别和最小复现；稳定的真实 bug 修复。
- 不通过改 expected 掩盖语义错误。

## 10. P2：ABI callback 边角

- HFA callback >2 向量、long double callback、复杂聚合参数/返回。
- 以现有 static trampoline 和 ABI frame 为基础，不做动态可执行内存。
- 验收：四 ABI 的 callback 边角回归；不支持的组合明确报错。

## 11. P2：可增长线性内存与配额

- 将固定 1 MiB 线性内存改为可配置/可增长模型。
- 为 stack/frame/plan/import/callback/库句柄设置 per-package 配额。
- 保留 `--safe` 和恶意 CIB 的边界；增加 OOM/配额错误和压力测试。

## 12. P2：重新分诊 excluded 与跨 ABI

- `va_list`/`setjmp`/fastcall 已补齐，重新运行 `gcc-torture.excluded` 中可能已通过的 varargs/builtin 用例并回收。
- 将 TCC/GCC/CompCert 的跨 ABI 从 12-case smoke 扩为可移植子集。
- 每个 excluded/skip 条目保留原因；不要把尚未验证的用例直接转成通过。

## 13. P2：生成式失败最小化

- 对 YARPGen/Csmith artifact 做 creduce/内置 delta-debugging，保存最小源和 CIB。
- 修复共同根因后，将最小样本加入固定回归 suite。
- nightly 100 seeds 保持 0 未分类 failure；known failures 必须有 issue。

## 14. 验收与命令

```bash
make test
make test-suites
make test-suites-full
make test-suites-nightly
make test-suites-cross
make generate-diff
make generate-diff-nightly
make generate-diff-csmith
```

目标：在保持现有四 ABI 和 support-subset 基线不回归的前提下，优先完成 P0/P1 标准 C 特性；P2 用于扩大真实程序和跨目标覆盖。

## 15. 非目标

- 多线程、原子操作、汇编/asm goto、向量类型、i128/vector ABI。
- Win64 vectorcall/COM、Win32 thiscall。
- 完整 GCC/LLVM 测试集和 SPEC 等商业 benchmark。
