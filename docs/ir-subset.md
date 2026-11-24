# LLVM IR 子集契约

`cinterp-cc` 默认接受由 `zig cc -S -emit-llvm -O2` 发出的 LLVM IR **文本**
（Zig 0.13 → clang 18.1.x）。`--cc-opt 0` 保留旧的 `-O0` 兼容模式。非 0 级别会关闭向量化
（`-fno-vectorize -fno-slp-vectorize`），并默认追加 `-fno-strict-aliasing -fwrapv
-fno-jump-tables -fno-builtin-printf`，以匹配 gcc-torture 依赖的别名/回绕语义并减少跳转表；仍出现的相对查找表初始化器会折叠为相对偏移。降低器实现
按边处理的 phi 并行拷贝、`llvm.smax/smin/umax/umin`、`llvm.abs`、整数位内建函数
（cttz/ctlz/ctpop/bswap/bitreverse/fshl/fshr/usub.sat）、`llvm.load.relative`、
`llvm.expect`、`llvm.assume` 等 lowering。类型化解析器/校验器只接受 CIVM 降低器已实现的子集：
解析器未实现的指令会变成 `line:column` 编译期诊断，而不是静默回退（少数部分建模的
例外列在下面）。类型化 AST（`compiler/src/ir/{lexer,ast,parser,verify}.zig`）是唯一
的 IR 前端；不存在 `--ir-parser` 选项，也没有第二套/旧式解析器。

## 模块

- `source_filename`、`target datalayout`、`target triple`
- 编号/具名类型定义，包括 `opaque` 主体
- 全局量：`global`、`constant`、`private`、`internal`、`external`、
  `thread_local`，以及作为不透明记录的 `alias`/`ifunc`
- 函数声明与定义、属性组、元数据记录（元数据仅为诊断/不透明记录保留）
- comdats、模块标志和 uselists 是不透明记录
- `@llvm.*` / `@.llvm.*` 全局量（`llvm.compiler.used`、`llvm.used` 等）不占用
  VM 存储

## 类型

`void`、`iN`、`half`、`bfloat`、`float`、`double`、`x86_fp80`、`fp128`、
`ppc_fp128`、`ptr`（不透明、addrspace）、数组、向量、字面量与具名结构体
（packed/unpacked）、函数类型。降低器会实体化 C 流水线所需的子集：标量、指针、
数组、结构体、f32/f64/f80/f128。`half`/`bfloat` 会被解析并且有布局，但 C 前端不会
对它们生成算术运算。

## 值与常量

局部量、全局量、整数/浮点字面量（十进制、十六进制、`0xK`/`0xL`）、`null`、`undef`、
`poison`、`zeroinitializer`、C 字符串、聚合常量，以及常量表达式：GEP、`ptrtoint`、
`inttoptr`、`bitcast`、`addrspacecast`、整数二元运算、trunc/zext/sext、icmp/fcmp。
多索引 GEP 常量表达式会保留每一个索引；f128 字面量会被规范化到规范字节序。

## 指令

`alloca`、`load`、`store`、`getelementptr`、`phi`、`br`、`switch`、`ret`、
`unreachable`、`select`、`extractvalue`、`insertvalue`、`extractelement`、`insertelement`、
直接/间接/尾调用 `call`（`call`、`tail`、`musttail`、`notail`）、`icmp`、`fcmp`、整数/浮点二元运算
（`add sub mul sdiv udiv srem urem and or xor shl lshr ashr fadd fsub fmul fdiv`）、
`fneg`、`freeze`、`trunc`、`zext`、`sext`、`fptosi`、`fptoui`、`sitofp`、`uitofp`、
`fpext`、`fptrunc`、`bitcast`、`inttoptr`、`ptrtoint`、`addrspacecast`。

生产编译会把可交换整数算子的常量左操作数重排到第二个发射位置，使运行时的
`LOAD_CONST_POOL;ALU` 融合生效；`icmp`/`switch` 的第二个操作数为常量时由
`LOAD_CONST_POOL;CMP` 融合吸收。`legacy_codegen`（仅 lowering golden 使用）不做重排。
8/16/32 位的 `shl/lshr/ashr/sdiv/udiv/srem/urem` 使用 `*_N` opcode（0xBA–0xC0），
结果归一化在同一个 dispatch 内完成；64 位仍使用基础 opcode 加 `NORMALIZE`。

`freeze` 按恒等操作降低（它把操作数存入结果槽）。`insertvalue` 在临时内存块中插入字段，
`extractelement`/`insertelement` 按内存元素读写；`extractvalue` 对标量字段加载，对聚合/
宽浮点字段返回地址。向量值在 CIVM 中以数据块地址表示。

受支持的 `llvm.*` 内建函数就是降低器已实现的那些：

