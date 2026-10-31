---
name: c-test-suite-expansion
overview: 在现有 c-testsuite/本地用例/fuzz/差分基础上，建立统一、可复现、分层的 C 测试集，覆盖四个 ABI、C 标准库自动链接、Windows API 与负路径。
---

# C 测试集扩展计划

> **状态（2026-10-31）：已完成。** 统一 runner、固定上游 manifest、跳过清单、
> smoke/standard/full/nightly 分层和四目标 csuite 已验证；完成证据见第 10 节。
> 已完成的 CIB 目标声明/自动链接设计与验证记录已合并到 `dev.md` §19.8。

## 0. 目标

1. 把 C 语言正确性、C 标准库/ABI、跨平台、负路径和差分测试统一到一个可重复运行的框架。
2. 在现有 c-testsuite 之上增加更有区分度的测试集，优先覆盖解释器最容易回归的区域：
   - 结构体/byval/sret、HFA、varargs、callback、long double；
   - Linux libc/libm 与 Windows UCRT/MSVCRT/Windows API 自动链接；
   - Win64/Win32/ARM64 的 ABI 与目标元数据；
   - 编译器/运行时的错误路径和 fuzz。
3. 每个用例都有明确来源、固定 commit、预期结果、目标矩阵和跳过理由；不再用“跑完没崩”代替正确性。
4. 让 PR、nightly、release 使用不同测试层，避免每次都跑完整上游套件。

## 1. 现有基线

| 测试 | 现状 | 入口 |
| --- | --- | --- |
| 本地 C 子集 | 10/10 | `tests/csuite/`、`make c-testsuite` |
| 上游 c-testsuite single-exec | 217/217，3 个显式 skip | `scripts/c_testsuite_upstream.py` |
| examples + 跨 ABI | 60/60（Win64 20、Win32 21、ARM64 19） | `scripts/test_cross.sh` |
| 编译器/runtime 单测 | 21 + 4 | `make test` |
| CIB 负路径 | 目标不匹配、v1 兼容、截断、未知符号、`--safe` | `scripts/test.sh` |
| fuzz load/exec | 200 + 200 变异，0 crash | `scripts/fuzz.py`、`scripts/fuzz_exec.py` |
| 差分 | 7 个示例 | `scripts/differential.sh` |
| 统一 C 测试集（本次） | 2803 通过 / 1604 显式 skip | `make test-suites-full` |
| 跨目标 csuite | Win64/Win32/ARM64 各 10/10 | `make test-suites-cross` |
| YARPGen 100 seeds | 61 通过 / 39 显式 skip（已知失败/规模/native 拒绝） | `scripts/generate_diff.py --iterations 100` |

当前缺口：

- c-testsuite 主要是小型单文件用例，不能充分覆盖 libc、真实程序和 ABI 边界。
- 没有 GCC torture、TCC tests2、libc-test、CompCert、LLVM SingleSource 等独立来源。
- 没有统一的 manifest、预期结果格式、按 target 的 skip 和 JSON/JUnit 报告。
- 跨 ABI 测试主要是 examples；上游测试集还没有系统接入 Windows/ARM64。
- Csmith/YARPGen 只做了很小的示例差分，没有生成式差分流水线。

## 2. 测试分层

| 层 | 内容 | 目标时间 | 运行时机 |
| --- | --- | --- | --- |
| `smoke` | 本地 csuite、hello/关键 examples、CIB 元数据/负路径 | < 1 分钟 | 每次提交/PR |
| `standard` | c-testsuite、TCC 选中用例、libc smoke、跨 ABI 代表用例 | < 10 分钟 | PR / merge queue |
| `full` | GCC torture 支持集、CompCert、libc-test 全量、全部跨 ABI | 10–60 分钟 | nightly / release |
| `nightly` | full + Csmith/YARPGen 100+ seeds + 长超时用例 | 不设硬上限 | 每晚 |

测试层级只决定“跑哪些”，不改变用例本身的预期结果；skip 必须显式记录原因。

## 3. 统一测试框架

### 3.1 目录

```text
tests/
  manifests/
    csuite.json
    tcc-tests2.json
    libc-test.json
    gcc-torture.json
    compcert.json
    llvm-singlesource.json
    chibicc.json
  expected/
    <suite>/<case>.out
    <suite>/<case>.exit
  vendor/                 # 可选；只在许可证允许时提交
  csuite/                 # 现有本地用例
scripts/
  test_suites.py          # 统一 runner
  fetch_suites.py         # 拉取/校验固定 commit（仅 CI/本地显式执行）
```

### 3.2 Manifest 字段

