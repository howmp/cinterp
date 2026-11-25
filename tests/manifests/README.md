# 测试套件清单

每个 `*.json` 文件描述一个上游或本地 C 测试套件。运行器是
`scripts/test/test_suites.py`；源码由 `scripts/test/fetch_suites.py` 拉取到 `build/suites/`，
不内置在仓库中。

## 清单字段

| 字段 | 含义 |
| --- | --- |
| `suite` | 稳定的套件 ID |
| `description`、`upstream`、`commit`、`license` | 来源元数据，运行器不读取 |
| `root` | 套件根目录；`{SUITES}` 展开为 `build/suites`（或 `CINTERP_SUITE_ROOT`） |
| `source_glob` | 省略 `cases` 时，相对于 `root` 的文件 |
| `cases` | 显式用例列表（`id`、`source`，以及可选的期望字段） |
| `mode` | `compile` = 仅编译套件：包会被构建并校验，但从不执行（`gcc-torture-compile`、`compcert-compile`、`llvm-regression-c`、`llvm-singlesource`） |
| `expected_ext` / `expected_dir` | 期望的 stdout 位置；默认为源码旁边的 `.expected` |
| `expected_required` | 跳过没有参考输出的用例（CompCert 使用） |
| `compare_stdout` | 对于测试脚手架会打印断言杂讯的套件，设为 false |
| `normalize_source_paths` | 比较前把绝对的 `__FILE__` 路径替换为基本文件名 |
| `normalize_trailing_whitespace` | 比较语义行时忽略行尾空格 |
| `strip_compiler_diagnostics` | 丢弃上游编译器警告行（TCC 特有的期望） |
| `expect_marker` | 从源码中读取 `// expect: N` 并比较 VM 结果 |
| `expected_exit` | 期望的进程退出码；`null` 会关闭该检查 |
| `prelude` | 可选文件，会被前置到生成的包装器中 |
| `cpath` | 编译期间添加到 `CPATH` 的目录 |
| `case_args` | 每个用例额外的宿主 argv（`id` → 列表） |
| `support_lib` | 测试运行器预加载的共享库（chibicc/libc 脚手架） |
| `rewrite` | 仅供测试脚手架使用的字面源码重写（必须显式声明） |
| `tiers` | `smoke`、`standard`、`full`、`nightly` |
| `repo_skip_file` | 已提交到仓库的 `ID<TAB>reason` 跳过列表 |
| `skip` | 内联的 `id: reason` 映射 |
| `case_cc_opt` | 每个用例的 C 前端优化级别覆盖（只在 -O0 语义下有效的上游用例仍会运行，不跳过） |
| `skip_by_target` | 跨 ABI 套件中每个用例的 `target: reason` 映射 |
| `repo_exclude_file` | 已提交到仓库的 `ID<TAB>reason` 排除列表（完全不运行） |
| `timeout`、`compile_timeout` | 每个用例的实际耗时上限（秒） |

## 命令

```bash
python3 scripts/test/fetch_suites.py --all --support
make test-suites-smoke      # smoke tier: csuite only (18 cases)
make test-suites            # standard: csuite, c-testsuite, TCC, chibicc, libc-test
make test-suites-full       # adds gcc-torture(+compile), gcc-ieee, CompCert(+c/compile),
                            # LLVM UnitTests/regression-c, libc-test-regression
make test-suites-nightly    # all fixed suites (full + the four cross-target smoke suites)
                            # plus scripts/fuzz/generate_diff.py (YARPGen, 100 iterations)
make test-suites-cross      # csuite + the four smoke suites on Win64/Win32/ARM64 (146 cases each)
make generate-diff          # YARPGen differential smoke
```

层级归属取自每个清单的 `tiers` 列表：

| 层级 | 套件 |
| --- | --- |
| `smoke` | csuite |
| `standard` | csuite, c-testsuite, tcc-tests2, chibicc, libc-test |
| `full` | standard + gcc-torture, gcc-torture-compile, gcc-ieee, compcert, compcert-c, compcert-compile, llvm-singlesource, llvm-regression-c, libc-test-regression |
| `nightly` | full + c-testsuite-smoke, tcc-smoke, gcc-smoke, compcert-smoke |

在不修改基线的情况下重新分诊被排除的候选用例：

```bash
python3 scripts/test/test_suites.py --suite gcc-torture --include-excluded \
  --include-skipped --only va-arg-1,stdarg-1 \
  --emit-reasons build/triage-varargs.txt --report build/triage-varargs.json

# faster local reruns (content-addressed CIB cache)
python3 scripts/test/test_suites.py --tier full --jobs 8 --cib-cache build/cib-cache
```

