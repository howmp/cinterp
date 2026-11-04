# CS-Situational-Awareness-BOF 示例源码

上游：[trustedsec/CS-Situational-Awareness-BOF](https://github.com/trustedsec/CS-Situational-Awareness-BOF)  
固定提交：`fd96c4dcd88fd00eea902bebb20d0736e48f5f61`

本目录收录上游 `src/common` 和 `src/SA` 的完整 BOF 源码，用于验证
`cinterp-cc` 对 BOF 风格 C 代码的编译能力。

> 上游 BOF 源码使用 **GPL-2.0**，见本目录 [`LICENSE`](./LICENSE)。它与仓库根目录
> 的 MIT 许可证相互独立。

## 编译

`cinterp-cc` 不接受 `-I/-D` 参数，`compile.py` 会为每个 `entry.c` 生成临时包装源：

- 定义 `BOF`、加入 `src/common` 头文件；
- 从 `bofdefs.h` 自动生成 `KERNEL32$Foo -> Foo`、`MSVCRT$foo -> foo` 等前缀映射；
- 把 `BeaconPrintf`/`BeaconOutput` 映射到本地 shim；
- 补齐 `wcstok`、`getaddrinfo`、`ConvertSidToStringSidW`、`DnsGetCacheDataTable`
  等 MinGW 头文件差异；
- 给 `ipconfig` 预置 winsock/iphlpapi include 顺序，暴露
  `PIP_ADAPTER_ADDRESSES`/gateway 类型；
- 添加 `main() { go(NULL, 0); }`。

```bash
make compiler
python3 examples/bof/compile.py --target x86_64-windows --jobs 4
python3 examples/bof/compile.py --target i686-windows --jobs 4
```

输出默认在 `build/bof/<target>/<name>.cib`。

## 结果

- 普通符号版本：x64 `72/72`、x86 `72/72` 编译成功。
- 生成的 CIB 在 Wine 下 `--load-only`：x64 `72/72`、x86 `72/72`。
- `hostname` 在 Wine 下实际运行并输出：

```text
result: 0
[*] Computer Name: DEBIAN[-] Not domain joined (workgroup member)[*] Workgroup: Workgroup
```

（`result:` 与 BOF 自身 stdout 的顺序可能因宿主缓冲不同而变化。）

## 运行示例

```bash
WINEARCH=win64 WINEPREFIX="$PWD/build/wine64" \
WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" \
  wine build/cross/cinterp-run64.exe build/bof/x86_64-windows/hostname.cib
```

需要先构建 cross runtime（例如 `make test-suites-cross CROSS_SUITE_TARGETS=win64,win32`）。

## 边界

- 生成的是 `cinterp` CIB，不是 Cobalt Strike 的 COFF `.o`。
- 不是通用 BOF loader：只提供 `BeaconPrintf`/`BeaconOutput` shim，没有实现
  `BeaconDataParse`、`BeaconFormat*`、`BeaconUseToken` 等 API，也不会解析真实
  Beacon 参数缓冲区。
- `go(char *, int)` 仍需要 loader 传入参数；当前示例用 `go(NULL, 0)` 验证不依赖
  输入的 BOF（如 `hostname`）。
- 运行时仍通过普通 WinAPI/CRT 符号解析；BOF 的 `$` 名称在编译包装层被规范化。
