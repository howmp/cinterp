# 文档索引

`cinterp` 编译器（`compiler/`）和运行时（`runtime/`）的参考资料。代码是事实的来源；
这些页面描述代码所实现的契约以及用于验证它们的命令。

| 文档 | 内容 |
| --- | --- |
| [`cib.md`](cib.md) | `.cib` 包格式：`CIPKG` v4 trusted 容器、`CIVM` v2 字节码、`CIPL` 调用计划、`CIPI` 链接元数据、`CIPC` 常量/名称池，以及运行时状态码 |
| [`embedding.md`](embedding.md) | 在 C 宿主中嵌入 `libcinterp`：构建/安装、`ci_vm_*` C ABI、错误生命周期、回调与内存限制注意事项 |
| [`multi-cib.md`](multi-cib.md) | 单进程多 CIB：`ci_process_*` 注册表、重复运行的全新镜像、每 VM 线程/执行权，以及 CIB 内显式 callback acquire/release |
| [`compatibility.md`](compatibility.md) | 版本与兼容性契约：单一 `VERSION` 来源、各组件版本、当前格式版本、C ABI 版本和编译器/运行时配对；0.1.4 已发布，但仍不保证格式兼容或旧格式迁移 |
| [`ir-subset.md`](ir-subset.md) | `cinterp-cc` 接受的 LLVM IR 子集：模块形式、类型、常量、指令、支持的 `llvm.*` intrinsic，以及会被拒绝并给出诊断的内容 |
| [`zig-frontend.md`](zig-frontend.md) | Zig 前端：`cinterp-cc` 如何驱动 `zig cc`、`compiler/src/ir` → `lower_ast.zig` 流水线、CLI 标志、调用约定/计划去重/限制的契约、外部符号表、发布压缩包内容 |
| [`ir-parser-differences.md`](ir-parser-differences.md) | IR 前端回归覆盖（解析器测试、降低 golden 用例），以及对已退役字符串解析器缺陷的明确标注为历史记录的说明 |
| [`unsupported-cases.md`](unsupported-cases.md) | 当前 full-tier 的 191 个 `unsupported` skip 用例及原因，按 suite 分组 |

`docs/` 下的参考文档以中文撰写；`examples/README.md`、`scripts/README.md`
等其他目录说明可能使用英文。代码块、命令、路径、标识符和 ABI/工具名称保持原样。

另见仓库的 [`README.md`](../README.md)（简介、原理、现状、用法）和 [`dev.md`](../dev.md)
（架构、实现决策与开发指南）。
