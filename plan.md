---
name: remaining-excluded-audit
overview: 仅保留尚未完成的 excluded/skip 分类审计；当前基线 4286/4519 和已完成结论见 dev.md §20.17。
---

# 剩余 excluded 审计

## 1. GCC compile excluded 分类

- 逐类审计剩余 605 行：gnu89/implicit-int/K&R（non-goal）、warning-first（重新观察真实原因）、resource、asm、vector、builtin。
- 不新增 gnu89/vector/builtin lowering；仍可回收因已实现能力而实际通过的用例。
- 禁止用 clang warning 或 traceback 作为原因，禁止自动更新 expected。

## 2. CompCert/TCC 候选

- 只回收与已实现能力直接相关且 native/cross 实测通过的 skip；诊断文本一致性继续保持 non-goal。
- 每个回收/保留项保留分类 token 和观察记录。

## 3. 验收

- 所有剩余 excluded/skip 行有可审计类别和原因。
- full 相对 **4286/4519（233 skip）** 无回归；新回收项必须实测通过并记录 ID。
- 不新增 expected 弱通过，不扩大 gnu89/vector/builtin 范围。