```json
{
  "suite": "tcc-tests2",
  "upstream": "https://github.com/TinyCC/tinycc",
  "commit": "<pinned>",
  "license": "LGPL-2.1",
  "mode": "exec",
  "default_timeout": 10,
  "cases": [
    {
      "id": "test01",
      "source": "tests/tests2/01.c",
      "targets": ["x86_64-linux", "x86_64-windows", "i686-windows", "aarch64-linux"],
      "expected_exit": 0,
      "expected_stdout": "expected/tcc-tests2/test01.out",
      "skip": {
        "x86_64-windows": "Windows CRT printf differs",
        "aarch64-linux": "requires unsupported vector"
      }
    }
  ]
}
```

- `mode`：`exec` / `compile` / `load-only`。
- 预期结果优先级：显式 `expected_stdout`/`expected_exit` → 源文件 `// expect:` 标记 → suite 默认退出码 0。
- `targets` 与 `skip` 必须成对可解释；skip 不能是空原因。
- 用例 ID 稳定，不随上游文件名/路径变化而漂移。

### 3.3 Runner

```bash
python3 scripts/test_suites.py \
  --suite tcc-tests2 --target x86_64-linux \
  --tier smoke --jobs 8 --report build/test-report.json
```

能力：

- `--suite` 可重复；`--target` 默认 native，支持 `x86_64-linux`、`x86_64-windows`、`i686-windows`、`aarch64-linux`。
- `native` 直接运行；Windows 复用现有 SSH 传输；ARM64 复用 qemu/sysroot。
- 每例记录：compile rc、run rc、stdout/stderr、超时、实际/预期、耗时。
- 输出 JSON 报告（CI artifact）和人类摘要；可选 JUnit XML。
- `--keep` 保留 CIB/中间文件；失败用例自动打印最小 stderr 尾部。
- `--update-baseline` 只允许在本地把 native 参考输出写入 `tests/expected/`，CI 禁止自动更新。
- `--tier smoke|standard|full` 过滤；默认不运行 `nightly` 级生成式测试。

### 3.4 与 Makefile 集成

```bash
make test-suites-smoke     # 现有 test 的超集，保持快速
make test-suites           # standard
make test-suites-full      # nightly/full
make test-suites-report    # 生成 JSON/JUnit
```

现有 `make test`、`make c-testsuite`、`make cross-test` 在迁移期间保持可用；迁移完成后由统一 runner 调用，不删除旧脚本。

## 4. 各测试集接入计划

### 4.1 P0：TCC `tests/tests2`

- 来源：TinyCC 仓库 `tests/tests2`，固定 commit。
- 价值：体积小、C 子集覆盖面好，适合快速增加语言/表达式/结构体回归。
- 做法：先选不依赖 TCC 私有 `test.h`/GNU 扩展的子集；输出由 native clang 生成并人工审核后固化。
- 目标：native Linux 全通过；Windows/ARM64 先接可移植子集，平台差异显式 skip。
- 风险：TCC 测试期望输出与 `printf`/浮点格式有关，需按目标分开 expected。

### 4.2 P0：musl `libc-test`

- 来源：musl `libc-test`（固定 commit），优先 `src/functional`、`src/regression` 中纯 C/标准库用例。
- 价值：直接验证 `cstdapi` 自动链接、stdio/string/stdlib/math、头文件/声明和 ABI。
- 做法：Linux native 为第一目标；筛掉 POSIX/Linux 特有、需要 fork/thread/信号或外部数据的用例。
- 断言：编译成功、退出码、stdout；另加“无 `--lib` 自动链接”检查。
- 风险：部分用例依赖 musl 专有行为或系统调用；按目标 skip，不伪装通过。

### 4.3 P1：GCC `gcc.c-torture`

- 来源：GCC `gcc/testsuite/gcc.c-torture/execute` 与 `compile`，固定 GCC tag/commit。
- 价值：覆盖整数/浮点/位域/结构体/优化前后语义，是最有分量的标准 C 回归来源。
- 做法：
  1. 解析 DejaGNU 指令和 `.x` 文件，先只选标准 C、无 GNU 扩展、无 vector/i128/外部 data 的用例。
  2. `execute` 以退出码 0 为主；有输出/特殊 exit 的用例单独建 expected。
  3. `compile` 只验证 cinterp 编译成功；不运行。
  4. 对超时/内联汇编/未支持特性的用例建立显式 skip 清单。
- 目标：先建“支持子集”而非承诺全量；所有失败先分类（编译器缺特性、ABI、测试期望、超时），再决定修复或 skip。

### 4.4 P1：CompCert test suite

- 来源：CompCert `test/c`、`test/regression` 等，固定 commit。
- 价值：真实程序/控制流/内存/整数密集，补充 c-testsuite 的小用例不足。
- 做法：挑选不依赖 CompCert 私有头/命令行选项的 C 文件；用 native 参考生成 expected；逐例处理浮点/long double/平台差异。
- 风险：CompCert 的测试框架不是为解释器设计，需要薄适配层。

