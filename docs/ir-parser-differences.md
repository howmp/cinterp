# IR 前端回归笔记

**当前状态。** 恰好只有一个 IR 前端：`compiler/src/ir/` 下带类型的 AST
（`lexer.zig` → `parser.zig` → `ast.zig`，由 `verify.zig` 检查）供给
`compiler/src/lower_ast.zig`，其中的 CIPL 调用计划来自
`compiler/src/abi.zig`。`compiler/src/main.zig` 始终通过它进行解析。已不再
存在 `--ir-parser` 选项、`legacy` 解析器、`scripts/ir_parser_parity.py`，也没有
`make parser-parity` 目标。

因此本文*不是*对两个前端的比较。它记录：(a) 如今如何捕获 IR 解析/lowering 的
回归；(b) 已退役的字符串解析器曾经存在、而 AST 路径正是为避免它们才编写出来的
那些解析缺陷 —— 这部分在
[§历史记录](#historical-string-parser-bugs-kept-as-regression-notes) 中明确标注为
历史内容。

## 如今如何捕获回归

以下所有内容都在 `cd compiler && zig build test` 下运行（即
`make compiler-test`，它也是 `make test` 的一部分）：

| 套件 | 位置 | 锁定的内容 |
| --- | --- | --- |
| IR 解析器测试 | `compiler/src/ir/tests.zig`（22 个测试） | 模块/类型/全局变量的解析，指令与常量表达式形式，调用/intrinsic/属性；畸形与变异输入返回带位置的错误，而不是 panic |
| 解析器 fixture | `compiler/src/ir/testdata/` | `clang18_x86_64.ll` 的端到端解析 |
| 校验器测试 | `compiler/src/ir/verify.zig` | triple/架构/OS/指针宽度不匹配以及非小端的 datalayout 都会被拒绝 |
| lowering golden | `compiler/src/lower_ast.zig`（`golden_cases`） | 每种 ABI 的完整 `CompileResult` 文本映像（CIVM 字节码 + CIPL 计划 + 外部符号） |
| ABI 计划测试 | `compiler/src/abi.zig` | SysV/Win64/Win32/AAPCS64 的计划形态、varargs、`conv` 映射 |
| 限制测试 | `compiler/src/main.zig` | `validateLimits` 拒绝那些会被运行时截断的记录尺寸 |

golden 文件位于 `compiler/src/testdata/lower_ast/golden/*.golden`（18 个
文件），是所有到达 CIVM/CIPL/CIPI 的 `CompileResult` 字段的规范文本映像：
`clang18`、`control_flow`、`external_constant`、`f32_literals`、
`ffi_callback`、`ffi_callback_scope`、`ffi_qsort`、`global_name_in_initializer`、`globals`、
`hello`、`intrinsics`、`inttoptr_global`、`metadata_global`、`misc`、
`null_callee`、`null_callee_args`、`null_suffix_callee`、`structs`。

回归会表现为失败的单元测试、失败的 golden 差异，或属性断言 —— 这里不存在可
供比对的第二份实现，因此 golden 的变动必须当作代码生成变更来审查：

```bash
cd compiler && zig build test                       # all parser + lowering checks
cd compiler && CINTERP_WRITE_GOLDEN=1 \
  zig test src/lower_ast.zig --test-filter "write golden files"
```

只有在有意变更代码生成时才重新生成 golden。不要通过重新引入下面某个历史解析器
缺陷来“修复”失败的 golden；请改为添加一个正确性测试，并更新本文档。

<a id="historical-string-parser-bugs-kept-as-regression-notes"></a>

## 历史记录：字符串解析器的缺陷（作为回归笔记保留）

下面的笔记描述的是已退役的文本 lowering 实现，它已被带类型的 AST 取代，并在此
之后被删除。其中的计数是历史上 parity 对比工具（`scripts/ir_parser_parity.py`，
随字符串解析器一并移除）在 `examples/`、`tests/csuite/` 以及抓取到的
gcc-torture / llvm-regression 语料上的测量结果：62 个源文件逐字节一致，10 个
存在差异。在这 10 个当中，每一个都是 AST 正确而字符串解析器存在解析缺陷，因此
字符串解析器被移除，且没有照搬这些行为。现在每个缺陷在
`compiler/src/lower_ast.zig` 中都有一个正向的 AST 回归测试，并配有一个 golden。

### 1. 全局 `inttoptr` 常量映像（2 个用例）

- `gcc-torture/execute/20021010-2` (`@global_vramPtr = global ptr inttoptr (i64 40960 to ptr)`)
- `llvm-regression-c/2003-06-16-InvalidInitializer` (`@Ptr = global ptr inttoptr (i64 8 to ptr)`)

原因（历史）：字符串解析器的 `parseConstant` 指针分支在
`inttoptr (i64 N to ptr)` 中定位到 `i64`，然后从一个前导空格开始切分剩余部分，
于是解析出一个空整数，并让数据映像保持为零。

当前行为：数据映像中包含来自 `inttoptr` 常量的小端、指针宽度的值（`40960` /
`8`）。

测试：`global inttoptr initializer is materialized`（数据映像字节外加 golden
`inttoptr_global.golden`）。

### 2. `external constant` 声明（6 个用例）

- `gcc-torture/compile/20030708-1` (`@a = external constant [0 x i8]`)
- `gcc-torture/compile/20031124-1` (`@stop = external constant [0 x i8]`)
- `gcc-torture/compile/20040708-1`（三个外部互斥方法表）
- `gcc-torture/compile/20110913-1` (`@__exp_deltatable`)
- `gcc-torture/compile/980816-1` (`@XtStrings`)
- `gcc-torture/compile/pr39983` (`@a = external constant [1 x i32]`)

原因（历史）：字符串解析器只把 `external global` 和 `external thread_local`
声明记录到外部符号表中。`external constant` 被丢弃，于是取它地址的代码
lowering 成了常量 `0`，该符号也从未进入 CIPI。

当前行为：外部常量声明会被加入 `external_data`，引用会 lowering 为
`OP_ADDR_EXTERN`，也就是说该符号是一个数据导入（`CIPI` kind 1），引用使用导入
的地址。这些输入仅用于编译，因此可执行行为不变；生成的代码是正确的表示。

测试：`external constant declarations are imported and addressed`（外部符号
列表、`OP_ADDR_EXTERN`、golden `external_constant.golden`）。

### 3. 提及另一个全局变量的全局初始化器（1 个用例）

- `gcc-torture/compile/pr19853`:
  `@test.const_test = internal constant %struct.test { ptr @global_int }`.

原因（历史）：字符串解析器在 `=` 之后的文本中、`constant` 之前查找单词
`global`。它匹配到了初始化器中 `@global_int` 里的 `global`，误解析了类型，
并丢弃了整个 `@test.const_test` 对象。

当前布局：`@test.const_test` 位于 0，`@global_int` 位于 8，`@flag` 位于 12，
`@global_test` 位于 16（24 字节映像），并在偏移 0 处有一个指向
`@global_int` 的重定位。

测试：`initializer mentioning a global name keeps the global allocated`（布局、
重定位、`OP_ADDR_CONST 12`、golden `global_name_in_initializer.golden`）。

### 4. 被调方名称以 `null` 结尾（1 个用例）

- `gcc-torture/execute/pr49886`:
  `%call = call ptr @getnull()`，随后是
  `call void @foo(ptr @gi, ptr %call)`。

原因（历史）：当指令文本以 `null()` 结尾时，字符串解析器的 `lowerCall` 会提前
返回。那本来是为裸 `call void null()` 准备的，却也匹配上了 `@getnull()`，于是
该调用及其存储的结果消失了；随后的调用便读取了一个未初始化的栈槽。

当前行为：会比较解析出的被调方（callee）记号，因此 `@getnull` 是普通调用，只有
裸 `null` 被调方才会被丢弃。`CALL @getnull`、结果存储以及带该结果的
`CALL @foo` 都会被生成。

测试：`call result is kept when the callee name ends in null` 和
`null callee calls lower to no instructions`（golden
`null_suffix_callee.golden`、`null_callee.golden`、`null_callee_args.golden`）。

### 5. LLVM 链接器元数据全局变量（过去表现不同，从未进入白名单）

`gcc-torture/execute/pr78791` 和
`llvm-regression-c/.../execute/20101011-1` 过去表现不同，因为 AST 跳过了
`@llvm.compiler.used`，而字符串解析器分配了 8 字节的零数据（以及一个更大的
`SET_MEM_TOP`）。LLVM 链接器元数据全局变量不是程序对象，绝不能预留 VM 存储，
因此在被移除之前，字符串解析器也被修复为跳过 `@llvm.*`/`@.llvm.*` 全局变量。

当前行为：元数据全局变量不预留 VM 存储；这是受支持的不变量，而不是分歧。

测试：`llvm metadata globals do not reserve VM storage`（数据映像长度外加
golden `metadata_global.golden`）。

## 上文引用的命令

```bash
cd compiler && zig build test   # parser, verifier, ABI and lowering tests
make test                       # runtime + compiler unit tests + integration
make test-suites-full           # full C suite through the AST frontend
make test-suites-cross          # csuite + upstream smoke on Win64/Win32/ARM64
make c-testsuite                # 18 local cases in tests/csuite (scripts/test/c_testsuite.sh), host target only
make test-winapi                # Windows API imports under Wine (fails when nothing can run)
```
