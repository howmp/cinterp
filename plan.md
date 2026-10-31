---
name: c-interpreter-remaining
overview: cinterp 剩余工作：跨 ABI callback、long double 完整 ABI、ABI 边界、完整 c-testsuite/chibicc、bytecode fuzz 与性能/发布。当前实现状态、架构和测试矩阵见 dev.md。
---

# C 解释器剩余工作

> 当前实现、架构、ABI 细节、已知边界和测试矩阵见 [dev.md](./dev.md)，最新实现状态见 dev.md 第 19 节。本文件只保留未完成工作。

## 0. 使用说明

当前实现基线、测试矩阵和已知边界见 [dev.md](./dev.md) 第 19 节。本文件只列未完成工作；完成一项后从本文件删除，并把实现细节补进 dev.md。

## 1. P0：跨 ABI callback

当前 callback 静态 trampoline、dispatcher 和 `CREATE_CALLBACK` 只在 SysV x86-64 上可用；Win64/Win32/AAPCS64 会返回 `UnsupportedCallback`。

- [ ] 每个 ABI 的 callback frame + dispatcher：
  - Win64：RCX/RDX/R8/R9、XMM0–3、32B shadow、栈参数、sret；浮点参数按计划双写。
  - Win32：栈参数、cdecl/stdcall 清理、EAX:EDX/ST0 返回、sret。
  - AAPCS64：x0–x7、v0–v7、HFA、x8 sret、16B 栈。
- [ ] 每个 ABI 的 256 槽静态 trampoline 池（无动态可执行内存），构建时只链接目标 ABI 的池。
- [ ] 编译器为 callback 生成目标 ABI 的 `CallbackPlan`（参数/返回分类、HFA、byval/sret、varargs 拒绝或支持明确）。
- [ ] 验证：qsort、结构体参数/返回、栈参数、嵌套 callback/重入；跨 ABI 套件加入 callback 用例。
- 退出：Win64/Win32/AAPCS64 qsort callback 全通过；无 `UnsupportedCallback` 路径。

## 2. P0：long double 完整语义与 ABI

当前 `x86_fp80` 是 16B 存储 + 64-bit 精度；只支持内部算术/比较/转换，FFI、varargs `printf("%Lf")` 未覆盖。

- [ ] 精确 80-bit 值表示与 x87 语义：常量（`0xK...`）、加减乘除、比较、转换、NaN/Inf。
- [ ] FFI 分类与引擎：
  - SysV：参数走栈（16B/对齐）、返回 x87 ST0；`%al`/varargs 规则。
  - Win64：16B 对象/按引用/sret 规则，确认 clang lowered IR。
  - Win32：x87 ST0 返回、栈参数、对齐。
  - AAPCS64：`long double` 的 AAPCS64 分类（通常 16B 聚合）。
- [ ] `printf`/`snprintf` 的 `%Lf` varargs 路径。
- [ ] 测试：`1.0L/3.0L` 精度、极大/极小值、C helper 对照、FFI 返回/参数、printf 输出。
- 退出：不再以 64-bit 精度截断；ABI helper 结果与 clang 编译的 C 一致。

## 3. P1：ABI 边界矩阵

当前计划/引擎以代表性用例为主，以下边界未系统覆盖。

### Win64

- [ ] 超过 4 个混合 GPR/XMM 参数、寄存器耗尽后的栈参数、shadow space 边界。
- [ ] varargs：home space、栈上 varargs、浮点 GPR+XMM 双写、超过 4 个参数、AL 语义。
- [ ] 大结构体按值/按引用的拷贝语义、packed/未对齐结构体。
- [ ] 浮点/整数混合、`__vectorcall`/COM/异常/unwind 明确排除或后续。

### Win32

- [ ] 编译器计划携带 calling convention（cdecl/stdcall），支持 clang 的 `stdcall` 函数；符号修饰/解析。
- [ ] varargs/callback（callback 见第 1 节）、超过 4 参数、浮点/整数混合。
- [ ] 大结构体、8 字节返回、packed/未对齐结构体、sret 栈布局。
- [ ] 明确不支持 `fastcall`/`thiscall`。

### AAPCS64

- [ ] HFA 3/4 个成员（v0–v3 返回/参数）；当前计划只处理 ≤2 个返回向量。
- [ ] HFA 栈参数、HFA 寄存器/栈混合、非 HFA 聚合的 x0/x1 与栈规则。
- [ ] 大结构体按值、>16B 聚合、packed/未对齐、varargs 边界。

