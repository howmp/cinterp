---
name: test-results-improvement
overview: 根据当前 4110/4453 通过、343 skip 的结果，按“先修真实缺陷和标准 C 语义，再扩跨 ABI/覆盖”的顺序提升测试通过率和诊断质量。
---

# 测试结果提升计划

> **状态（2026-10-31）：执行中。** P0 的 `fcmp`/float 转换、VM 上限、external data
> 与函数指针已落地；full 基线升到 **4090/5516（74.1%）**，csuite+c-testsuite smoke 在
> Win64/Win32/ARM64 均 12/12。仍剩 GCC 运行失败分诊、mismatch 收敛、生成式最小化等项。
> 统一测试集和 runner 见 `dev.md` §20。

## 0. 当前基线

| 套件 | 通过 | skip | 说明 |
| --- | ---: | ---: | --- |
| csuite | 12 | 0 | 四 ABI 各 12/12 |
| c-testsuite | 217 | 3 | 外部 data/向量/复杂全局初始化 |
| TCC tests2 | 84 | 59 | 23 compile、35 mismatch、1 run |
| chibicc | 14 | 27 | 20 compile、7 run |
| libc-test | 40 | 35 | 29 mismatch、3 compile、3 runtime |
| GCC torture execute | 1155 | 91 | 剩余运行缺陷；455 个非目标用例排除 |
| GCC torture compile | 1407 | 0 | 非目标编译用例已拆出 |
| CompCert regression | 41 | 68 | 16 compile、52 mismatch（含无 expected） |
| LLVM UnitTests | 85 | 8 | 全部 compile 失败 |
| GCC ieee | 59 | 20 | ieee 子集 |
| CompCert c | 12 | 12 | benchmark 选中子集 |
| LLVM Regression/C | 935 | 0 | compile-supported 子集 |
| libc regression | 49 | 20 | 选中子集 |
| **合计** | **4110** | **343** | skip 占 7.7%；另有 455 个明确排除 |

已识别的重点信号：

- 约 **91** 个 GCC execute 运行失败（另有 137 个 varargs/builtin/asm 用例已明确排除），很多只是 `run: exit 1 != 0`，缺少真实 stderr；样本里已经出现 `FrameOverflow`、`TooManyFunctions`、`SymbolNotFound`、`abort`。
- `fcmp une` 和 `fptoui/uitofp` 已实现，相关 skip 已移除；剩下一部分运行失败仍需分诊。
- external data 已支持 `stdout`/`t_status` 等基础场景；剩余未解析数据/函数指针仍需分诊。
- TCC/libc/CompCert 共约 **77** 个 stdout mismatch；必须区分真实语义 bug、浮点/printf 格式差异和上游 expected 差异。
- YARPGen 100 seeds：61 通过、39 skip；Csmith 3/3 命中已知 checksum/TooManyFunctions 失败。
- 跨 ABI 只系统验证了 csuite；上游套件仍是 native-only。
- fuzz 只有 200 变异；nightly CI 仍跑 20-seed diff，而不是 100-seed。

## 0.1 本轮已完成（2026-10-31）

- `fcmp` 全 ordered/unordered 谓词；`fptoui/uitofp` 的 f32/f64/f80/f128 路径。
- VM 上限提高：函数 512、帧 512、槽栈 8192、模块 2 MiB、plan 1024、参数 64。
- external data + 函数地址：`stdout`/`t_status`/`strcmp`/`memcpy` 等可通过 CIPI data/`--lib` 解析。
- 常见 LLVM 数学 intrinsic（fabs/round/ceil/floor/sqrt/fma/min/max 等）映射到 libc provider。
- csuite 增加 NaN、float 转换用例；新增 GCC ieee、CompCert c、LLVM Regression/C 支持子集和 c-testsuite 跨 ABI smoke。
- full 从 2803/1604 提升到 4110/343（支持集）；`make test-suites` 367/491；cross smoke 12/12 × 3。
- CI nightly 改为 `make test-suites-nightly`（含 100-seed 差分）；runner 报告增加 `error_class`。

## 1. 原则

