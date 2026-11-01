---
name: remaining-c-features
overview: 保留 excluded/跨 ABI 重分诊的审查结论、P2a/P2b/P2c 拆分、执行前置条件、回收候选和待确认决策；已完成项与非目标见 dev.md。
---

# 剩余工作：excluded 重分诊与跨 ABI

> 子 agent 只读审查结论（2026-10-31）。当前 full 4219/4457，238 skip；标准集 394/495。
> 不要直接批量重跑/改 expected：先补 runner 能力，再逐项回收。

## 0. 结论先行

原计划的一项应拆成三项，按顺序执行：

1. **P2a：excluded 重分诊与证据修复**（优先，低风险、可量化）
2. **P2b：跨 ABI 可移植子集扩展**（依赖 P2a 后的稳定 manifest）
3. **P2c：FP/NaN 真实缺陷 bucket**（不要把已知错误结果继续归为 non-goal）

`-std=gnu89`、musl 参考目标、编译器诊断文本一致性暂不作为默认范围，待产品确认。

## 1. P2a：excluded 重分诊

### 1.1 当前 excluded 规模

| 文件 | 数量 | 说明 |
| --- | ---: | --- |
| `gcc-torture.excluded` | 454 | 约 317 compile + 137 run |
| `gcc-torture-compile.excluded` | 609 | compile-only |
| `compcert.excluded` | 34 | 多数缺少参考输出，应进入 compile 子集 |
| `tcc-tests2.excluded` | 1 | `99_fastcall` inline asm 边界 |

### 1.2 先修证据/工具，不要直接回收

- `scripts/test_suites.py` 目前没有 `--include-excluded`；`.excluded` 在 discovery 阶段直接丢弃，无法重跑。
- 没有 `--only ID,...`，无法只确认候选。
- 没有 `--emit-reasons PATH`；应输出 `ID<TAB>status: reason`，由人审阅后修改列表。
- 失败 reason 取 stderr 第一行，常把 clang **warning** 当成原因；应优先 `error:`/`fatal error:`/`^cinterp:`，并保存 detail。
- `gcc-torture-compile.skip` 是 609 个 excluded ID 的重复；只删 `.excluded` 会被 skip 文件重新跳过，必须先将其缩成 header-only。
- 5 个编译器 Python **traceback** 被记录成 unsupported feature；应先改成干净的 resource/compiler 诊断。
- 建议先实现：`--include-excluded`、`--only`、`--emit-reasons`；可选 `repo_skip_file_by_target` 供 P2b 使用。
- 不自动更新 expected/skip；回收时只删除已经确认通过的 excluded 行，保留 diff 和审查报告。

### 1.3 优先回收候选

- **varargs（约 56 个）**：`va-arg-*`、`stdarg-*`、`9xxxxx-*`、`pr44942`、`pr64979`、`*vprintf*` 等。varargs/`va_copy` 已实现，预计 25–45 个可回收；`va-arg-trap-1` 仍因故意 trap 排除；`*chk` 变体需确认 `__printf_chk` provider。
- **HFA coerce 残留**：`20071102-1`、`981223-1`、`pr55921`、`pr38969`；先区分 HFA struct 与真正的 `_Complex`。
- **近期能力覆盖的 skip**：`tcc-tests2:128_run_atexit`、CompCert `aligned/alignglob/alias/attribs1`、chibicc 的 `alignof/float/pointer/initializer/variable/commonsym`。
- **`gcc-ieee` FP bucket**：`cdivchkd`、`copysign1`、`copysign2`、`inf-4`、`pr108540-1`、`pr109386`；这些是真实语义问题，转入 P2c。

### 1.4 P2a 验收

- 每个剩余 excluded/skip 行有分类（non-goal/dialect/diagnostics/resource/host/bug）和观察记录。
- 不再有以 clang warning 或 Python traceback 作为原因的行。
- `gcc-torture-compile.skip` 不再复制 excluded 列表。
- full 相对 4219/4457 无回归；确认回收的 ID 列表写入提交信息，expected/compare 标志不变。
- 优先目标：净回收 ≥40 个通过用例。

