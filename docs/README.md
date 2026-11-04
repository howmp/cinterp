# 文档索引

`cinterp` 编译器（`compiler/`）和运行时（`runtime/`）的参考资料。代码是事实的来源；
这些页面描述代码所实现的契约以及用于验证它们的命令。

| 文档 | 内容 |
| --- | --- |
| [`cib.md`](cib.md) | `.cib` 包格式：`CIPKG` v2/v1 容器、`CIVM` 字节码、`CIPL` 调用计划、`CIPM` 目标头、`CIPI` 链接元数据，以及运行时状态码 |
| [`embedding.md`](embedding.md) | 在 C 宿主中嵌入 `libcinterp`：构建/安装、`ci_vm_*` C ABI、错误生命周期、回调与内存限制注意事项 |
| [`compatibility.md`](compatibility.md) | 版本与兼容性契约：单一 `VERSION` 来源、各组件版本、N−1 读取保证、C ABI 版本、编译器/运行时配对、弃用策略 |
| [`ir-subset.md`](ir-subset.md) | `cinterp-cc` 接受的 LLVM IR 子集：模块形式、类型、常量、指令、支持的 `llvm.*` intrinsic，以及会被拒绝并给出诊断的内容 |
| [`zig-frontend.md`](zig-frontend.md) | Zig 前端：`cinterp-cc` 如何驱动 `zig cc`、`compiler/src/ir` → `lower_ast.zig` 流水线、CLI 标志、调用约定/计划去重/限制的契约、外部符号表、发布压缩包内容 |
| [`ir-parser-differences.md`](ir-parser-differences.md) | IR 前端回归覆盖（解析器测试、降低 golden 用例），以及对已退役字符串解析器缺陷的明确标注为历史记录的说明 |

所有文档均用中文撰写；代码块、命令、路径、标识符和 ABI/工具名称保持原样。

另见仓库的 [`README.md`](../README.md)（构建、用法、支持矩阵）和 [`dev.md`](../dev.md)
（开发者指南）。
