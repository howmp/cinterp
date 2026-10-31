---
name: c-interpreter-complete
overview: cinterp 计划内工作已全部完成，无未完成项。实现细节、ABI 边界、修复记录和验证矩阵见 dev.md 第 19 节。
---

# C 解释器计划状态

## 0. 状态

**无未完成计划项。**

多 ABI、精确 long double、跨 ABI callback、ABI 边界、上游 c-testsuite 支持集、fuzz/差分/CI、性能/体积/发布打包均已完成并通过对应验证。后续工作仅剩明确范围外的扩展，见下一节。

## 1. 明确范围外（非本轮计划项）

- 外部数据符号（`stdout`、`errno` 等）：c-testsuite 有 1 个 skip。
- 向量类型/复合复杂聚合全局初始化：c-testsuite 有 2 个 skip。
- Win64 `__vectorcall`/COM、Win32 `fastcall`/`thiscall`、SysV `i128`/向量参数。
- HFA callback >2 向量、long double callback。
- Windows CRT `%Lf`：与原生 MinGW 行为一致，不额外提供格式化 shim。
- 跨 ABI 的 safe bytecode fuzz 需要对应 Windows/ARM runner；当前为 native safe fuzz + 跨 ABI 集成测试。

## 2. 验证证据

| 项目 | 结果 |
| --- | --- |
| `make test` | runtime 3 单测、compiler 15 单测、20 个端到端用例、错误路径全部通过 |
| `make c-testsuite` | 本地 C 子集 10/10 |
| 上游 c-testsuite 支持集 | 217/217 通过，3 个明确 skip |
| `scripts/test_cross.sh` | 58/58（Win64 19、Win32 20、ARM64 19） |
| `make fuzz` | 200 变异，0 crash |
| `make fuzz-exec` | 500 变异，0 crash，0 timeout |
| `make differential` | 7/7 与 clang 原生返回值一致 |
| `make size-cross` | sysv 72,568B、win64 78,848B、win32 95,744B、arm64 84,520B，均 <128K |
| `make release-artifacts` | 四目标 `cinterp-0.1.0-*.tar.gz` |
| `make bench` | 每用例平均运行时间已记录 |

实现/决策/边界细节见 [dev.md](./dev.md) 第 19 节；命令入口见 README。
