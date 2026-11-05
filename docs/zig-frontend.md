# Zig 编译器前端

`cinterp-cc` 是唯一的构建期编译器。编译器位于 `compiler/`（不存在
`compiler-zig/` 目录树），它是一个单独的 Zig 程序：调用 `zig cc` C 前端，
用带类型的词法分析器/语法分析器/AST 外加一个子集校验器解析得到的 LLVM IR
文本，并输出 CIVM 字节码、CIPL 计划和 CIPKG v3 trusted 包。

IR 前端**只有一个** —— 即 `compiler/src/ir/` 下带类型的 AST：

```text
compiler/src/ir/lexer.zig    spans/tokens (no-copy)
compiler/src/ir/ast.zig      typed Module/Function/BasicBlock/Instruction AST
compiler/src/ir/parser.zig   IR text -> AST
compiler/src/ir/verify.zig   target/datalayout allowlist checks
compiler/src/lower_ast.zig   AST -> CIVM + CIPL + external symbols
compiler/src/abi.zig         CIPL call plans (SysV/Win64/Win32/AAPCS64)
compiler/src/ir/tests.zig    parser fixtures and malformed-input tests
compiler/src/ir/dump.zig     `zig build ir-dump -- file.ll` (debug aid, not installed)
```

原先的字符串/文本 lowering 实现（`compiler/src/` 内一个独立的 `lower.zig`
实现，现已删除）和最初的 Python 编译器都已被移除，`compiler/src/main.zig`
中也没有任何代码会在运行期选择解析器：既没有 `--ir-parser` 选项，也没有
`legacy` 解析器模式，也没有 `make parser-parity` 目标。
`compiler/src/lower_ast.zig` 是唯一的 lowering 实现。

## 依赖要求

- Zig 0.13（内置 clang/LLVM 18）。构建期和 `cinterp-cc compile` 时都需要
  Zig（它就是 C 前端），但*运行* `.cib` 不需要。
- 用 `cinterp-cc` 编译 C 不需要 libclang、libLLVM、外部 clang 或 Python
  依赖。

## 传给 `zig cc` 的编译选项

```text
-S -emit-llvm -O0 -g0 -fno-discard-value-names
-fno-sanitize=all -fno-stack-protector -ffine-grained-bitfield-accesses
```

Windows 目标会额外加上 `-fms-extensions -fdeclspec`；除原生 x86-64 Linux
宿主机之外，每个目标都会传入一个 `--target=`（`compiler/src/main.zig`、
`runZigCc`）。

之所以需要 `-fno-sanitize=all`，是因为 Zig 的 Debug `-O0` 否则会生成
`llvm.sadd.with.overflow` / `llvm.ubsantrap` intrinsic，而它们并不属于 CIVM
lowering 约定的一部分。`-fno-stack-protector` 去掉了编译器插入的、在运行时
中没有对应实现的栈检查。`-fno-discard-value-names` 让局部名称在 IR 和
`--dump-ast` 输出中都保持可读。

## 命令行

```text
cinterp-cc compile <source.c> [-o out.cib] [--target T] [--cc-path zig] [--keep-ir]
                    [--dump] [--dump-ast] [--dump-imports]
                    [--no-auto-link]
cinterp-cc --version
```

| 选项 | 行为 |
| --- | --- |
| `-o`, `--output PATH` | 输出包；默认取源文件路径，并把它的最后一个扩展名替换为 `.cib` |
| `--target T` | `x86_64-linux`（默认）、`x86_64-windows`、`i686-windows`、`aarch64-linux`；其他任何值都以退出码 2 结束 |
| `--cc-path PATH` | C 前端可执行文件（默认 `zig`） |
| `--cc NAME` | C 编译器选择项；只实现了 `zig`，任何其他值都以退出码 2 结束 |
| `--keep-ir` | 在输出文件旁保留临时的 `<out>.<random>.ll` |
| `--dump` | 向 stdout 打印每个函数的大小以及每一个计划（`args= ret= stack= conv=`） |
| `--dump-ast` | 向 stderr 打印解析出的模块摘要以及每个函数的块/指令数量 |
| `--dump-imports` | 打印 CIPI 表（计划索引、符号、提供者） |
| `--no-auto-link` | 跳过生成的 CIPI 提供者条目 |

`--dump-ast` 是编译器内部的结构化转储（`lower_ast.dumpModule`）：它会报告
类型定义/全局变量/declare/函数的数量，以及每个函数的 `blocks`/`instructions`。
`zig build ir-dump -- file.ll` 单独运行同一个解析阶段，并打印逐条指令的转储。

## IR 流水线

```text
LLVM IR text
  -> ir/lexer.zig        spans/tokens (no-copy)
  -> ir/parser.zig       typed Module/Function/BasicBlock/Instruction AST
  -> ir/verify.zig       subset allowlist + target/datalayout checks
  -> lower_ast.zig       CIVM functions
  -> abi.zig             CIPL call plans (SysV/Win64/Win32/AAPCS64)
```

解析器只接受 lowering 所消费的指令/类型/intrinsic 子集。它未实现的指令会
产生形如 `line:column` 的诊断信息，而不是 panic，也不会静默地给出零值；同时
lowering 会拒绝少数已被接受的形式（`frem`、`asm` 调用）。确切的白名单（包括
那些被接受但只做了部分建模的构造）见 [`ir-subset.md`](ir-subset.md)。
目标 triple/OS/指针宽度以及小端一致性会在 lowering 之前检查。

## 代码生成约定

