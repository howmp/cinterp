---
name: production-embedding-readiness
overview: 生产嵌入调查结论；P0 1–3（库/header、C API 合同、VM 回调隔离）已完成并验证，剩余安全、正确性和发布合同。
---

# 生产嵌入可用性结论

## 结论

**当前项目已有可链接的 `libcinterp`、C 头文件和单 VM C API；但距离生产可用仍受 P0 4–6（安全、正确性、发布合同）阻断。**

- 作为 `cinterp-run` 独立子进程运行时，只能有条件试用：CIB 必须来自可信构建流水线，每个 CIB 一个进程，并在 OS sandbox、资源限制和 wall-clock kill 下运行。
- `ci_vm_*` 现在可通过 `libcinterp.a`/`libcinterp.so`（Windows `cinterp_static.lib`/`cinterp.dll`）和 `runtime/include/cinterp.h` 链接；仍缺少 pkg-config/CMake/Rust 绑定。
- 不能运行不可信 CIB：CIB 可表达任意原生调用，`--safe` 是 fuzzing 辅助，不是安全边界。
- 多 VM 已有 callback 隔离和 destroy 清理；但同一个 VM 仍要求单线程串行调用，不能并发执行。
- 不适合 MCU/资源敏感嵌入式设备：每实例约 10 MB 固定内存，且只支持 Linux/Windows 的 64 位/32 位特定目标。

## 已验证的基础

- full：4292/4519 通过，227 skip；standard：394/495 通过，101 skip。
- 4 个 ABI：x86_64-linux、x86_64-windows、i686-windows、aarch64-linux；cross suite 保持通过。
- 运行 CIB 不需要 clang；编译器是构建期 Python 工具。
- 无 JIT、无运行期 codegen、无可执行内存；CIB 目标/ABI/指针宽度/端序在 load 时校验。
- 已有真正的 FFI plan 校验、4 ABI 调用引擎和 callback 回归覆盖。

## 阻断项

### P0：正式嵌入前必须解决

1. **可链接的库和头文件（已完成）**
   - `runtime/build.zig` 现在安装 `libcinterp.a`、`libcinterp.so`（Windows 为 `cinterp_static.lib`/`cinterp.lib`/`cinterp.dll`）和 `runtime/include/cinterp.h`。
   - 已验证 C 程序可分别静态/动态链接并运行；release 打包包含 header/lib/DLL。

2. **C API 合同（已完成）**
   - `ci_vm_create(stack_size)` 现在把参数作为 VM 值栈上限；新增 `ci_vm_create_ex`/`ci_vm_config`。
   - 新增 ABI/版本查询、`ci_vm_run_args`、`ci_vm_result`、稳定错误码、`ci_vm_last_error_code`、错误清理。
   - `ci_vm_run` 返回状态而非截断结果；package/module loader 是事务性的，失败保留旧状态。

3. **VM 多实例/回调生命周期（已完成）**
   - callback entry 和逻辑槽映射移入 VM；trampoline 使用进程级安全槽映射，destroy/plan 重载会退休旧槽并等待活跃回调结束，避免跨 VM 串调和 UAF。
   - C API 回归覆盖两个 VM 同时使用 qsort callback、销毁其中一个后另一个继续运行。

4. **`--safe` 不是安全边界**
   - 未覆盖 `VA_START`/`VA_COPY`/`FPCLASS`、callback 和部分算术路径；已观察到 `--safe` 下的 SIGSEGV/SIGFPE 和宿主内存访问。
   - 没有指令预算、超时或取消接口，死循环无法在 VM 内停止。
   - 不可信执行必须使用独立进程/容器 + OS 级隔离；不能只依赖 VM 模式。

5. **正确性仍有系统性缺口**
   - 46 个 GCC execute 失败，已审计排除项中仍有约 125 个 `bug` 标签（另有 non-goal/dialect 分类）。
   - 32 位整数在 `add/sub/mul/icmp/ret` 上的宽度归一化不完整，可能导致溢出类误编译。
   - 全局常量地址表达式（如 `&array[i].field`）不可靠；varargs 路径仍存在 SIGSEGV 类失败。
   - 这些属于嵌入式/正式项目的实际风险，不是单纯的测试边角。

6. **发布与法律合同缺失**
   - 仓库没有 LICENSE；release tarball 已包含 header/lib/DLL，但仍不含许可证。
   - 版本号分散在 6 处，`runtime_version` 与发布版本没有映射，没有 CIB/API 兼容策略。
   - 没有正式 release workflow、SBOM、校验和/签名、split debug 产物。

### P1：生产质量

- 将 plan store 改为按包大小分配；让 stack/memory 可配置；减少约 10 MB/实例。
- 支持 musl 或明确拒绝并给出清晰错误；当前 Linux provider 硬编码 `libc.so.6`/`libm.so.6`。
- 修复 `alloca` 大小为 0/溢出的前端限制，并重新标注误导性的 `resource:` 分类。
- 增加 sanitizer、结构化 bytecode fuzz、启用 FFI 的 exec fuzz、跨 ABI fuzz。
- 把 cross-ABI 测试放进 CI，去掉手工 LAN IP 依赖。
- 修正 `docs/cib.md` 与代码不一致的容量限制，补英文嵌入指南和错误码表。
- 修正 macOS/未知 OS 被静默映射为 Linux 的目标校验问题。

## 建议的落地路径

### 阶段 A：现在可用（不修改运行时 API）

- 构建期生成 CIB，只运行自有/已审查的 CIB。
- 使用独立 `cinterp-run` 子进程，每 CIB 一进程。
- 外层加 OS sandbox、只读文件系统、无网络、CPU/内存限制和硬超时。
- 把 `--safe` 仅用于 fuzzing/诊断，不作为安全控制。
- 不把第三方 CIB、`--lib` 或宿主动态库暴露给不可信输入。

### 阶段 B：成为可嵌入库（P0 1–3 已完成）

- `libcinterp`/`cinterp.h` 和单 VM、单线程、可信 CIB 的基础 API 已完成。
- C API 错误/结果/argv/版本合同和原子 load 已完成。
- callback 全局状态、destroy 清理和多 VM 隔离已完成；嵌套 run 保护仍未完成。
- 剩余：LICENSE、版本单一来源、release manifest、pkg-config/CMake/Rust 绑定。

### 阶段 C：生产级/多租户

- 指令预算/取消、可配置内存、provider 清理和符号 allowlist。
- 修复整数宽度、全局常量地址、varargs 崩溃等正确性问题。
- 完成 CI 跨 ABI、sanitizer、结构化 fuzz 和兼容性回归。
- 若要运行不可信代码，始终以进程/容器为边界，而不是依赖 VM 内部 `--safe`。

## 明确的支持边界

当前只适合：

- 单线程、单 VM、每进程一个 CIB。
- Linux x86_64/aarch64（glibc）或 Windows x64/x86。
- C17、单 translation unit、≤512 函数、≤2 MiB module、≤1 MiB globals/VLA、递归 ≤512 帧、单对象 ≤64 KiB。
- 调用 host libc、但不依赖线程/atomics/`_Complex`/SIMD/函数指针身份/外部 inline/weak 的代码。
- 可信或半可信插件/规则脚本，并且宿主提供外部隔离。

明确不适合：

- MCU、裸机、musl、macOS、Windows ARM64、Linux 32 位/ARM32。
- 在宿主进程内直接执行用户上传的 CIB。
- 一个进程多 VM、多线程共享 VM、依赖回调跨线程。
- 要求与 GCC/Clang 在 32 位整数边界和完整 C 语义上逐字节一致的项目。