| 内建函数 | 降低方式 |
| --- | --- |
| `llvm.memcpy.*`, `llvm.memset.*` | `OP_MEMCPY` / `OP_MEMSET` |
| `llvm.dbg.*`, `llvm.lifetime.*` | 丢弃（无调试信息） |
| `llvm.va_start.p0`, `llvm.va_copy.p0`, `llvm.va_end.p0` | `OP_VA_START` / `OP_VA_COPY` / 空操作 |
| `llvm.stacksave`, `llvm.stackrestore` | `OP_STACKSAVE` / `OP_STACKRESTORE` |
| `llvm.frameaddress` | 常量 `0` |
| `llvm.ptrmask` | `and` |
| `llvm.is.fpclass` | `OP_FPCLASS` |
| `llvm.fmuladd.{f32,f64,f80,f128}` | `OP_FMA` / `OP_FMA32`（f32/f64）或 libm `fmal`（宽浮点） |
| `llvm.smax/smin/umax/umin.{i8,i16,i32,i64}` | `OP_MAX_N` / `OP_MIN_N`，param 携带宽度与 signedness |
| `llvm.abs.{i8,i16,i32,i64}` | `OP_ABS_N`（忽略 is_int_min_poison） |
| `llvm.cttz/ctlz.{i8,i16,i32,i64}` | `OP_CTTZ_N` / `OP_CTLZ_N`，零输入返回位宽 |
| `llvm.ctpop.{i8,i16,i32,i64}` | `OP_CTPOP_N` |
| `llvm.bswap.{i16,i32,i64}` | `OP_BSWAP_N` |
| `llvm.bitreverse.{i8,i16,i32,i64}` | `OP_BITREV_N`；i1 为恒等 |
| `llvm.fshl/fshr.{i8,i16,i32,i64}` | `OP_FSHL_N` / `OP_FSHR_N` |
| `llvm.usub.sat.{i8,i16,i32,i64}` | `OP_USUB_SAT_N` |
| `llvm.load.relative.{i32,i64}` | 读 i32 相对偏移并加基址 |
| `llvm.eh.sjlj.setjmp` / `llvm.eh.sjlj.longjmp` | `OP_SETJMP` / `OP_LONGJMP` |
| `llvm.experimental.noalias.scope.decl`, `llvm.sideeffect` | 无操作 |
| `llvm.expect.*` | 恒等（取值参数） |
| `llvm.assume`, `llvm.donothing` | 无操作 |
| `llvm.fabs`, `llvm.sqrt`, `round`, `ceil`, `floor`, `trunc`, `nearbyint`, `rint` | 对应的 libm 条目（`fabsf`/`fabs`/`fabsl` 等） |
| `llvm.sin`, `llvm.cos`, `llvm.exp2`, `llvm.log2`, `llvm.pow`, `llvm.fmin`, `llvm.fmax` | 对应的 libm 条目 |
| `llvm.copysign` | `copysignf` / `copysign` / `copysignl` |

只有 FMA 类内建函数中 `llvm.fmuladd` 被映射（映射到 `fmaf`/`fma`/`fmal`）。没有
`llvm.fma.*` 条目，因此它会走下面描述的未知内建函数路径。

在解析期被拒绝（编译期错误，`line:column` 诊断）：`shufflevector`、作为指令的
`va_arg`、`atomicrmw`、`cmpxchg`、`fence`、`invoke`、`resume`、`landingpad`、
`indirectbr`，以及任何未在上文列出的助记符（`compiler/src/ir/parser.zig`，
`parseInstruction`）。

稍后由降低器拒绝：`frem`（可以解析，但没有 CIVM opcode），非空模板的内联汇编调用
（`error.UnsupportedInstruction`）。空模板 `asm` 视为恒等/编译器屏障。

已接受但只是部分建模，因此值得了解：

- `callbr` 可以解析，并按普通 `call` 降低；它的标签列表会被解析进
  `Call.callbr_targets`，随后被忽略，因为运行时没有间接分支。clang 不会为 C 生成
  `callbr`。
- 未知的 `llvm.*` 内建函数不做特殊处理：它们保留自己的名字，成为普通的外部调用
  计划，并在运行期（未解析符号）而不是编译期失败。
- GNU 向量扩展不在该子集内。向量值在 CIVM 中以数据块地址表示；`extractelement`/
  `insertelement` 按元素大小读写，向量常量和 `zeroinitializer` 会实体化到临时内存。
  向量算术、`shufflevector`、`getelementptr` 进入向量的非零字面索引仍未实现。
- 全局 `fp128` 初始化器会写入 16 字节真实数据。`ppc_fp128`、`half`、`bfloat` 和
  全局向量初始化器没有 runtime 值路径，会返回 `UnsupportedGlobalInitializer`，
  不再静默保持为零。相对查找表的 `trunc(sub(ptrtoint, ptrtoint))` 初始化器会在
  布局完成后折叠为相对偏移；普通的外部/内部地址仍走 relocation。

## 校验

`compiler/src/ir/verify.zig` 校验模块 triple 的架构/OS 以及由此推导出的指针宽度与
`--target` 匹配，并且 datalayout 为小端（`e-...`）。解析器对不受支持或格式错误的
IR 报告 `line:column`（`compiler/src/main.zig`，`lowerModule`）。

运行时/CI 门禁：

```bash
cd compiler && zig build test   # parser fixtures, verifier tests, lowering goldens
make test-suites-full           # full local suite (4331 passed / 191 skipped;
                                # 2451 compile-mode passes, 1880 executable)
make test-suites-cross          # csuite + upstream smoke on Win64/Win32/ARM64
```

关于 golden 文件的回归方案以及历史解析器缺陷记录，见
[`ir-parser-differences.md`](ir-parser-differences.md)。