`--include-excluded` 会绕过 `.excluded`，`--only` 接受以逗号分隔的 ID，
`--emit-reasons` 会写出可审计的 `ID<TAB>status: reason` 行。只能从已提交到仓库的
列表中删除经核实已通过的 ID；期望输出和比较标志必须保持不变。

## 跳过策略

- 生成的 `.skip` 文件中每个非 `ok` 条目都曾被观察到一次，并且带有原因。它是
  已知支持子集的跳过，而不是静默通过。
- 报告中的每个 skip 还会带有 `skip_class`：
  - `unsupported`：明确不支持的平台/语言/诊断特性；
  - `known-failure`：已观察到的 mismatch、崩溃、超时或错误返回，属于待修缺陷。
- `scripts/tools/check_plan_evidence.py` 会汇总 `skip_classes["known-failure"]`，不再把
  已知失败藏在单一 skip 数字里。
- `compile:` 表示编译器不支持的特性，或需要 GNU/扩展的上游测试；`runtime:` 是已知的
  运行时/ABI 失败；`mismatch:` 是已知的输出差异；`timeout:` 是资源/时间上限。
- 用修复替换跳过需要重新运行套件，并从跳过文件中删除该条目。CI 从不更新期望输出
  或跳过文件。
- 期望输出在 CI 中从不自动更新；按照设计，`--update-baseline` 并未针对这些清单实现。
- `.excluded` 文件比 `.skip` 更严格：被排除的 ID 在运行前就被移除，完全不会出现在
  任何报告中，因此它们既不算通过也不算跳过。用 `--include-excluded` 重新复核它们。

### 跳过 / 排除清单（2026-11-03）

- 11 个清单引用了 `repo_skip_file`。这些文件合计包含 **187** 行非注释的
  `ID<TAB>reason`；`c-testsuite.json` 的 2 条和 `llvm-regression-c.json` 的 2 条
  内联跳过另计，因此 `build/test-suites-full.json` 中共有 **191** 次跳过。
- `libc-test/pthread_tsd` 被跳过：它在 VM 执行期间从 worker 线程调用 VM
  callback；每 VM fail-fast 线程策略会有意跳过这种外部线程 callback。
- `tests/manifests/gcc-torture-compile.skip` 有八个条目：六个是超出运行时上限的仅编译
  压力用例（`limits-externdecl` >512 个导入，`pr37669-2` >64 个参数，`stuct` >2 MiB
  模块，以及 3 个 static data >16 MiB 用例），另两个是 vector 全局初始化
  （`simd-6`、`vector-align-1`）。`llvm-regression-c.json` 内联跳过 `pr60822`
  和 `20020107-1`。
- `tests/manifests/c-testsuite.skip` 是**孤立的**：没有任何清单引用它
  （`c-testsuite.json` 把它的两条跳过保留为内联），而独立运行器使用的是
  `tests/csuite/cinterp.skip`，不是这个文件。参见下面的 c-testsuite 小节。
- 4 个排除文件包含 **1034** 行非注释内容：
  `gcc-torture.excluded` 394、`gcc-torture-compile.excluded` 605、
  `compcert.excluded` 34、`tcc-tests2.excluded` 1。

## 清单卫生：重复 ID

重复的用例 ID 会静默地让用例运行两次并破坏报告，因此
`scripts/test/test_suites.py` 现在会直接拒绝它们
（`reject_duplicate_ids`）：包含重复 ID 的清单会使运行失败，并给出
重复 ID 列表。`--allow-duplicate-ids` 会将其降级为警告并
保留第一次出现的条目，仅用于对未修改清单的本地分诊。

`llvm-regression-c.json` 在那些 `#include` 它们的用例旁边，包含了 LLVM 的
`SingleSource/.../builtins/lib/*.c` 支持文件。这些支持文件的
ID 曾与真正的测试用例冲突，因此它们被重命名并加上
`*-support` 后缀（共 20 个条目，例如 `memchr-support`）。清单现在包含
**935 个唯一的用例 ID**，与下面基线的 `llvm-regression-c` 行一致。

## 当前原生基线（2026-11-03）

在 `x86_64-linux` 上运行 `make test-suites-full`；这些数字直接读取自
`build/test-suites-full.json`（`tier=full`，`counts = {ok: 4331, skip: 191}`，
共 4522 条结果）。TCC 的参考输出会针对绝对的 `__FILE__`
路径、行尾空格和 TCC 编译器警告做归一化处理；这样在不削弱语义比较的前提下
多恢复了 4 个用例。