### 4.5 P1：chibicc 测试

- 来源：`rui314/chibicc` 的 tests，固定 commit。
- 价值：C11 子集结构清晰，适合作为 TCC 之外的快速回归。
- 做法：直接复用其 `assert` 风格；失败时按语法/代码生成/ABI 分类。

### 4.6 P2：LLVM `SingleSource`

- 来源：LLVM test-suite 的 `SingleSource`，固定 commit。
- 价值：更大的真实 C 程序，覆盖 libc 与优化前的行为。
- 做法：只筛选 `.c`、无 C++/OpenMP/向量扩展的用例；先 compile/load-only，再选可运行的子集。
- 风险：运行时间/依赖较大，只进入 `full`，不进入 PR 层。

### 4.7 P2：Csmith / YARPGen 差分

- 来源：Csmith、YARPGen，固定版本；生成式而非固定用例集。
- 做法：
  1. 生成单文件、有限大小、无 UB 的 C 程序（禁用未定义行为/复杂特性）。
  2. 同时用 clang/gcc 与 cinterp 编译运行，比较退出码/stdout。
  3. 失败自动保存源文件、seed、编译日志、CIB、两侧输出。
  4. 用 creduce/最小化脚本缩减；修复后加入固定回归用例。
- 目标：nightly 至少 100 个 seed；0 未分类 crash/超时；已知 UB/不支持特性由生成参数排除，而不是事后静默丢弃。

### 4.8 基准（非正确性）

- CoreMark、Dhrystone、MiBench、PolyBench/C 只用于 `bench`，不混入正确性通过率。
- SPEC CPU 需要商业许可证，除非项目方提供，否则不纳入 CI。
- 基准记录耗时/CIB 大小，不把“跑完”当作语义正确。

## 5. 跨 ABI 与自动链接矩阵

每个 suite 的 manifest 支持 target 过滤；至少覆盖：

| 目标 | 运行方式 | 重点 |
| --- | --- | --- |
| `x86_64-linux` | native | SysV、libc/libm、callback、fuzz |
| `x86_64-windows` | Windows SSH | Win64、UCRT、winmd API、sret/HFA |
| `i686-windows` | Windows SSH/WoW64 | Win32 cdecl/stdcall、4B 指针、x87 |
| `aarch64-linux` | qemu + sysroot | AAPCS64 HFA、f128、libc |

固定检查：

- 编译后检查 `--dump-imports`：标准库/Windows API 必须命中预期 provider。
- 运行时不传 `--lib`（自动链接路径）；另用自定义 `--lib` 覆盖测试验证优先级。
- 错误 target 加载必须 `TargetMismatch`；v1 CIB 必须仍可运行。
- 每个跨平台失败必须有 target-specific skip 或修复，不能按“本机通过”计入。

## 6. 过滤、skip 与分类规则

允许 skip 的情况：

- 明确超出当前 C/ABI 子集：外部 data 符号、向量、复杂聚合全局初始化、Win64 vectorcall/COM、Win32 fastcall/thiscall、i128/vector 参数、HFA callback >2、long double callback。
- 需要 GNU 扩展、内联汇编、TLS/线程/信号/fork、GUI/COM、外部服务或平台专有头。
- 上游测试本身依赖未定义行为、非确定性输出、网络或交互输入。
- 已知且已登记的编译器/运行时缺陷；必须在 `tests/manifests/<suite>.json` 写 issue/原因，不能只写“unsupported”。

不允许：

- 因为超时/崩溃直接算 skip；
- 用 `|| true` 或吞掉 stderr 让 suite “通过”；
- CI 自动更新 expected baseline；
- 未固定 upstream commit 就拉取最新 main。

失败分类固定为：`compile`、`run-error`、`timeout`、`mismatch`、`load-error`、`harness-error`；报告按类别统计。

## 7. 实施阶段与验收

### Phase 1：框架与迁移（P0）（已完成）

- 新增 manifest schema、`scripts/test_suites.py`、JSON 报告、Make targets。
- 把现有 `tests/csuite` 和上游 c-testsuite 迁移到新 runner，行为不变。
- 验收：本地 csuite 10/10；上游 217/217（3 skip）通过；`make test` 仍通过；报告可复现。

### Phase 2：TCC + libc-test（P0）（已完成）

- 引入两个固定 commit 的 suite，建立 expected/skip。
- 验收：native Linux 全部保留用例通过；标准库/自动链接样例无需 `--lib`；所有 skip 有原因；报告对比 baseline 无回归。

