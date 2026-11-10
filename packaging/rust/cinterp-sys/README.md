# cinterp-sys

用于 cinterp C 嵌入 ABI 的原始 FFI 绑定以及一个小型安全封装。

该 crate 随 cinterp 发布 tarball 一起分发，位于 `rust/cinterp-sys`。
它期望原生库位于相对于 crate 目录的 `../../lib`，头文件位于
`../../include`。可以用下面的方式覆盖这些路径：

```bash
export CINTERP_LIB_DIR=/opt/cinterp/lib
export CINTERP_INCLUDE_DIR=/opt/cinterp/include
```

或者把该 crate 作为路径依赖加入：

```toml
[dependencies]
cinterp-sys = { path = "vendor/cinterp-sys" }
```

## 运行示例

`examples/run_hello.rs` 加载一个包，运行一个入口点并打印
结果。`--expect N` 会把它变成一个冒烟测试：结果不同时以非零状态退出。

```bash
cd rust/cinterp-sys
cargo run --offline --example run_hello -- /path/to/app.cib --expect 42
# result = 42
```

该示例在运行时同样需要这个共享库；如果该库没有安装在系统范围内，
请先导出加载器路径：

```bash
export LD_LIBRARY_PATH="$PWD/../../lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
```

## 测试

```bash
cargo test --offline
```

该 crate 的单元测试覆盖 `CI_*` 状态名称、`Error` 格式化以及
原生库报告的 ABI 版本。它们会链接 `libcinterp`，因此请在
`CINTERP_LIB_DIR`（或 `../../lib`）能够解析的位置运行。

## API 说明

- `Vm::last_error_code()` 返回最近一次失败调用的稳定 `CI_E_*` 分类；
  `Vm::last_error()` 返回其消息，`Vm::clear_error()` 会把两者都重置。
- `Error::code` 就是该分类（`ci_vm_last_error_code`），`Error::status`
  是失败调用返回的负值，`Error::message` 是来自 `ci_vm_last_error()` 的
  文本。`status_name(code)` 会把 crate 已知的 `CI_*` 值映射到名称，未知值
  返回 `UNKNOWN`；`CI_E_BUSY = -12` 已包含在 `status_name` 中。
- `CI_ERROR` 表示运行时无法对该失败进行分类；其他所有失败都是
  具体的 `CI_E_*` 值。

## 多 VM、线程与 callback

- 每个 `Vm` 同一时间只允许一个执行上下文。需要并行执行时，请为每个任务创建独立的
  `Vm` 实例；同一进程中的不同 `Vm` 可以在不同线程上并行运行。
- 当前 crate 只封装了核心 `ci_vm_*` 函数。多 CIB 的 `ci_process_*` 注册表、
  `ci_vm_busy`、`ci_vm_destroy_ex`、`ci_vm_callback_error` 和
  `ci_callback_pool_stats` 尚未提供安全封装；需要这些能力时，请在 Rust 中直接声明
  对应的 `extern "C"`（头文件见发布 tarball 的 `include/cinterp.h`），或使用 C 宿主。
  此时的 busy 状态是 `CI_E_BUSY = -12`；`Error::status` 会保留该负值。
- 回调 trampoline 是进程范围的固定 256 个静态槽。自动 `@cb`/`CREATE_CALLBACK` 槽绑定
  到所属 `Vm`，跨重复运行保留，`Vm` 被销毁或计划重载时退休。CIB 内的 C 代码可以用
  `ci_callback_acquire`/`ci_callback_release` 显式管理生命周期：release 成功后槽位可
  复用，释放后的旧指针不得再次调用；未 release 的显式槽随 VM 销毁/重载退休。
- 每次 `run` 都是全新镜像（线性内存/值栈/帧/`setjmp` 目标重置，`main` 重新安装
  globals），`Vm::result()` 返回最后一次成功运行的结果。运行时只接受 `main` 入口别名；
  其他入口名返回 `CI_E_ENTRY`。

## 示例代码

```rust
use cinterp_sys::Vm;

let bytes = std::fs::read("app.cib").unwrap();
let mut vm = Vm::new(0).expect("create VM");
vm.load_package(&bytes).expect("load package");
let args = ["app", "--flag"];
vm.run_args("main", &args).expect("run");
println!("result = {}", vm.result());
```

每个 `Vm` 都是单执行上下文的。独立或并行执行请使用单独的 `Vm` 实例；回调跳板是
进程范围的：自动槽在所属 `Vm` 被销毁或计划重载时退休，显式 acquire/release 的槽在
release 后可复用。需要多 CIB 的进程级注册表时，请使用 C 头文件中的 `ci_process_*`，
参见发布 tarball 中的 `docs/multi-cib.md`、`docs/embedding.md` 和
`docs/compatibility.md`。