1. **先修真实缺陷，再扩范围**：优先标准 C 语义、VM 资源上限和已确认的 ABI/运行时 bug；不把 vector/asm/atomics/i128/GNU 扩展当短期目标。
2. **skip 必须可审计**：每条 skip 带 `compile/runtime/mismatch/timeout/harness` 分类、原因和（可选）issue；不再用泛化的 `exit 1`。
3. **先补诊断再修**：运行失败必须保存 stderr、CIB、源文件、fixture 和最小复现；否则无法判断是 bug 还是资源限制。
4. **固定目标不漂移**：每个改进项都要用同一组 manifest/seed 重新跑，报告存 `build/`，不因为“本机通过”删 skip。
5. **不做假通过**：禁止 `|| true`、自动更新 expected、把超时/崩溃直接算 skip。

## 2. P0：VM 资源上限与诊断

### 2.1 现状

- `MAX_FUNCS = 8`，`MAX_FRAMES = 64`，`MAX_STACK = 1024`，`MAX_MODULE = 262144`。
- 实际失败样本：
  - GCC `20010122-1`：`TooManyFunctions`；
  - GCC `20000412-2`：`FrameOverflow`；
  - YARPGen 部分 seed：`StackOverflow`、`ModuleTooLarge`；
  - 大型生成程序会触发模块/文件大小限制。

### 2.2 工作项

- 统计所有失败中的 `TooManyFunctions`、`FrameOverflow`、`StackOverflow`、`OutOfMemory`、`ModuleTooLarge` 数量，建立真实需求分布。
- 在内存/包大小预算内提高 `MAX_FUNCS`、`MAX_FRAMES`、`MAX_STACK`；模块上限单独评估，不盲目放大。
- 错误信息包含当前值/需求值/函数名或调用链，例如 `FrameOverflow (limit=64)`。
- 添加边界单元测试和回归用例；记录上限提高对 runtime 体积、CIB 体积、执行时间的影响。
- 对生成式程序增加明确的“超出当前引擎限制”分类，而不是归到未知失败。

### 2.3 验收

- GCC `20010122-1` 不再 `TooManyFunctions`；`20000412-2` 不再 `FrameOverflow`（或确认是超出新上限的极端用例并记录）。
- YARPGen 100 seeds 中与资源上限相关的 skip 全部有明确原因；新增的 StackOverflow 必须能定位到具体调用链。
- `make size`、`make size-cross`、`make test` 无回归。

## 3. P0：标准 C 语义缺口

### 3.1 NaN/无序比较

- 当前约 75 个用例因 `unsupported fcmp predicate: une` 被 skip。
- 实现 LLVM `fcmp` 的 ordered/unordered 谓词（至少 `oeq/one/olt/ole/ogt/oge/ord/uno/ueq/une/ult/ule/ugt/uge`）在 SysV/Win64/Win32/AArch64 后端的一致语义。
- 添加 `NaN`、`+0/-0`、比较结果到整数分支的 ABI 测试；覆盖 C 的 `<`, `<=`, `>`, `>=`, `==`, `!=` 在 NaN 下的行为。
- 验收：相关 skip 条目被移除；TCC/libc/CompCert 中 NaN 相关 mismatch 重新分类。

### 3.2 浮点/整数转换

- 当前约 20+ 个 `fptoui`/`uitofp`（以及部分 `fptosi`）用例不具备 lowering。
- 实现 unsigned/signed float→int、int→float 的边界语义：截断方向、NaN/Inf、越界值、32/64 位差异。
- 在四种 ABI 上验证 `float`/`double`/`long double` 与整数互转。
- 验收：GCC/CompCert/LLVM 中对应 compile skip 消除；新增边界回归不依赖 UB。

### 3.3 零大小/空结构体

- `bad alloca size 0`、zero-size struct / empty struct 目前被跳过。
- 明确 C 扩展/ABI 语义（GCC/Clang 对空结构体大小和对齐的处理），为 `alloca`、GEP、byval、返回值补齐 1 字节/对齐规则。
- 验收：zero-size struct 相关用例不再因编译器内部错误跳过。

## 4. P0：GCC execute 226 个运行失败

### 4.1 先补诊断

- 当前 runner 对非零退出只记录 `exit N`，没有区分：
  - VM 资源限制（FrameOverflow/StackOverflow/TooManyFunctions）；
  - 原生符号缺失（SymbolNotFound）；
  - 测试主动 `abort`（真实语义错误）；
  - 超时或非法内存。
- 修改 runner：保存每个失败用例的完整 stderr、CIB、源文件、命令和首次错误行；报告中增加 `error_class`。
- 对 226 个失败按错误类聚合，选出 top 5 根因；不要逐个修 226 个用例。

### 4.2 修复与回归

