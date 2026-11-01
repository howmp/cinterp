---
name: remaining-excluded-audit
overview: 仅保留尚未完成的 excluded/skip 分类审计；varargs、FP/NaN、traceback、跨 ABI 扩展和生成式最小化已完成，详见 dev.md §20。
---

# 剩余 excluded 审计

## 1. 当前规模

| 文件 | 数量 | 主要类别 |
| --- | ---: | --- |
| `gcc-torture.excluded` | 396 | dialect、asm、vector/_Complex、builtin、resource |
| `gcc-torture-compile.excluded` | 609 | dialect、诊断、asm、vector、resource |
| `compcert.excluded` | 34 | 缺参考输出 / 非目标 |
| `tcc-tests2.excluded` | 1 | inline asm |

## 2. 仍需做的分类

- **HFA coerce 残留**：`20071102-1`、`981223-1`、`pr55921`；先确认是否 HFA struct，而不是 `_Complex`；通过则回收。
- **GCC compile excluded**：逐类审计 dialect（non-goal）、warning-first（需要重新观察真实原因）、resource、vector/asm/builtin（non-goal）；不为 gnu89/vector/builtin 增加实现。
- **CompCert/TCC skip**：只回收与已实现能力直接相关且实测通过的项；诊断文本一致性保持 non-goal。
- **证据清理**：剩余行应有分类 token 和观察记录；禁止用 clang warning 或 traceback 当原因，禁止自动更新 expected。
- **跨 ABI**：已完成每目标约 145 个，见 `dev.md` §20.16；后续只按新失败补充 per-target skip。

## 3. 验收

- 所有剩余 excluded/skip 行有可审计类别和原因。
- 不新增 expected 弱通过，不扩大 gnu89/vector/builtin 范围。
- full 相对 **4282/4515（233 skip）** 无回归；新回收项必须实测通过并记录 ID。

## 4. 已确认决策

- 保持 C17，不启用 `-std=gnu89`。
- `_Complex`、GCC builtins、外部 inline/weak 地址、CIB-to-CIB、多线程/原子/汇编/vector、可增长内存均为 non-goal。
- 编译器错误文本一致性 non-goal。
- 跨 ABI 扩展 nightly 运行，PR 保持小 smoke。
- runner 的 `--include-excluded`、`--only`、`--emit-reasons` 已实现。