- **调用约定。** `abi.convFromName` 把 `x86_stdcallcc` 映射为 `conv=1`、把
  `x86_fastcallcc` 映射为 `conv=2`，`x86_thiscallcc` 映射为 `conv=3`；其余所有
  LLVM 约定以及缺失关键字都映射为 `0`（即目标默认值：cdecl / SysV / AAPCS64）。
  调用点的关键字优先于声明处的关键字。间接调用采用 `call` 指令上的关键字（clang
  把约定打印在那里，而不是打印在函数指针类型里，因此没有其他地方可查）。回调计划
  使用定义函数的签名约定，所以 Win32 的 `__stdcall`/`__fastcall`/`__thiscall`
  回调分别得到 `conv=1`/`conv=2`/`conv=3`。i686 trampoline 会保存 ECX/EDX 以支持
  fastcall/thiscall callback；`win32CallbackSupported` 只拒绝未知约定
  （`runtime/src/ffi/platform.zig`）。最后，`main.zig` 会依据生成的 MinGW 导入表
  为已知的 WinAPI 导出覆盖 `conv`。
- **计划去重。** 计划按完整的序列化内容驻留（`lower_ast.plansEqual`：name、
  参数/返回位置、`stack_size`、`sret`、`sse_count`、`ret_size`、`conv`）。同一
  符号的相同签名共用一个计划；不同符号或不同 ABI 布局绝不合并。这减轻了大型
  模块对 `MAX_PLANS` 的压力。
- **各项限制在序列化之前强制执行。** `main.validateLimits` 在任何字节写出之前
  对完整的 `CompileResult` 和 CIPI 表运行，并以 `compiler limit: ...` 失败，
  而不是生成一个会被运行时加载器拒绝或截断的包：函数 ≤512 个、计划 ≤1024 个、
  每个计划的参数 ≤64 个且位置 ≤8 个、函数/计划名 ≤128 字节、导入 ≤512 个、
  每个导入的提供者 ≤8 个、导入/提供者/符号名 ≤64 字节、提供者版本 ≤32 字节、
  CIVM 模块 ≤2 MiB。

## 外部符号解析（构建期索引）

`cinterp-cc` 不附带任何签入仓库的链接数据库。`compiler/build.zig` 把
`compiler/tools/gen_link_index.zig` 构建为宿主机工具并运行两次；产物是一张
紧凑的二进制表，外加一个用 `@embedFile` 嵌入它的包装模块，二者以
`win_defs_generated` / `libc_defs_generated` 匿名导入的形式注入。

- Windows（`compiler/src/win_defs.zig`）：
  `<zig lib>/libc/mingw/{lib32,lib64,lib-common}/*.def`，外加用 `zig cc -E`
  预处理过的 `*.def.in` 模板，从中得到 DLL、导出符号、`arch_mask` 和调用
  约定。Windows API 名称（包括诸如 `\01_GetTickCount64@0` 这样的 Win32
  stdcall 修饰名）会解析到 `kernel32.dll`/`user32.dll`/`api-ms-win-*`，并优先
  选择具体 DLL 而不是 API set。`make test-winapi` 会为 Win64/Win32 编译
  `examples/windows/*.c` 并在 Wine 下运行它们；当没有任何目标能够实际执行时，它以
  非零码退出（本地只想空跑时可用 `python3 scripts/test_winapi.py --allow-skip`）。
- Linux（`compiler/src/libc_defs.zig`）：`<zig lib>/libc/glibc/abilists`，
  限定为 `x86_64-linux-gnu` 和 `aarch64-linux-gnu`，从中得到作为导出方的
  soname（`libc.so.6`、`libm.so.6`、`libpthread.so.0`、……）。
- 索引未描述的符号不进入 CIPI，而由运行时回退机制解析（进程符号、`--lib`、
  默认 CRT 库）。`compiler/src/data/link_wrappers.json` 是仅存的签入链接
  元数据，且只保存同签名别名（`snprintf -> _snprintf`）。

`zig build gen-link-index` 可以单独重新生成这两张表（它会打印条目/库/blob
大小），无需构建编译器的其余部分。

## 构建与使用

```bash
make compiler                                     # builds compiler/zig-out/bin/cinterp-cc
                                                  # and copies it to build/cinterp-cc
./build/cinterp-cc compile examples/basics/hello.c -o build/hello.cib
./runtime/zig-out/bin/cinterp-run build/hello.cib
```

交叉目标请使用 `--target`：

```bash
./build/cinterp-cc compile --target aarch64-linux examples/basics/hello.c -o build/hello-arm64.cib
./build/cinterp-cc compile --target x86_64-windows examples/basics/hello.c -o build/hello-win64.cib
./build/cinterp-cc compile --target i686-windows examples/basics/hello.c -o build/hello-win32.cib
```

## 测试

Python 只供测试、fuzz 和基准测试框架使用。编译器本身不依赖 Python，它的
外部符号表由 `zig build`（或 `zig build gen-link-index`）从 Zig 工具链生成。

- `make test` 构建编译器并运行 `scripts/test.sh`：运行时单元测试、
  `cd compiler && zig build test`，以及端到端集成用例。
- `make compiler-test` 只运行 `cd compiler && zig build test`（main、abi、
  ir、lower_ast、imports、link_index、link_wrappers、win_defs、libc_defs）。
- 已不再有 `make parser-parity` 目标：lowering 的回归由
  [`ir-parser-differences.md`](ir-parser-differences.md) 中描述的 golden
  CIVM/CIPL 比对来覆盖。

发布 tarball（`make release-artifacts`）：只有
`cinterp-<VERSION>-sysv-x86_64`（Linux x86-64）包含编译器 —— 即
`bin/cinterp-cc` 加上 exec 它的 `bin/cinterp` 包装脚本。`win64-x86_64`、
`win32-x86` 和 `arm64` 的 tarball 仅含运行时。参见
`packaging/README.release.md.in`。