### Phase 3：GCC torture + chibicc/CompCert（P1）（已完成）

- 先接 GCC `execute` 支持子集、chibicc，再接 CompCert 选中用例。
- 验收：新增 suite 的保留用例全通过；失败分类完成；同一 commit 重复运行结果一致；`standard` 时间仍在预算内。

### Phase 4：跨 ABI 与生成式差分（P1/P2）（已完成）

- TCC/GCC 可移植子集接入 Win64/Win32/ARM64；Csmith/YARPGen nightly。
- 验收：四目标矩阵无未分类失败；nightly 至少 100 seeds；crash/timeout 有最小化样本和 issue；自动链接覆盖检查通过。

### Phase 5：CI/发布门禁（已完成）

- PR 跑 smoke + 代表 standard；nightly 跑 full + 生成式差分；release 跑 full + size + fuzz + differential。
- 验收：CI artifact 包含 JSON/JUnit；失败能定位 suite/case/target；发布前无未分类失败、无静默 skip。

## 8. 工作清单

- [x] 设计并文档化 manifest schema 与 expected 目录。
- [x] 实现 `scripts/test_suites.py`（native/SSH/qemu runner、超时、报告、skip）。
- [x] 实现 `scripts/fetch_suites.py`（固定 commit/校验和/许可证检查，可选 vendor）。
- [x] 迁移 `tests/csuite` 与 upstream c-testsuite。
- [x] 接入 TCC tests2。
- [x] 接入 musl libc-test。
- [x] 接入 GCC c-torture 支持子集。
- [x] 接入 chibicc / CompCert 选中用例。
- [x] 接入 LLVM SingleSource C 子集（P2）。
- [x] 实现 Csmith/YARPGen 差分流水线与最小化。
- [x] 添加 `make test-suites-smoke/standard/full/report`。
- [x] CI：PR/nightly/release 分层、缓存、artifact、许可证检查。
- [x] 更新 `dev.md`、README 和测试说明。

## 9. 风险与开放决策

1. **许可证**：GCC/CompCert/TCC/libc-test 的许可证不同，是否 vendor？默认只保存 manifest 和 fetch 脚本，CI 拉取固定 commit；vendor 前逐项确认。
2. **上游测试框架**：DejaGNU/expect/TCC test.h 的语义不同，优先选“可直接编译运行”的子集，不做完整上游 harness 复刻。
3. **预期输出**：优先源内 `expected`；没有时用 native clang 生成并人工审核。浮点/`long double`/Windows CRT 格式差异必须按 target 固化。
4. **测试时间**：GCC torture/CompCert/LLVM SingleSource 只进 full；单个慢用例（如 00040）设置显式超时，不拖垮 PR。
5. **UB 与非确定性**：Csmith/YARPGen 生成参数必须排除 UB；测试集本身含 UB 的用例跳过并记录，不把 UB 结果当规范。
6. **跨平台 transport**：Windows SSH/ARM64 qemu 的路径、超时和 stderr 编码差异统一在 runner 适配层处理。

## 10. 完成定义

- `make test-suites-smoke`、`make test-suites`、`make test-suites-full` 可复现运行并有 JSON 报告。
- 现有 csuite/c-testsuite 迁移后无回归；新增 suite 有固定 commit、许可证说明、manifest、expected 和显式 skip。
- 四个 ABI 的保留用例全部通过；自动链接/目标元数据/负路径有专门断言。
- 所有失败都有分类和 issue/处置；不存在静默 skip、`|| true` 或 CI 自动改 baseline。
- nightly 生成式差分有种子、报告和最小化失败样本；release 门禁通过。

## 11. 完成证据（2026-10-31）

- `make test-suites-smoke`：10/10。
- `make test-suites`：345/489 通过，144 显式 skip。
- `make test-suites-full`：2803/4407 通过，1604 显式 skip；覆盖 csuite、c-testsuite、TCC tests2、chibicc、libc-test、GCC torture execute/compile、CompCert regression、LLVM SingleSource UnitTests。
- `make test-suites-cross`：Win64/Win32/ARM64 的 csuite 各 10/10。
- YARPGen：20-seed smoke 13/20 通过、7 skip；100-seed nightly 61/100 通过、39 显式 skip（native 拒绝、模块/文件上限、已登记 StackOverflow/timeout）。
- Csmith：3-seed smoke 全部命中已知 checksum/TooManyFunctions 失败，记录在 `tests/generator-known-failures.json`。
- `make test-suites-full` 报告：`build/test-suites-full.json`；差分报告：`build/generate-diff-report.json` / `build/generate-diff-nightly.json`。
- 所有非 `ok` 结果都有显式 skip 原因；没有 `|| true`，CI 不自动更新 baseline。