## 2. P2b：跨 ABI 子集

### 2.1 现实目标

当前每目标：csuite 17 + c-testsuite/TCC/GCC/CompCert smoke 各 12。
建议扩到每目标约 145：

| suite | 现在 | 建议 | 选择规则 |
| --- | ---: | ---: | --- |
| csuite | 17 | 17 | 保持 |
| c-testsuite-smoke | 12 | 40 | 算术/循环/struct/指针；无 `%p`/`%zu`/argv |
| gcc-smoke | 12 | 40 | 从 native 已通过用例选，无 libc/指针宽度依赖 |
| compcert-smoke | 12 | 24 | 纯 C、有固定 Results；避开 math/float |
| tcc-smoke | 12 | 24 | 基础算术/指针/数组；避开 asm/backtrace/bound/sizeof 输出 |

### 2.2 策略与坑

- 用 per-case `cases` 列表和 `skip_by_target`；不新增 per-target expected 文件。
- Win32 是 ILP32：排除 `sizeof(void*)`/`size_t`/`%p`/指针地址输出。
- ARM64/x86 的 long double、`%Lf`、f128/f80 行为不同：排除相关用例。
- helper library（chibicc/libc-test）跨目标未接线；不要在本项强行支持。
- Windows 每 case 一次 ssh/scp；扩展后应批量传输或限制 nightly。
- Windows abort/SEH 退出码与 Linux 不同；不要把 Linux skip 文本照搬。
- qemu 需要 sysroot，超时应按套件调整。
- P2b 验收：每目标 ≥140 case，全部通过或有 per-target 原因；总 nightly 时长可接受。

## 3. P2c：FP/NaN 真实缺陷

- 单独跟踪 `gcc-ieee` 的 `cdivchkd`、`copysign1/2`、`inf-4`、`pr108540-1`、`pr109386`。
- 这些不是 builtin/asm 非目标；修复后加固定回归并删除对应 skip。
- 5 个 compiler traceback 先改成 clean resource/compiler error，再决定是否修复。

## 4. 待确认决策

1. **C 方言**：是否接受 `-std=gnu89`（implicit int/K&R）？接受可多回收约 150+ compile-only 用例，但改变产品接受的 C 方言；默认不纳入。
2. **vector 含义**：计划中的 vector 指 HFA-coerced struct（已支持），还是 C vector/FMA/i128（明确非目标）？
3. **诊断一致性**：TCC `60_errors_and_warnings` 等断言编译器错误文本的用例，是否明确 non-goal？
4. **跨 ABI 优先级**：约 145/target 放 nightly，还是 PR 也跑？
5. **runner 变更**：是否批准新增 `--include-excluded`、`--only`、`--emit-reasons`？

## 5. 明确非目标

- `_Complex`；GCC builtins（不再回收）。
- 可增长线性内存/配额；固定 `MAX_*` 上限。
- 外部 inline/weak 地址、COMDAT、跨 TU inline、函数地址身份。
- CIB-to-CIB 链接。
- 多线程、原子操作、汇编/asm goto、向量类型、i128/vector ABI。
- Win64 vectorcall/COM、Win32 thiscall。
- 完整 GCC/LLVM 测试集和 SPEC 等商业 benchmark。

## 6. 建议执行顺序

1. 补 runner 三能力 + 清理重复 skip + reason 分类。
2. 用 `--include-excluded --only` 重跑 varargs/HFA 候选，回收 Tier A。
3. 把 FP/NaN 缺陷拆到 P2c，修一个共同根因并加回归。
4. 稳定 native manifest 后，再扩跨 ABI 子集和传输方式。
5. 最后处理方言/诊断一致性等产品决策。
