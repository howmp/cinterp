---
name: cib-target-and-auto-link
overview: 扩展 CIB：声明目标架构/平台，内嵌外部符号链接元数据；第一阶段用 cstdapi 自动链接 C 标准库，第二阶段用 winmd 自动链接 Windows API。
---

# CIB 架构声明与外部符号自动链接

## 0. 目标

在 `.cib` 中加入两类新数据：

1. **目标声明**：架构、平台/OS、ABI、指针宽度、端序、目标 triple、最低运行时版本和特性位。运行时在加载模块/计划前先校验目标，错误直接报 `TargetMismatch`，不再只依赖 CIPL 的 ABI id。
2. **外部符号链接信息**：每个外部调用不仅包含 ABI plan，还包含“从哪个库、用什么符号/别名、什么调用约定、最低 OS/架构”解析。运行时按 CIB 内的信息自动加载 provider 库并解析符号，不再把所有符号都丢进全局搜索。

分阶段：

- **Phase 1**：C 标准库自动链接。参考 [cstdapi](https://github.com/howmp/cstdapi) 的 `cstdapi.txt`、`linuxgood.txt`、`wingood.txt`、`linuxbad.txt`、`winbad.txt`、`glibcabi.txt` 和 msvcrt/ucrtbase/ntdll spec，生成 C 标准库符号→provider/别名/可用性表。
- **Phase 2**：Windows 全 API 自动链接。参考 [winmd](https://github.com/howmp/winmd) 的 `apis.json`（18k+ API；含 name/args/ret/callconv/dll/os/arch/ref），生成紧凑的 Windows API 链接索引，按 DLL 自动加载并解析。

“自动链接”指编译器自动把被使用的外部符号及其 provider 写入 CIB，运行时按 CIB 元数据动态加载；**不是**把库静态链进字节码，也不是运行期把库路径写死。

## 1. 现状

- `CIPKG` v1：`CIPKG` 头 + module + plans；无目标元数据、无 import 表。
- `CIVM` v1：字节码模块；`arch` 字节是 VM 字节码架构，不是宿主目标。
- `CIPL` v3：`CallPlan` 只含 name/ABI locs/stack/sret/sse/conv/ret_size；不含 provider、别名、最低 OS。
- 运行时 `resolveNative` 每次调用按“进程默认 → `--lib` 句柄逆序 → CRT fallback → Windows 别名/修饰名回退”动态搜索；符号来源和版本不受 CIB 控制。
- `--lib` 可加载用户库；没有自动 provider 元数据。

## 2. 总体设计

### 2.1 CIB v2 外层

新增可选 section，同时保持 v1 兼容。建议：

```
CIPKG v2:
offset size field
0      5    "CIPKG"
5      1    version = 2
6      1    flags (bit0 = has_target, bit1 = has_imports)
7      2    header_size (currently 25)
9      4    module_len
13     4    plan_len
17     4    meta_len       # CIPM section
21     4    import_len     # CIPI section
25     module_len          CIVM
...    plan_len            CIPL
...    meta_len            CIPM
...    import_len          CIPI
```

- 所有长度 u32 LE；section 顺序固定；`header_size` 允许未来扩展。
- `meta_len` 必须存在（v2），`import_len` 可为 0（无外部符号）。
- 运行时接受 CIPKG v1（无 CIPM/CIPI，沿用旧的推断式 ABI 校验和搜索）与 v2（严格使用目标/import 元数据）。
- 编译器默认写 v2；可以加 `--cib-version=1` 用于回归测试兼容路径。

### 2.2 CIPM：目标/平台声明（v1）

```
magic "CIPM" (4)
version u8 = 1
header_size u16
arch u8          # 1=x86_64, 2=x86, 3=aarch64
os u8            # 1=linux, 2=windows
abi u8           # 1=sysv, 2=win64, 3=win32, 4=aapcs64
ptr_bits u8      # 32/64
endian u8        # 1=little
flags u8
features u64     # f80/f128, callbacks, varargs, auto-link, ...
min_runtime u16  # 运行时最低 ABI/feature 版本
triple_len u16
triple bytes     # canonical target triple
link_db_id_len u16
link_db_id bytes # 例如 "cstdapi@<commit>;winmd@<commit>"
producer_len u16
producer bytes   # cinterp/clang version
```

- `arch/os/abi/ptr_bits/endian` 用于快速校验；`triple` 用于诊断和未来平台扩展。
- `features` 声明包依赖的 VM/运行时能力；加载时按位与运行时能力比较，缺失则 `UnsupportedFeature`。
- `link_db_id` 记录生成 import 表所用的 cstdapi/winmd 版本，便于复现和排查链接差异。
- CIVM 的 `arch=1` 保持不变（VM 字节码版本），宿主目标只在 CIPM 表达。

### 2.3 CIPI：外部符号链接表（v1）

CIPI 是 plan→provider 的映射；不把完整 cstdapi/winmd 数据库塞进每个 CIB，只写实际用到的符号。

```
magic "CIPI" (4)
version u8 = 1
flags u8
entry_count u16
reserved u16

entry:
  plan_index u16       # CIPL 中该外部 CallPlan 的索引；0xFFFF = 无 plan 的数据符号
  kind u8              # 0=function, 1=data (data 预留)
  flags u8             # required/lazy/allow_fallback/allow_override
  callconv u8          # 0=cdecl, 1=stdcall/winapi, 2=vectorcall(预留)
  arch_mask u8         # bit0 x86_64, bit1 x86, bit2 aarch64
  min_os u16           # 0=unknown; Windows 用 winmd os 映射
  name_len u8
  name bytes           # 逻辑符号名（规范化后的 IR/plan 名）
  provider_count u8
  provider[]:
    kind u8            # 0=system library name, 1=SONAME/DLL name, 2=explicit path (禁止自动使用)
    name_len u8
    name bytes         # "libc.so.6"/"libm.so.6"/"ucrtbase.dll"/"user32.dll"...
    symbol_len u8
    symbol bytes       # provider 内真实符号名，例如 "_snprintf"，可与 name 不同
    ordinal u16        # 0=按名；非 0=按 ordinal（Windows）
    version_len u8     # 预留
    version bytes      # 预留（GLIBC_2.x / API set version）
```

- `plan_index` 与 `CIPL` 的索引绑定；同一符号多次调用可共享 provider 信息，但每条 plan 仍可独立指向。
- `name` 是逻辑名；`provider.symbol` 是实际符号（别名、Windows 修饰名、`_snprintf`）。
- 每个 provider 按顺序尝试；成功后在 VM 内缓存 `(plan_index/provider)` 结果。
- `kind=data` 为未来 `errno`/`stdout` 等 external data 预留；Phase 1/2 先支持函数。
- `flags` 控制：require（失败即错误）/ optional（允许 fallback 或延迟到调用失败）/ allow_override（`--lib` 可覆盖）。
- `arch_mask`/`min_os` 由生成器填充；运行时在加载/首次解析时校验。

### 2.4 运行时解析顺序（v2）

1. `--lib` 显式加载的库（用户覆盖优先，保持现有行为）。
2. CIB `CIPI` 中该 plan 的 provider 列表（顺序尝试）：
   - Linux：`dlopen(provider.name, RTLD_NOW|RTLD_GLOBAL)`，`dlsym`；
   - Windows：`LoadLibraryA(provider.name)`，`GetProcAddress`（按名或 ordinal）；
   - 成功后缓存 provider handle / symbol address。
3. 若 `flags` 允许 fallback，则退回现有进程默认/CRT 搜索（兼容旧 CIB 和未收录符号）。
4. 否则返回 `SymbolNotFound`/`ImportUnavailable`，错误中包含尝试过的 provider 列表。

- CIB 中的 provider 只允许**系统库名/受控 allowlist**；自动链接不得从 CIB 读取任意绝对路径。绝对路径只允许用户显式 `--lib`。
- Windows 缺失 API/OS 版本时优先尝试候选 provider（如 ucrtbase → msvcrt），再报 `ImportUnavailable`；不静默降级到不兼容的 DLL。
- provider handle/符号缓存按 VM 生命周期保存；单线程，无需锁。

## 3. Phase 1：C 标准库自动链接

### 3.1 生成数据

新增 `tools/gen_cstdapi.py`（build-time，非运行时依赖）：

输入（固定 upstream commit）：

- `cstdapi.txt`：C 标准库符号全集。
- `linuxgood.txt` / `linuxbad.txt`：glibc 可用性。
- `wingood.txt` / `winbad.txt`：Windows CRT 可用性。
- `glibcabi.txt`、`abilists/`：glibc provider/版本信息。
- `msvcrt.spec`、`ucrtbase.spec`、`ntdll.spec`：Windows provider 与符号别名。
- 可选 `macgood/macbad`（当前目标不含 macOS，先生成但不用）。

输出（check-in）：

```
compiler/src/cinterp/link/cstdapi.generated.json
{
  "upstream_commit": "...",
  "targets": {
    "x86_64-linux": {
      "printf": {"providers":[{"lib":"libc.so.6","symbol":"printf"}],"available":true},
      "sin": {"providers":[{"lib":"libm.so.6","symbol":"sin"}],"available":true},
      "getrandom": {"providers":[{"lib":"libc.so.6","symbol":"getrandom"}],"min_glibc":"2.25"}
    },
    "x86_64-windows": {
      "snprintf": {"providers":[
        {"lib":"ucrtbase.dll","symbol":"snprintf"},
        {"lib":"msvcrt.dll","symbol":"_snprintf"}
      ],"available":true}
    }
  }
}
```

- 生成器按目标 triple 输出 provider 候选、别名、可用性、最低版本/OS；`winbad`/`linuxbad` 明确列入 `available:false`，编译期给出清晰错误。
- 数据文件带 upstream commit/license/provenance 注释；不联网、不在编译期解析 upstream。
- 标准库签名不作为数据源：参数/返回类型仍来自 clang LLVM IR；cstdapi 只负责“符号→provider/别名/可用性”。

### 3.2 编译器行为

- 新增 `compiler/src/cinterp/link/`：
  - `cstdapi.py`：加载 generated 数据，按 target 查询。
  - `imports.py`：把外部 `CallPlan` 匹配到 import entry；未匹配的符号保留旧的手动 `--lib` 路径。
- 对外部调用：
  - Phase 1 命中 C 标准库：生成 `CIPI` entry，自动选择 provider/别名；不需要用户写 `--lib`。
  - 未命中：不自动猜测（避免加载错误 DLL）；保留现有 fallback/手动 `--lib`，并在 `--dump` 中标记 `unresolved`。
  - `--no-auto-link`：完全关闭自动 import 生成。
  - `--link-db path`：覆盖 generated 数据（测试/私有 CRT）。
- Windows 目标优先使用 ucrtbase，其次 msvcrt/ntdll（按数据）；Linux 优先 `libc.so.6`，数学函数 `libm.so.6`；AArch64 同样按 glibc provider。
- 编译期检查：`available:false`、目标架构不匹配、缺少 provider → 错误含 cstdapi 来源/原因；不生成不可加载的 import。

### 3.3 验收

- 四个目标（sysv/win64/win32/arm64）分别编译并运行不写 `--lib` 的示例：
  `printf/snprintf/malloc/free/qsort/strcmp/strlen/memcpy/memset`，Linux 再加 `sin/cos`（libm）。
- CIB `--dump-imports` 能列出 plan→provider/alias。
- Windows `snprintf` 自动选 `_snprintf`；不再依赖 native.zig 的硬编码别名（硬编码可保留为 legacy fallback）。
- 旧 CIB v1 仍可加载；新 CIB v2 在错误 OS/arch 上 `TargetMismatch`。
- 体积：import 只包含使用符号；hello 无外部符号时 CIPI 为空。

## 4. Phase 2：Windows 全 API 自动链接

### 4.1 生成数据

新增 `tools/gen_winmd.py`：

- 输入 `winmd/apis.json`（或 `apis.txt`），固定 commit。
- 对每条 API 提取：
  - `name`、`dll`、`callconv`、`os`、`arch`（如数据未显式给出，按 winmd 元数据/Windows API contract 补全）。
  - 重名 API：保留多个 provider，按 DLL/OS/arch 排序。
  - `A/W` 变体、别名、ordinal（若 metadata 可提供）。
- 生成紧凑索引：
  ```
  compiler/src/cinterp/link/winmd.generated.bin  # 或 .json.zst
  name → [{dll, symbol, callconv, min_os, arch_mask, ordinal?}]
  ```
- 不把 10MB `apis.json` 放进 CIB；只有每个 CIB 实际使用的 API 进入 `CIPI`。

### 4.2 编译器行为

- Windows 目标下，外部声明/调用名匹配 winmd 索引：
  - 自动写 import entry：`dll`、真实符号、`callconv`（winapi→Win32 stdcall / Win64 等）、`min_os`、`arch_mask`。
  - `A`/`W` 名称按 IR 名匹配；无匹配时保留手动 `--lib`/报未解析。
  - 已有 CIPL plan 负责参数/返回 ABI；winmd 的 args/ret 可用于交叉校验（可选，Phase 2 后半）。
- 调用约定：
  - `winapi` 在 Win32 映射为 `stdcall`（CIPL conv=1），Win64/ARM64 按各自 ABI；
  - `cdecl` 保持 cdecl；
  - 不支持 `vectorcall`/COM 时编译期明确报错。
- API 可用性：
  - 目标 `min_os` 高于运行时/目标配置时给出 `ImportUnavailable` 或警告；
  - `arch_mask` 不匹配（例如 x86-only API 在 x64）编译期错误。
- `--no-auto-link`/`--link-db` 同样适用于 Windows。

### 4.3 运行时行为

- 首次调用时按 CIPI 的 DLL provider 自动 `LoadLibraryA`（只允许系统 DLL/API set 名；禁止 CIB 携带绝对路径）。
- `GetProcAddress` 支持按名、别名和 ordinal；按 provider 顺序失败回退。
- 缓存 DLL handle 和符号地址；卸载随 VM 销毁（或保持与 `--lib` 相同的生命周期）。
- Windows API set（`api-ms-win-*`）通过系统 loader 转发；若目标机器缺少 API，报 `ImportUnavailable`，不要静默改用不兼容 DLL。
- 与 `--lib` 的关系：显式 `--lib` 优先，允许用户覆盖系统 provider（测试/兼容层）。

### 4.4 验收

- Windows 测试机（x64 + WoW64 x86）自动调用不使用 `--lib`：
  - `kernel32.dll`：`GetTickCount64`/`Sleep`；
  - `user32.dll`：`MessageBoxA` 仅做非交互/不弹窗测试或 `GetSystemMetrics`；
  - `advapi32.dll`/`bcrypt.dll` 等非 GUI API；
  - `A`/`W`、stdcall/cdecl、64 位返回值、struct 参数。
- `--dump-imports` 输出 DLL/symbol/conv/min_os；错误目标加载失败。
- Win64/Win32/ARM64 的 import 表按 arch/OS 过滤；同一 CIB 不会在错误平台静默运行。
- 测试 Windows 全 API 索引生成可重复、带 commit/license；CI 只检查代表性 API，不跑 18k 全量调用。

## 5. 代码改动清单（预计）

- `compiler/src/cinterp/codegen/binary_writer.py`：CIPKG v2 section 写入。
- 新增 `compiler/src/cinterp/link/`：
  - `target.py`（target metadata）
  - `cstdapi.py`、`winmd.py`（数据库加载/匹配）
  - `imports.py`（CIPI 生成、plan_index 绑定）
- `compiler/src/cinterp/ffi/plan.py`：保持不变（ABI 计划）；plan 索引仍由 PlanTable 管理。
- `compiler/src/cinterp/llvm_ir/lower.py`：外部调用生成 import entries；保留旧 fallback。
- `compiler/src/cinterp/cli.py`：`--cib-version`、`--no-auto-link`、`--link-db`、`--dump-imports`。
- `runtime/src/ffi/package_loader.zig`（或 `main`/`vm` 拆分）：解析 CIPKG v2/CIPM/CIPI。
- `runtime/src/ffi/link.zig`：provider 解析、DLL/DSO 加载、符号缓存、校验。
- `runtime/src/ffi/native.zig`：保留底层 dlopen/LoadLibrary；新增按 provider 加载。
- `runtime/src/vm.zig`：`resolveNative` 使用 CIPI；旧路径 fallback；错误信息。
- `runtime/src/main.zig`：目标校验/诊断、`--dump-target`/`--dump-imports`。
- `tools/gen_cstdapi.py`、`tools/gen_winmd.py`、生成数据、provenance/license。
- `docs/cib.md`：CIPKG v2/CIPM/CIPI 完整字段表；更新示例。
- 测试/CI：格式 round-trip、目标不匹配、provider 回退、Windows 自动化、体积预算。

## 6. 版本与兼容策略

- CIPKG v2 默认；v1 旧包继续可读（无目标/import 元数据）。
- CIPM v1、CIPI v1 独立版本；新增字段用 flags/header_size 扩展。
- CIPL 保持 v3；import 表通过 plan_index 关联，避免破坏 ABI 计划格式。
- 未知 section/version：`UnsupportedCibVersion`；未知 provider kind：`UnsupportedProvider`。
- 生成数据库带 upstream commit 与 schema version；编译器/运行时版本不匹配时给出可诊断错误。

## 7. 安全与边界

- 自动 provider 只允许**系统库名/allowlist**；CIB 不能指定任意磁盘路径或命令行参数。
- 不允许自动加载 CIB 内嵌的二进制；`--lib` 是显式用户授权路径。
- 目标/OS/arch 校验在模块/计划解析前执行；计划 ABI 必须与 CIPM.abi 一致。
- 符号错误包含 provider 尝试列表；不静默加载同名但 ABI 不兼容的 DLL。
- Windows API 的 `min_os`/arch 过滤在编译期和运行期各做一次；缺失时报错而非猜测。
- 仍不引入 libffi、JIT 或动态可执行内存；provider 加载只影响符号来源。

## 8. 开放决策

1. CIPKG v2 section 顺序/header 字段是否采用本文布局，还是把 CIPM/CIPI 作为可选 TLV section？
2. 显式 `--lib` 与 CIB provider 的优先级（当前 proposal：`--lib` 优先覆盖）。
3. Phase 1 未匹配标准库符号：编译期错误，还是保留旧 fallback 并警告？
4. Windows provider 选择：ucrtbase 优先还是 msvcrt 优先；是否按 Windows 版本动态选择？
5. winmd 索引用 JSON/zstd、SQLite 还是自定义二进制；是否把按名索引拆成多个文件以控制仓库体积。
6. Windows API 签名（winmd args/ret）是否只做交叉校验，还是也用于参数 ABI 自动修正？
7. `data` 符号（`errno`/`stdout`）是否纳入 Phase 1/2，还是单独 Phase 3。

## 9. 完成定义

- Phase 1 完成：四个现有目标上，C 标准库示例无需 `--lib` 自动链接；CIPKG v2 + CIPM + CIPI 通过 round-trip/错误路径/真实运行；旧 v1 兼容；文档更新。
- Phase 2 完成：Windows x64/x86（及 ARM64 如 CI 可用）代表性 API 自动从 winmd DLL 解析；stdcall/cdecl、alias/ordinal、min_os/arch 校验；错误 provider 有诊断；文档/CI 更新。
- 只有实际使用的 import 进入 CIB；CIB 体积预算和 fuzz 覆盖新 section。
