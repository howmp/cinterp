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
  文本。`status_name(code)` 会把其中任一值映射到对应的 `CI_*` 名称，便于
  记录日志。
- `CI_ERROR` 表示运行时无法对该失败进行分类；其他所有失败都是
  具体的 `CI_E_*` 值。

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

每个 `Vm` 都是单线程的。独立执行请使用单独的 `Vm` 实例；回调跳板是
进程范围的，在其所属的 VM 被销毁时退役。参见发布 tarball 中的
`docs/embedding.md` 和 `docs/compatibility.md`。
