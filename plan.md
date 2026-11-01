---
name: remaining-quality-performance-work
overview: 剩余 excluded 审计，以及 plan 外的 GCC execute 运行失败、TCC mismatch/compile 和编译器 batch/daemon 性能工作；基线见 dev.md §20.17。
---

# 剩余工作

## 1. GCC compile excluded 分类

- 逐类审计 605 行：gnu89/implicit-int/K&R（non-goal）、warning-first（重新观察真实原因）、resource、asm、vector、builtin。
- 不新增 gnu89/vector/builtin lowering；仍可回收因已实现能力而实际通过的用例。
- 禁止用 clang warning 或 traceback 作为原因，禁止自动更新 expected。

## 2. CompCert/TCC 候选归档

- CompCert include-skipped：55 通过 / 20 失败；TCC：97 通过 / 45 失败，已确认无新增安全回收。
- 将剩余项归入平台差异、外部 inline、诊断文本和 non-goal；不再期待代码回收。

## 3. GCC execute 52 个 run 失败

- 当前 `gcc-torture.skip` 有 52 个 run 失败，原因多只有 `exit N != 0`。
- 用 `--include-skipped --only` 重跑并保存 stderr/detail；按 `abort/segfault/timeout/engine limit` 聚合，而不是逐个修。
- 优先找共同根因；明确区分真实语义 bug、UB、asm/builtin/vector/threads non-goal。
- 验收：每个剩余失败有类别和最小复现；能修的共同根因修复并加入固定回归，不能修的明确 non-goal。

## 4. TCC 剩余 mismatch/compile

- 当前 TCC 45 个 skip（约 20 compile、24 mismatch、1 run）。
- 先区分 cinterp 语义 bug、Windows/平台差异、TCC 专有行为、诊断文本不一致和外部 inline/asm non-goal。
- 只回收标准 C 且 native/cinterp 实测通过的项；诊断文本一致性继续 non-goal。
- 验收：每项有分类；真实 bug 有最小复现；不新增 expected 弱通过。

## 5. 编译器 batch/daemon 性能

- 当前 Python 进程内编译和 CIB cache 已降低小套件开销，但 full 仍受 clang 子进程、runtime 启动和测试调度限制。
- 目标：一次 compiler 进程处理多个源文件，批量调用 clang（或缓存 IR），复用 link DB；避免每 case 启动 Python。
- 保留 `--inprocess` 作为单进程快速路径；batch 需支持 target、CPATH、错误隔离和 CIB 输出。
- 验收：full/standard 的 wall time 明显下降，输出/通过数完全一致；不改变 CIB 格式和测试 expected。
- Rust 重写暂不启动，除非 profile 证明 batch/cache 后 lowering 仍是主瓶颈。

## 6. 验收与边界

- 所有剩余 excluded/skip 行有可审计类别和原因。
- full 相对 **4286/4519（233 skip）** 无回归；新回收项必须实测通过并记录 ID。
- 不新增 expected 弱通过，不扩大 gnu89/vector/builtin 范围。
- 多线程/原子/汇编/vector/`_Complex`/外部 inline weak/CIB-to-CIB/可增长内存继续 non-goal。