- 优先修复能同时解锁多个用例的根因，例如 FrameOverflow 或某个标准库/ABI 行为。
- 用 creduce 或最小化脚本缩减失败源；将最小复现加入固定回归 manifest，而不是保留生成式大文件。
- 验收：226 个失败中至少 50% 转为通过或明确的范围外 skip；其余每条有 `error_class` 和 issue/原因。

## 5. P0：TCC/libc/CompCert mismatch

### 5.1 先分类

- 77 个 mismatch 至少分为：
  1. **cinterp 语义 bug**：结构体/浮点/varargs/生命周期/stdio 行为；
  2. **格式差异**：`printf`/`%Lf`/NaN/±0/整数宽度；
  3. **测试 harness 差异**：TCC 专有行为、libc `t_status` shim、CompCert 参考输出；
  4. **上游 expected 不适用当前 target**。
- 为每类建立最小样本；不要用“skip”掩盖真实 bug。

### 5.2 重点候选

- `libc-test` 的 `sem_init`/线程相关 segfault、`qsort`/`string`/`snprintf` mismatch；
- CompCert `aligned`/`bitfields`/`varargs` mismatch；
- TCC 的结构体、浮点格式、`stdout` 相关 mismatch；
- Csmith checksum mismatch 和 YARPGen StackOverflow 作为独立根因跟踪。

### 5.3 验收

- 先修复 1-2 个跨 suite 的共同根因，并移除对应 skip；
- 每个剩余 mismatch 有分类和最小复现；
- 不允许新增无原因 skip。

## 6. P1：external data 符号

- 当前约 100 个 `unknown global`，集中在 `stdout`、`errno`、`environ`、`t_status` 和测试全局。
- 设计并实现 `CIPI.kind=data`：
  - 编译器识别外部全局声明，生成 data import；
  - 运行时按 provider 解析数据符号地址；
  - VM `ADDR`/load/store 支持外部数据地址；
  - 明确只允许系统库/`--lib`，继续禁止 CIB 任意路径。
- 替代方案：给测试 harness 提供受控 shim，但应优先实现真实能力，避免 `libc-test` 的 `t_status` 重写长期存在。
- 验收：`stdout`/`errno` 等代表性用例通过；相关 skip 从约 100 降到可解释的少数。

## 7. P1：跨 ABI 与自动链接

- csuite 和 c-testsuite 上游 smoke 已在 Win64/Win32/ARM64 各 12/12；更大上游子集仍 native-only。
- 为 TCC/chibicc/GCC/CompCert 建立 per-target manifest 子集；
- 增加 target-specific expected 和 skip，不允许 compile 失败被 native 通过结果掩盖；
- 自动链接断言：
  - 每个目标检查 `--dump-imports` 的 provider/符号/arch/OS；
  - C 标准库覆盖 `printf/snprintf/malloc/free/qsort/sin`；
  - Windows 覆盖 UCRT/MSVCRT、kernel32/user32、A/W、cdecl/stdcall/varargs；
  - 验证 `--lib` 覆盖和 `TargetMismatch` 负路径。
- 验收：四目标各自有代表性上游套件通过；跨目标 skip 有 target 原因。

## 8. P1：生成式差分

- 当前 YARPGen 100 seeds 有 39 个 skip（27 个已知失败 + native/规模）；Csmith 3/3 已知失败。
- 失败样本自动保存到 `build/generate-failures/<generator>/<seed>/`，包含源文件、CIB、native/cinterp 输出、seed、命令和最小化结果。
- 引入 creduce 或内置简化器；修复后把最小样本加入固定回归 suite。
- 修复 StackOverflow、TooManyFunctions、checksum mismatch 的共性根因；不要持续扩大 known-failures 列表。
- 将 nightly 从 `make generate-diff`（20）改为 `make generate-diff-nightly`（100），CI artifact 保留报告和失败样本。
- 验收：100 seeds 无未分类 failure；已知失败数量下降且有 issue；新增固定回归不回归。

## 9. P2：覆盖广度

- CompCert：补齐 34 个缺少 expected 的 regression；接入 `test/c` 中可运行 benchmark；逐步减少 74 skip。
- libc-test：接入 `src/regression` 和更多 functional；去掉 `t_status` 文本重写，改用真实 external data 或正式 harness。
- LLVM SingleSource：从 79/93 扩到 `Regression/C` 的筛选子集；先 compile-only，再运行。
- TCC：在 77 个通过基础上继续处理 mismatch；优先标准 C、非 GNU cleanup/asm。
- c-testsuite：增加 `single-compile`/`multi-exec` 子集；保留现有 217/217 基线。
- 每个新 suite 都必须有 commit、license、expected、targets 和 skip 说明。