| 套件 | 用例数 | 通过 | 跳过 | 备注 |
| --- | ---: | ---: | ---: | --- |
| csuite | 18 | 18 | 0 | 本地子集，`// expect:` 标记 |
| c-testsuite | 220 | 218 | 2 | 内联跳过（`00204`、`00216`） |
| tcc-tests2 | 142 | 99 | 43 | |
| chibicc | 41 | 17 | 24 | |
| libc-test | 75 | 46 | 29 | `pthread_tsd` 因外部线程 callback 的 fail-fast 策略跳过 |
| libc-test-regression | 69 | 48 | 21 | |
| gcc-torture | 1306 | 1299 | 7 | 执行类用例 |
| gcc-torture-compile | 1411 | 1403 | 8 | 仅编译（`mode: compile`）；含 6 条运行时/资源上限与 2 条 vector 全局初始化 skip |
| gcc-ieee | 79 | 64 | 15 | |
| compcert | 75 | 59 | 16 | |
| compcert-c | 24 | 12 | 12 | 慢 benchmark 全部 unsupported/deferred |
| compcert-compile | 34 | 30 | 4 | 仅编译（`mode: compile`） |
| llvm-singlesource | 93 | 85 | 8 | 仅编译（`mode: compile`） |
| llvm-regression-c | 935 | 933 | 2 | 仅编译（`mode: compile`），已去重 ID；2 条 inline skip |
| **总计** | **4522** | **4331** | **191** | |

### 仅编译部分

套件设置了 `"mode": "compile"` 的用例会被构建并校验，但从不执行，
因此它们不能证明程序行为：

| 套件 | 通过 |
| --- | ---: |
| gcc-torture-compile | 1403 |
| llvm-regression-c | 933 |
| compcert-compile | 30 |
| **按仅编译统计的小计** | **2366** |
| llvm-singlesource（同样是 `mode: compile`） | 85 |
| **所有编译模式的通过数** | **2451** |

其余 4331 − 2451 = **1880** 次通过是可执行用例，其 stdout /
退出状态 / `// expect:` 结果会与参考结果进行比较。

### 每日/交叉冒烟套件（不属于 4331 的一部分）

这四个冒烟套件只属于 `nightly` 层级；它们由
`make test-suites-cross` 和 `cross-abi` 工作流按目标分别执行，结果落在
`build/test-suites-cross-*.json` 中，而不是 `test-suites-full.json` 中：

| 套件 | 用例数 | 目标特定的跳过（`skip_by_target`） |
| --- | ---: | --- |
| c-testsuite-smoke | 40 | `aarch64-linux`：`00040`（qemu 超时） → 39 + 1 |
| tcc-smoke | 24 | `x86_64-linux`、`x86_64-windows`、`i686-windows`、`aarch64-linux`：`22_floating_point` → 23 + 1（Linux 因移除 f80/f128 支持，其余目标见清单） |
| gcc-smoke | 40 | 无 |
| compcert-smoke | 24 | `x86_64-windows`、`i686-windows`：`binops` → 23 + 1 |

`make test-suites-smoke`（smoke 层级）只运行 `csuite`（在宿主上为 18/18）。
生成的 YARPGen/Csmith 已知失败种子单独记录在
`tests/generator-known-failures.json` 中。YARPGen 白名单有一个
`slow` 条目（seed 24：cinterp 解释执行约 27 秒，空闲机器能完成，
CI 并发下超过 60 秒运行上限）。`slow` 条目只豁免运行超时：同一 seed
出现输出不一致或编译失败仍然算 failure，也不会因机器变快而报 stale。
超出已记录运行时上限的生成程序会被报告为
`cinterp engine limit:` 跳过，而普通白名单中的种子一旦开始通过，就会让
`scripts/fuzz/generate_diff.py` 因 stale 而失败。Csmith 映射仍有三个
条目。

## 上游 c-testsuite：两个不同的数字

`c-testsuite.json` 以 glob 方式收集 220 个单次执行的源码，并内联跳过两个
（`00204` 向量类型，`00216` 复杂聚合全局初始化器），因此
清单运行的结果是 **218 通过 / 2 跳过**，与基线表一致。

独立的 `scripts/test/c_testsuite_upstream.py` 仍然默认使用较旧的
`tests/csuite/cinterp.skip` 列表，该列表额外列出了 `00189`（需要
外部数据符号）。因此它的默认运行在同 220 个用例中是 **217 通过 / 3 跳过**。
这两个跳过列表并未统一：清单运行请引用 **218/2**，
只有独立脚本才用 **217/3**。不要对它们取平均，也不要声称单一数字。
