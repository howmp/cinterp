# keygenme

这个示例把一份 C 源码编译成 cinterp 的 CIB 字节码，再由 Zig 宿主编译期嵌入
字节码，生成不依赖外部 `.cib` 文件的独立可执行程序。它同时包含一个可复现的
keygen 挑战。

## 文件

| 文件 | 作用 |
| --- | --- |
| `keygenme.c` | 挑战程序；校验用户名和序列号 |
| `src/main.zig` | Zig 宿主；嵌入 CIB 并调用 `ci_vm_*` |
| `build.zig` | 构建宿主，按目标选择 VM 汇编后端并嵌入 CIB |
| `build.sh` | 编译四个平台的 CIB、构建对应二进制、生成 CIB dump |
| `keygen.py` | 参考 keygen；实现 Feistel 逆变换 |
| `CHALLENGE.md` | 挑战目标、输入格式和提示 |

## 构建

需要 Zig 0.13 和 Python 3。在仓库根目录运行：

```sh
make keygenme
```

该目标会先构建 `cinterp-cc`，然后生成：

```text
build/keygenme/keygenme-linux-x86_64
build/keygenme/keygenme-linux-aarch64
build/keygenme/keygenme-windows-x86_64.exe
build/keygenme/keygenme-windows-x86.exe
build/keygenme/cib/keygenme-<target>.cib
build/keygenme/keygenme-<target>.dump.txt
```

每个 CIB 的 dump 由 `scripts/tools/cib_dump.py` 生成，包含 CIPKG/CIVM 头部、
反汇编和常量池摘要。也可以手动重新生成：

```sh
python3 scripts/tools/cib_dump.py build/keygenme/cib/keygenme-linux-x86_64.cib
```

## 运行

Linux x86-64：

```sh
./build/keygenme/keygenme-linux-x86_64 alice LJN5-AU8D-DUPN-2222
# Access granted: welcome, alice!
```

一个用户名可以有多个合法序列号，用参考 keygen 生成：

```sh
python3 examples/keygenme/keygen.py alice
python3 examples/keygenme/keygen.py alice --salt 0xabcde
python3 examples/keygenme/keygen.py alice --count 3
```

ARM64 使用 qemu：

```sh
qemu-aarch64 -L /usr/aarch64-linux-gnu \
  ./build/keygenme/keygenme-linux-aarch64 alice LJN5-AU8D-DUPN-2222
```

Windows 使用 Wine；如果默认前缀不可用，可参考 `scripts/test/test_cross.sh`
准备的 `build/wine64` / `build/wine32`：

```sh
wine build/keygenme/keygenme-windows-x86_64.exe alice LJN5-AU8D-DUPN-2222
wine build/keygenme/keygenme-windows-x86.exe alice LJN5-AU8D-DUPN-2222
```

退出码：合法序列号 `0`；格式错误或校验失败 `1`；参数错误 `2`。宿主加载或执行
CIB 失败也返回 `1`。

## 实现说明

- `build.sh` 为每个目标单独编译 CIB，因为 CIVM 包带目标架构，不能跨架构复用。
- `build.zig` 通过 `@embedFile` 生成模块把 CIB 嵌入宿主；运行时不需要读取
  外部文件。
- VM 代码和平台 ABI 汇编直接来自 `runtime/src`，按目标选择 SysV、Win64、
  Win32 或 AArch64 后端，因此这个示例不依赖预构建的运行时库。
- 校验算法使用 60 位状态和 20 位 salt 的 24 轮 Feistel。每个用户名约有
  `2^20` 个合法序列号，程序内不存在唯一的期望 key；简单调试器在最终比较处
  只能看到变换后的状态和用户名 tag。真正的 keygen 需要逆推轮函数。挑战
  说明见 [`CHALLENGE.md`](CHALLENGE.md)。
- 本地校验器仍然可以被 patch；本示例不是安全边界，也不试图防止 patch。