## 10. P2：CI、fuzz 与报告

- CI nightly 调用 `make test-suites-nightly`（含 100-seed diff），不再只跑 20-seed；
- 增加 Windows/ARM 上游子集 job；Windows runner 使用现有 SSH，ARM 使用 qemu；
- fuzz：
  - 扩到 1000+ 变异/多 seed；
  - 对 CIPM/CIPI section 做定向变异；
  - 在 ASan/UBSan 或 Zig safety 构建上跑原生执行 fuzz；
  - 生成式失败样本进入 corpus。
- 报告：
  - JSON 增加 `error_class`、`expected_source`、`skip_issue`、`first_error`；
  - 可选 JUnit XML；
  - 失败 artifact 保留一周；
  - 每个 skip 绑定 issue 或明确“范围外”标签。
- 验收：CI 可定位 suite/case/target/错误类；nightly 无未分类 failure。

## 11. 执行顺序与验收

### 阶段 A（P0）

1. 资源上限审计与诊断字段。
2. `fcmp` 无序谓词、float/int 转换。
3. GCC 226 运行失败分类和 top 根因修复。

验收：标准 C 相关 skip 明显下降；资源限制相关失败有明确结果；`make test-suites-full` 无回归。

### 阶段 B（P0/P1）

1. 77 个 mismatch 分类与共同根因修复。
2. external data 符号。
3. 四目标上游子集和自动链接断言。

验收：TCC/libc/CompCert 至少移除一批真实 skip；跨 ABI 有代表性套件；`make test-suites-cross` 通过。

### 阶段 C（P1/P2）

1. 生成式差分修复与最小化。
2. CompCert/libc/LLVM 覆盖扩展。
3. CI nightly、fuzz、报告完善。

验收：100-seed nightly 无未分类 failure；skip 有 issue/范围标签；报告可作为发布门禁。

## 12. 度量

| 指标 | 当前 | 目标 |
| --- | ---: | ---: |
| full 通过率 | 4110/4453 (92.3%) | ≥72% 已达到，下一步 ≥80% |
| skip 数 | 1426 | 先降到 <1200，再按范围外/缺陷拆分 |
| GCC execute 运行失败 | 226 | 至少减半，其余有 error_class/issue |
| `fcmp une` skip | ~75 | 0（标准 C） |
| `fptoui/uitofp` skip | ~20+ | 0（标准 C） |
| `unknown global` skip | ~100 | 代表性 external data 用例通过 |
| 跨 ABI 上游套件 | csuite + c-testsuite smoke 12/12 × 3 | 四目标各有 TCC/GCC/CompCert 子集 |
| YARPGen 100 未分类 failure | 0（已分类 39 skip） | 保持 0；known 失败有最小复现 |
| CI nightly 生成式 seeds | 20 | 100 |

目标是“真实通过率”提高，不是把 skip 换个名字。

## 13. 非目标与开放决策

**非目标（除非产品范围改变）**：

- GNU 扩展（nested functions、cleanup、asm goto、`__builtin_*`、`typeof` 等）；
- 向量类型/i128/atomics/indirectbr/callbr；
- Win64 vectorcall/COM、Win32 fastcall/thiscall；
- 完整 GCC/LLVM 测试集、SPEC 等商业 benchmark。

**开放决策**：

1. `MAX_FUNCS`/`MAX_FRAMES`/`MAX_STACK`/`MAX_MODULE` 的新值，以及 CIB 体积/内存预算。
2. external data 符号的 provider 解析、`--lib` 覆盖和安全边界。
3. fcmp 谓词覆盖范围是否包括全部 ordered/unordered 组合。
4. CompCert/libc 的 expected 是 native 生成还是上游文件优先。
5. 100-seed nightly 的超时/资源上限和失败最小化工具（creduce/内置）。

## 14. 命令

```bash
make test-suites-smoke
make test-suites
make test-suites-full
make test-suites-nightly
make test-suites-cross
make generate-diff
make generate-diff-nightly
make generate-diff-csmith
```

报告：`build/test-suites*.json`、`build/generate-diff*.json`、`build/generate-failures/`。