### SysV x86-64

- [ ] 超过 2 个 eightbyte 的聚合（非 MEMORY/sret 路径）、mixed-class、packed/未对齐。
- [ ] `i128`/向量类型（若纳入 C 子集）。
- [ ] varargs 边界、寄存器耗尽、栈对齐。

### 通用验证

- [ ] 每个 ABI 用 clang 编译的 C helper 做差分测试，覆盖寄存器/栈/返回。
- [ ] 把边界用例加入 `scripts/test_cross.sh` 或独立矩阵脚本。

## 4. P1：C 覆盖与完整 c-testsuite/chibicc

当前 `make c-testsuite` 是本地 9 用例子集；外部目录只识别 `// expect:` 标记。完整上游 c-testsuite/chibicc 未跑通/未分级。

- [ ] 上游 c-testsuite single-exec harness：编译、运行、期望退出码/输出；记录 pass/fail/skip。
- [ ] 按失败项补 C 子集：间接调用/内部函数指针、变长参数定义（`va_start`/`va_arg`）、VLA、复合字面量、`goto`/switch 边界等。
- [ ] 明确排除并文档化：`_Atomic`、`_Thread_local`、`_Complex`、`setjmp`/`longjmp`、内联汇编、向量类型、`indirectbr`。
- [ ] chibicc 子集/回归用例；形成稳定的“支持/跳过”清单。
- 退出：上游可运行子集达到约定通过率；所有失败/跳过有分类和原因。

## 5. P1：fuzz、sanitizer 与持续集成

当前 fuzz 只做 `--load-only` 的 package/plan 变异；没有 bytecode 执行 fuzz、差分测试或 Windows/ARM64 CI。

- [ ] bytecode/VM fuzz：隔离进程、超时、崩溃检测；覆盖 opcode、跳转、内存边界、FFI 计划。
- [ ] plan/package fuzz 扩展到所有 ABI ID、所有 loc kind、stack/sret/varargs。
- [ ] 差分测试：同一 C 用例分别用 clang 原生和 cinterp 运行，比较返回值/输出。
- [ ] ASan/UBSan/Zig ReleaseSafe CI 路径；记录已知不可恢复错误。
- [ ] CI：Linux 全量 + Windows runner（或 SSH 测试机）+ qemu-aarch64；跨 ABI 用例自动化。
- 退出：固定 fuzz 预算无崩溃；sanitizer/差分测试纳入 PR 检查。

## 6. P2：性能、体积与发布

- [ ] 基准：VM 循环、内存访问、FFI 调用开销、callback 开销（各 ABI）。
- [ ] 每个目标 ABI 的 ReleaseSmall 体积预算与检查（当前 runtime 40K；跨平台目标待测）。
- [ ] 发布物/版本策略、安装说明、许可证、CI 产物。
- [ ] 文档：支持矩阵、已知限制、沙箱/信任模型。

## 7. 完成定义与验证入口

剩余项完成需同时满足：

- 功能实现 + 目标 ABI 的真实环境验证（Windows SSH / qemu / native）。
- 对应单测/集成用例加入 `make test`、`make c-testsuite` 或 `scripts/test_cross.sh`。
- 不在 `plan.md` 保留已完成条目；实现细节、决策和边界更新到 `dev.md`。

现有验证入口：

```bash
make test            # 运行时/编译器单测 + 端到端 + 错误路径
make c-testsuite     # 本地 C 子集
make fuzz            # package/plan load-only 变异
make size            # ReleaseSmall 体积
make release-check   # test + size
HOST=user@windows ./scripts/test_cross.sh   # Win64/Win32/ARM64 真实环境
```

## 8. 开放决策

- **callback 跨 ABI**：每 ABI 独立 256 槽静态池，还是每程序生成 dispatcher（仍无动态可执行内存）？
- **long double**：实现精确 x87 80-bit，还是保留 64-bit 精度并明确不支持 FFI/printf？进入第 2 节前先确认。
- **Win32 stdcall**：在 CallPlan 增加 `conv` 字段，还是用 ABI 子类型/名称修饰约定？
- **c-testsuite 通过率**：全上游 vs 约定子集；失败分类的接受标准。
- **fuzz 信任边界**：VM 执行变异字节码是否允许调用任意原生符号；需要沙箱/白名单策略。
