# `.cib` 文件结构

`.cib` 是 `cinterp compile` 生成的**发布包**。当前默认外层格式为 `CIPKG` v3（trusted），内部由三个 section 组成：

1. `CIVM`：字节码模块（函数表 + 每个函数的 code）；
2. `CIPL`：FFI/callback 计划表（每个外部符号的参数/返回位置）；
3. `CIPI`：外部符号链接表（plan → provider 库/符号/别名/架构/最低 OS）。

v3 不写目标声明，也不执行目标校验：包必须由与编译目标匹配的运行时加载。本文描述的是**当前实现**的唯一二进制格式；代码是最终事实来源：

- `compiler/src/main.zig`：`CIPKG`、CIPI 写入
- `compiler/src/lower_ast.zig`：CIVM、opcode、globals 初始化
- `compiler/src/abi.zig`：CIPL、`Loc`/`ArgPlan`/`CallPlan`
- `compiler/src/imports.zig`：CIPI 结构与序列化
- `compiler/src/link_index.zig`：构建期生成的符号索引的二进制格式
- `compiler/src/win_defs.zig`：Windows provider（Zig 自带 MinGW `.def` 数据）
- `compiler/src/libc_defs.zig`：Linux provider（Zig 自带 glibc `abilists` 数据）
- `compiler/src/link_wrappers.zig` + `src/data/link_wrappers.json`：target 级 ABI 别名（`snprintf -> _snprintf`）
- `compiler/tools/gen_link_index.zig`：构建期索引生成器
- `runtime/src/vm.zig`：CIVM 解析、opcode 执行、C ABI、provider 解析
- `runtime/src/ffi/plan_loader.zig`：CIPL 解析
- `runtime/src/ffi/link_loader.zig`：CIPI 解析
- `runtime/src/ffi/platform.zig`：ABI/frame/marshal 选择与目标校验

## 1. 通用约定

- 所有多字节整数/浮点位模式均为**小端**。
- 没有对齐 padding、checksum、签名或压缩。
- `CIVM` 是虚拟机字节码，不是宿主 CPU 机器码；`CIPKG`/CIPL 的 ABI id 指示计划对应的宿主 ABI。
- 包不携带目标声明，运行时不做目标校验；计划表与运行时 ABI 的 `abi_id` 仍必须一致（`BadAbi`）。
- CIPI 的 plan 索引必须指向本包 CIPL 中的外部计划；运行时加载时校验。
- 所有二进制长度按实际字节数写入，读取器会拒绝截断、尾随字节和越界计数。

## 2. CIPKG 外层

### 2.1 v3 trusted（默认）

```
offset  size  field
0       5     magic = "CIPKG"
5       1     version = 3
6       4     module_len (u32 LE)
10      4     plan_len   (u32 LE)
14      4     import_len (u32 LE)
18      module_len       CIVM module bytes
...     plan_len         CIPL plan table bytes
...     import_len       CIPI import section
```

v3 没有 flags/header_size 和 diagnostics。`18 + module_len + plan_len + import_len` 必须等于文件长度；运行时仍解析 CIVM/CIPL/CIPI，但不做目标声明校验。CIPKG v3 的 `CIPL` 仍携带 ABI id，运行时用它防止明显的 ABI 混用。

### 2.2 CIPI：外部符号链接表（v1）

```
offset size field
0      4    magic = "CIPI"
4      1    version = 1
5      1    flags
6      2    entry_count (u16)
8      2    reserved = 0
10     entry[]
```

每个 entry：

```
2     plan_index       # CIPL 计划索引；0xffff 预留给 data 符号
1     kind             # 0=function, 1=data
1     flags            # bit0=required, bit1=lazy, bit2=allow_fallback, bit3=allow_override
1     callconv         # 0=cdecl, 1=stdcall/winapi, 2=fastcall, 3=thiscall（后三者仅 Win32）
1     arch_mask        # bit0=x86_64, bit1=x86, bit2=aarch64; 0=all
2     min_os           # 0=unknown; Windows 编码为 (major<<8)|minor
1     name_len
N     name             # 逻辑符号名（plan 名，可能含 Win32 修饰）
1     provider_count
provider[]:
  1   kind             # 0=system library name, 1=SONAME/DLL name, 2=path（自动链接禁用）
  1   name_len
  N   name             # e.g. libc.so.6 / libm.so.6 / ucrtbase.dll / user32.dll
  1   symbol_len
  N   symbol           # provider 内真实符号，例如 _snprintf / GetTickCount64
  2   ordinal          # 0=按名；非 0=Windows ordinal
  1   version_len
  N   version          # 预留（GLIBC_2.x / API set 版本）
```

- `plan_index` 绑定 CIPL；`0xffff` 表示 data entry，`ADDR_EXTERN` 使用 entry 索引解析地址。同一符号多次调用可以有多条 entry。
- provider 按顺序尝试；成功后缓存库 handle 和符号地址。
- 自动生成的 provider 只能是系统库名/allowlist；运行时会拒绝包含 `/`、`\` 或 `:` 的自动 provider 名，避免 CIB 指定任意路径。显式 `--lib` 仍允许用户路径。
- 一个 VM 实例同一时间只持有一个包（再次 `load_package` 会整体替换）；一个进程可以用
  `ci_process_*` 持有多个各自独立的 VM。CIPI 不提供 CIB-to-CIB 链接/包间导出表，
  跨包请合并源码后重新生成。
- `arch_mask` 与 `min_os` 在加载时校验；不匹配返回 `ImportArchMismatch` / `ImportUnavailable`。
- `kind=data` 已支持 `stdout`/`errno` 类 external data：编译器为未知外部全局生成 data entry，运行时按 provider/`--lib` 解析地址；`ordinal` 解析在 Windows 已支持。

### 2.3 运行时符号解析顺序

对有 CIPI entry 的函数计划：

1. 若 entry 允许 override（flags bit3），先搜索用户 `--lib` 加载的库（逆序）。
2. 按 CIPI provider 顺序 `dlopen`/`LoadLibraryA` 并 `dlsym`/`GetProcAddress`；缓存成功结果。
3. 若 entry 允许 fallback（flags bit2），再走进程默认 → `--lib` → CRT 搜索。
4. 否则返回 `SymbolNotFound`。

对 data entry（`CIPI.kind=data`，`ADDR_EXTERN`）：总是先搜索 `--lib`，再按 provider 顺序解析；仍失败则回退到进程/CRT 搜索。

没有 CIPI entry 的计划（旧 v1 包或未收录的自定义符号）仍走旧搜索路径。

### 2.4 外部符号索引（构建期生成）

编译器按 target 自动生成 CIPI，只写实际使用的外部符号。符号 → provider 的映射不再来自签入的数据库，而是在构建期由 `compiler/tools/gen_link_index.zig` 从已安装的 Zig 工具链生成，并以二进制表内嵌进 `cinterp-cc`：

- **Linux**（`compiler/src/libc_defs.zig`，`glibc-abilists@<zig version>`）：解析 `<zig lib>/libc/glibc/abilists`，只保留 `x86_64-linux-gnu` 与 `aarch64-linux-gnu`；库名映射 `c → libc.so.6`、`m → libm.so.6`、`pthread → libpthread.so.0`、`dl → libdl.so.2`、`rt → librt.so.1`、`util → libutil.so.1`、`resolv → libresolv.so.2`，`ld`（动态 loader）不作为 provider。`printf`/`qsort` → `libc.so.6`，`sin` → `libm.so.6`，`pthread_create` → `libc.so.6` + `libpthread.so.0`。
- **Windows**（`compiler/src/win_defs.zig`，`mingw-defs@<zig version>`）：解析 `<zig lib>/libc/mingw/{lib32,lib64,lib-common}/*.def` 与 `lib-common/*.def.in`（用 `zig cc -E` 预处理），得到 DLL、实际导出符号、`arch_mask` 与调用约定。具体 DLL（`kernel32.dll`/`user32.dll`）优先于 `api-ms-win-*`；`ucrtbase` 优先于 `msvcrt`；PE 可执行文件（`*.exe`）永不作为 provider。
- **别名**：`compiler/src/data/link_wrappers.json` 是唯一保留的签入链接元数据，提供同签名 target 别名（Windows `snprintf -> _snprintf`、`vsnprintf -> _vsnprintf`）；`atexit -> __cxa_atexit` 仍由 `lower_ast.zig` 处理。
- **运行期 fallback**：索引未收录的符号不写 plan entry，运行期从进程符号、`--lib` 库、默认 CRT 库（Linux `libc.so.6`/`libm.so.6`/`libdl.so.2`/`libpthread.so.0`/`librt.so.1`/`libutil.so.1`/`libresolv.so.2`，Windows `msvcrt.dll`/`ucrtbase.dll`/`ntdll.dll`）继续解析。Windows plan entry 的 provider 允许失败后 fallback（flag bit2）。
- **`min_os`**：MinGW defs 没有最低 OS 版本信息，新包的 plan entry 一律写 `min_os=0`；旧包仍按其原字段校验。
- `--no-auto-link` 关闭生成；自定义符号继续使用 `--lib`/运行期 fallback。

## 3. CIVM 模块（v1）

### 3.1 头部

```
offset size field
0      4    magic = "CIVM"
4      1    version = 1
5      1    arch = 1          # VM 字节码架构，不是宿主 CPU
6      2    func_count (u16)
8      2    reserved = 0
```

### 3.2 函数记录（重复 `func_count` 次）

```
size  field
1     name_len (u8)
N     name bytes (UTF-8)
2     param_count (u16)
2     local_count (u16)
4     code_len (u32)
M     code bytes
```

- `param_count` 是函数参数个数；参数占用函数局部槽的**前 `param_count` 个**。
- `local_count` 包含参数槽和后续 alloca/SSA 槽；必须 `>= param_count`。
- 函数名有效上限为运行时的 `MAX_NAME = 128` 字节；函数数上限 `MAX_FUNCS = 512`。
- code 是字节流，跳转目标是**当前函数 code 内的绝对字节偏移**。
- 入口默认是 `main`，运行时可指定其他入口。

### 3.3 槽、栈与返回值

- 每个槽/栈项是 8 字节 `Value`，按 `i64` 或 `u64` 解释。
- 函数帧：调用者先压入 `param_count` 个参数值；`OP_CALL` 以
  `callee_base = sp - param_count` 建立被调帧，清零 `callee_base+param_count`
  到 `callee_base+local_count-1`。
- `OP_RET` 弹出一个值并返回给调用者；入口/Callback 的 `RET` 直接结束执行。
- 运行时槽栈默认/上限 `MAX_STACK = 8192`（`ci_vm_config.stack_size` 只能把它调小；`0` 表示使用默认 8192），帧上限 `MAX_FRAMES = 512`。
- 函数返回后，`OP_ALLOCA` 在 `mem_mark` 之后的线性内存会回收；调用者分配的内存保留。

### 3.4 线性内存与 globals

VM 默认有 1 MiB 线性内存（`mem`，`ci_vm_config.memory_size=0` 选默认值，上限 16 MiB），`mem_top` 是 bump pointer：

- `OP_ADDR_CONST offset` 压入 `&mem[offset]` 的**宿主地址**（不是文件偏移）。
- `OP_SET_MEM_TOP size` 将 `mem_top` 设为 size。
- `OP_ALLOCA size` 在 8 字节对齐的 `mem_top` 分配并清零，压入宿主地址。
- FFI 宽/多 loc 返回值使用同一 bump allocator 分配（16 字节对齐）；块在帧返回前不会回收，长循环可能耗尽线性内存。
- `OP_ALLOCA_DYN` 从栈弹 size，做同样的动态分配（VLA）。
- 全局数据没有独立 section；编译器在 `main` 开头生成：
  1. `SET_MEM_TOP <global_data_size>`
  2. 对每个 8 字节 chunk 生成 `LOAD_CONST chunk; ADDR_CONST off; STORE_MEM size`
  3. 对 global 指针/函数指针重定位生成 `ADDR_CONST/FUNC_ADDR; ADDR_CONST field; STORE_MEM ptr_size`
- 因此 `.cib` 中的全局地址是**运行期 VM 内存地址**，不是可重定位文件地址；同一包应在兼容的运行时进程中执行。
- 每次 `ci_vm_run*` 都会先清零线性内存/值栈/帧/`setjmp` 目标。`main` 开头的全局安装
  代码会随每次运行重新执行，因此重复运行 `main` 会重新安装 globals；从非 `main` 入口
  运行不会执行该安装代码，只能看到清零后的全局区域（已知限制）。

## 4. Opcode

> **单一来源**：opcode 编号的权威定义是 `compiler/src/opcodes.zig`（编译器实际发出的字节）与 `runtime/src/vm.zig` 顶部的 `OP_*` 常量及 `run` 中的 dispatch（运行时实际解码的字节）。下表已按当前代码逐项核对：它覆盖 `compiler/src/opcodes.zig` 中 0x01–0xA4 的全部常量，唯一例外是 `POP`（0x15）/`SWAP`（0x16）——它们只在运行时有解码实现，当前编译器不发出。若今后新增/删除 opcode，必须同步此表；无法保证同步时应把本节改为只链接源码，不要保留过期快照。

栈效果按“先压入的值在下面”描述，例如 `a, b -> result` 表示先压 `a`、再压 `b`，opcode 弹 `b` 再弹 `a`。

| code | mnemonic | 操作数 | 栈效果/说明 |
| --- | --- | --- | --- |
| 0x01 | `RET` | — | `a ->`；返回值 a |
| 0x02 | `RET_VOID` | — | 返回 0 |
| 0x10 | `LOAD_CONST_I64` | i64 (8B) | 压入常量 |
| 0x11 | `ADD` | — | `a,b -> a+b` |
| 0x12 | `SUB` | — | `a,b -> a-b` |
| 0x13 | `MUL` | — | `a,b -> a*b` |
| 0x14 | `DUP` | — | `a -> a,a` |
| 0x15 | `POP` | — | `a ->` |
| 0x16 | `SWAP` | — | `a,b -> b,a` |
| 0x17 | `XOR` | — | `a,b -> a^b` |
| 0x18 | `DIV_S` | — | 有符号整除 |
| 0x19 | `DIV_U` | — | 无符号整除 |
| 0x1A | `REM_S` | — | 有符号取余 |
| 0x1B | `REM_U` | — | 无符号取余 |
| 0x1C | `AND` | — | `a,b -> a&b` |
| 0x1D | `OR` | — | `a,b -> a|b` |
| 0x1E | `SHL` | — | `a,b -> a<<b` |
| 0x1F | `SHR_S` | — | 算术右移 |
| 0x20 | `LOAD_LOCAL` | u16 | 压入局部槽 |
| 0x21 | `STORE_LOCAL` | u16 | 弹出并写局部槽 |
| 0x24 | `SHR_U` | — | 逻辑右移 |
| 0x25 | `FPTOSI` | — | f64 bits -> i64 |
| 0x26 | `SITOFP` | — | i64 -> f64 bits |
| 0x27 | `FADD` | — | f64 |
| 0x28 | `FSUB` | — | f64 |
| 0x29 | `FMUL` | — | f64 |
| 0x2A | `FDIV` | — | f64 |
| 0x2B | `FCMP` | pred u8 | `a,b -> 0/1`，f64 谓词 |
| 0x2C | `FADD32` | — | f32 |
| 0x2D | `FSUB32` | — | f32 |
| 0x2E | `FMUL32` | — | f32 |
| 0x2F | `FDIV32` | — | f32 |
| 0x30 | `JMP` | u32 target | 绝对跳到函数 code 内 target |
| 0x31 | `JZ` | u32 target | 弹条件；为 0 跳转 |
| 0x32 | `JNZ` | u32 target | 弹条件；非 0 跳转 |
| 0x33 | `CMP_EQ` | — | `a,b -> 0/1` |
| 0x34 | `CMP_LT` | — | 有符号 `<` |
| 0x35 | `CMP_LT_U` | — | 无符号 `<` |
| 0x38 | `FCMP32` | pred u8 | f32 比较 |
| 0x39 | `FPEXT` | — | f32 -> f64 bits |
| 0x3A | `FPTRUNC` | — | f64 -> f32 bits |
| 0x3B | `FPTOSI32` | — | f32 -> i64 |
| 0x3C | `SITOFP32` | — | i64 -> f32 bits |
| 0x40 | `CALL` | u16 func | 调用内部函数 |
| 0x41 | `FUNC_ADDR` | u16 func | 压入内部函数标签 `func+1`（0 表示 null） |
| 0x42 | `CALL_INDIRECT` | — | 弹函数标签，调用对应内部函数 |
| 0x60 | `ALLOCA` | u16 size | 线性内存分配，压地址 |
| 0x61 | `LOAD_MEM` | u8 size | `addr -> value`；size 1..8，<8 时符号扩展 |
| 0x62 | `STORE_MEM` | u8 size | `value,addr ->`；写 size 1..8 低字节 |
| 0x63 | `MEMCPY` | — | `dst,src,len ->`；重叠地址按 memmove 方向复制 |
| 0x64 | `MEMSET` | — | `dst,value,len ->` |
| 0x65 | `ADDR_CONST` | u32 offset | 压 `&mem[offset]` 宿主地址 |
| 0x66 | `SET_MEM_TOP` | u32 size | 设置 `mem_top` |
| 0x70 | `CALL_NATIVE` | u16 plan | 按计划调用原生函数 |
| 0x71 | `CALL_VARARG` | u16 plan | 按计划调用 varargs 原生函数 |
| 0x72 | `CREATE_CALLBACK` | u16 slot,u16 func,u16 plan | 注册自动静态 callback slot（绑定当前 VM，跨 run 复用），压 trampoline 地址 |
| 0x73 | `F80_CONST` | 10 bytes | x87 80-bit little-endian；压 f80 对象地址 |
| 0x74-0x77 | `F80_ADD/SUB/MUL/DIV` | — | `a,b -> result`（指针） |
| 0x78 | `F80_CMP` | pred u8 | f80 比较 |
| 0x79 | `F80_FROM_F64` | — | f64 bits -> f80 指针 |
| 0x7A | `F80_TO_F64` | — | f80 指针 -> f64 bits |
| 0x7B | `F80_FROM_I64` | — | i64 -> f80 指针 |
| 0x7C | `F80_TO_I64` | — | f80 指针 -> i64 |
| 0x7D | `F80_FROM_F32` | — | f32 bits -> f80 指针 |
| 0x7E | `F80_TO_F32` | — | f80 指针 -> f32 bits |
| 0x7F | `F80_NEG` | — | f80 取负 |
| 0x80 | `F128_CONST` | 16 bytes | IEEE 128-bit little-endian；压 f128 对象地址 |
| 0x81-0x84 | `F128_ADD/SUB/MUL/DIV` | — | f128 指针运算 |
| 0x85 | `F128_CMP` | pred u8 | f128 比较 |
| 0x86 | `F128_NEG` | — | f128 取负 |
| 0x87-0x8C | `F128_FROM_F64/TO_F64/FROM_I64/TO_I64/FROM_F32/TO_F32` | — | f128 转换 |
| 0x8D | `ALLOCA_DYN` | — | 弹 size，动态分配 VLA |
| 0x8E | `FPTOUI` | — | f64 -> u64 bits |
| 0x8F | `UITOFP` | — | u64 bits -> f64 |
| 0x90 | `FPTOUI32` | — | f32 -> u64 bits |
| 0x91 | `UITOFP32` | — | u64 bits -> f32 |
| 0x92-0x95 | `F80_TO_U64/FROM_U64/F128_TO_U64/FROM_U64` | — | long double 无符号转换 |
| 0x96 | `ADDR_EXTERN` | u16 import | 压入 CIPI data 符号地址 |
| 0x97 | `SETJMP` | u16 slot | 保存 VM 执行上下文，结果写 slot |
| 0x98 | `LONGJMP` | — | 恢复对应 jmp_buf 的上下文 |
| 0x99 | `CALL_VARIADIC` | u16 func,u16 total | 调用内部可变参数函数，保留额外参数 |
| 0x9A | `VA_START` | — | 按目标 ABI 初始化 va_list，溢出参数放到 VM 内存 |
| 0x9B | `VA_COPY` | — | 复制目标 ABI 的 va_list |
| 0x9C | `CALL_INDIRECT_NATIVE` | u16 plan | 间接调用内部函数或原生 FFI 地址 |
| 0x9D | `STACKSAVE` | — | 压入当前 `mem_top` |
| 0x9E | `STACKRESTORE` | — | 恢复 `mem_top` |
| 0x9F | `ALLOCA_ALIGNED` | u16 size,u8 align | 对齐的静态 alloca |
| 0xA0 | `ALLOCA_DYN_ALIGN` | u8 align | 对齐的动态 alloca（size 在栈顶） |
| 0xA1 | `CALL_VARIADIC_TYPED` | u16 func,u16 total,per-extra code/size | 内部 varargs 调用，携带 overflow 布局描述 |
| 0xA2 | `FPCLASS` | u8 kind | `value,mask -> 0/1`；LLVM `is.fpclass`，kind 选择分类、mask 是测试位图 |
| 0xA3 | `CALLBACK_ACQUIRE` | u16 plan,u16 func | 为 `func`/`plan` 分配一个进程级 trampoline 槽并压入地址；池耗尽时压入 NULL |
| 0xA4 | `CALLBACK_RELEASE` | — | `ptr -> status`；释放该 VM 拥有的槽，返回 0/`CI_E_BUSY`/负值 |

### 4.1 浮点谓词

`FCMP`/`FCMP32`/`F80_CMP`/`F128_CMP` 的 pred 字节：

| value | 谓词 |
| --- | --- |
| 0 | `oeq`（有序等于） |
| 1 | `one`（有序不等） |
| 2 | `olt` |
| 3 | `ole` |
| 4 | `ogt` |
| 5 | `oge` |
| 6 | `ord` |
| 7 | `uno` |

### 4.2 f80/f128 值表示

f80/f128 **不是** 8 字节栈值本身：

- `*_CONST` 在 VM 线性内存分配一个 16B 对象，并把**对象地址**压栈。
- 算术/比较 opcode 读取这些对象地址，结果再分配一个新对象并压地址。
- `store/load` 对 f80/f128 使用 `MEMCPY`/指针别名语义；全局/内存布局由 C 类型大小决定。
- FFI 返回 `st0`/多寄存器聚合时，`invokeFfi` 会从调用方 VM 线性内存分配返回块、复制结果并压入地址；返回块存活到当前帧返回，不再共享固定缓冲区。

### 4.3 显式 callback acquire/release

`CALLBACK_ACQUIRE`/`CALLBACK_RELEASE` 服务于 `ci_callback_acquire(fn)`/
`ci_callback_release(fn)` 宏。`cinterp-cc` 会把内嵌的
`compiler/src/data/cinterp_callbacks.h` 写入临时目录并通过 `zig cc -include` 强制
包含，因此 CIB 源码不需要 `#include` 或 include path。编译器把
`__ci_callback_acquire`/`__ci_callback_release` 当作内部 builtin，不生成 CIPI import。

- `CALLBACK_ACQUIRE u16 plan,u16 func`：校验 `func`/`plan` 及其 ABI 后，从进程级
  **256 个静态 trampoline 槽**中取一个空闲槽，绑定到当前 VM，压入 trampoline 地址；
  池耗尽时压入 NULL。acquire 的参数必须是直接函数引用（可带 cast），运行期函数指针
  变量会在编译期被拒绝。
- `CALLBACK_RELEASE`：弹出 acquire 返回的地址，释放当前 VM 拥有的槽并压入状态：
  `0` 成功；`CI_E_BUSY` 表示该 callback 仍在 dispatch，槽未释放；负值/`CI_E_INVALID_ARGUMENT`
  表示该 VM 不拥有此指针或已经释放。
- 释放后的槽回到可复用集合；释放后的旧指针不得再次调用（可能被新 acquire 复用并进入
  另一个 VM，属于调用方违约）。没有动态可执行内存，也没有代际检查。
- VM 销毁或计划重载会退休所有**仍未释放**的槽（自动和显式），已释放的槽不受影响。
  自动 `OP_CREATE_CALLBACK` 槽在 VM 生命周期内保留并跨重复运行复用，不会每次运行消耗
  一个新槽。
- `ci_callback_pool_stats(total, live, free_slots, retired)` 查询池状态；
  `ci_vm_callback_error(vm)` 记录被跳过的 dispatch（例如另一线程正在运行该 VM 时的
  `CI_E_BUSY`）。详见 [`multi-cib.md`](multi-cib.md)。

## 5. CIPL 计划表

CIPL v3 是紧凑计划表：没有 magic/version/reserved 头，计划数为 0 时整个 section 省略。

### 5.1 头部

```
offset size field
0      1    abi_id
1      2    plan_count (u16 LE)
```

### 5.2 计划记录（重复 `plan_count` 次）

```
size  field
1     name_len
N     name bytes（ASCII/UTF-8，有效上限 128）
1     args_count
1     ret_count
2     stack_size
1     flags：bit0=sret，bits1..4=sse_count，bits5..6=conv
2     ret_size
```

随后 `args_count` 个参数记录：

```
1     flags：低 4 位=loc_count，bit7=is_struct
2     size
...   loc_count × Loc
```

最后 `ret_count` 个返回 `Loc`。

`Loc`（7 B）：

```
1     kind
2     index
2     size
2     offset
```

`kind` 取值：

| byte | kind | 含义 |
| --- | --- | --- |
| 0 | `gpr` | 整数/指针参数寄存器槽 |
| 1 | `xmm` | SSE/vector 参数槽（AArch64 也用于 vec） |
| 2 | `stack` | 栈参数槽 |
| 3 | `sret` | 隐藏 sret 指针槽 |
| 4 | `rax` | 整数返回寄存器 |
| 5 | `rdx` | 第二整数返回寄存器 |
| 6 | `xmm0` | 第一 SSE/vector 返回槽 |
| 7 | `xmm1` | 第二 SSE/vector 返回槽 |
| 8 | `st0` | x87 ST0（long double） |
| 9 | `xmm2` | 第三 HFA 返回槽 |
| 10 | `xmm3` | 第四 HFA 返回槽 |

### 5.3 字段语义

- `name`：外部符号名。callback 计划的名称是 `callback:<vm-function>`，没有原生符号。
- `args_count`：实际传入的参数个数；上限 64。
- `loc_count`：一个参数可拆成多个位置（HFA 的 xmm0/xmm1…）；上限 8。
- `size`：参数的字节宽度。
- `offset`：参数在 marshal arg block 中的偏移；`stack` loc 的 `index` 是栈参数缓冲区内的字节偏移；返回 loc 的 offset 是返回缓冲区偏移。
- `is_struct=1`：参数的 VM 值是指向结构体字节的指针；运行时从该地址拷贝 `size` 字节到 arg block。
- `sret=1`：隐藏返回指针；`sret` loc 指示隐藏指针槽。
- `sse_count`：SysV `%al` / Win64 varargs 的向量计数。
- `conv`：Win32 调用约定；0=cdecl，1=stdcall，2=fastcall，3=thiscall；其他 ABI 忽略。
- `ret_size`：sret/聚合返回缓冲区字节数。
- `ret_count > 0`：普通返回 loc（`ret_count ≤ 8`）；多 loc、`st0` 或单 loc `size > 8` 时，运行时会把返回块复制到按调用分配的 VM 临时块并压入其地址。
- `stack_size`：计划需要的栈参数字节数；运行时校验不超过 4096。

### 5.4 ABI id 与 LocKind 的对应

| id | ABI | frame/engine |
| --- | --- | --- |
| 1 | SysV x86-64 | `call_x86_64_sysv.S` |
| 2 | Win64 x86-64 | `call_x86_64_win64.S` |
| 3 | Win32 x86 | `call_x86_win32.S` |
| 4 | AArch64 AAPCS64 | `call_arm64_aapcs.S` |

计划表只描述位置，不描述实际寄存器编号映射；具体 `gpr[0]`/`xmm[0]` 由目标 ABI 的 `platform.zig` frame 和固定汇编引擎映射。

## 6. 完整示例：`hello.cib`

运行 `./build/cinterp-cc compile examples/basics/hello.c -o build/hello.cib` 后（CIPKG v3），下面是一次实际构建的 `xxd -g1` 注解；该包共 101B：module 83B、plans 0B、imports 0B，CIVM `code_len` 为 60B：

```
43 49 50 4b 47        CIPKG
03                    version 3
53 00 00 00           module_len = 83
00 00 00 00           plan_len = 0
00 00 00 00           import_len = 0

43 49 56 4d           CIVM
01                    version 1
01                    arch 1
01 00                 func_count = 1
00 00                 reserved
04 6d 61 69 6e        name_len=4, "main"
00 00                 param_count = 0
01 00                 local_count = 1
3c 00 00 00           code_len = 60
60 04 00              ALLOCA 4
21 00 00              STORE_LOCAL 0
10 00 00 00 00 00 00 00 00   LOAD_CONST_I64 0
20 00 00              LOAD_LOCAL 0
62 04                 STORE_MEM 4
10 2a 00 00 00 00 00 00 00   LOAD_CONST_I64 42
10 ff ff ff ff 00 00 00 00   LOAD_CONST_I64 0xffffffff（32 位宽度）
1c                    AND
10 20 00 00 00 00 00 00 00   LOAD_CONST_I64 32
1e                    SHL
10 20 00 00 00 00 00 00 00   LOAD_CONST_I64 32
1f                    SHR_S
01                    RET
```

该包没有计划和外部调用，所以 CIPL/CIPI 两个 section 都省略。带自动链接的包会在 section 末尾追加 CIPI；可用 `--dump-imports` 查看，例如：

```
>>> cinterp-run --dump-target --dump-imports --load-only build/ffi_printf.cib
target: unchecked (host)
import[plan 0] printf: libc.so.6:printf
```

## 7. 检查与验证

```bash
# 查看十六进制
xxd -g1 build/hello.cib

# 查看编译器生成函数/计划/import 摘要
./build/cinterp-cc compile examples/ffi/ffi_printf.c -o build/printf.cib --dump --dump-imports

# 只加载/校验，不执行；查看 import 元数据
./runtime/zig-out/bin/cinterp-run --dump-target --dump-imports --load-only build/printf.cib

# 指定入口
./runtime/zig-out/bin/cinterp-run build/hello.cib main

# 解析 CIB：头信息 + CIVM 反汇编
./scripts/cib_dump.py build/hello.cib

# 只打印头信息 / 只反汇编
./scripts/cib_dump.py --headers build/ffi_callback.cib
./scripts/cib_dump.py --asm build/ffi_callback.cib
```

`cib_dump.py` 支持 CIPKG v3、CIVM、紧凑 CIPL 和 CIPI；会打印 section
偏移/长度、函数与计划表、import provider，以及每个函数的 opcode 反汇编。

运行时失败始终返回稳定的 `CI_E_*` 类别；Debug 构建把具体错误名（`BadPackage`、`BadPackageMagic`、`BadAbi`、`BadPlan` 等）写入 `ci_vm_last_error`/`ci_process_last_error` 并输出，Release 构建返回空字符串，只保留状态码。CLI 在 Release 下输出 `load failed: error <code>` / `run failed: error <code>`。

### 7.1 C ABI 错误码

`ci_vm_load_module`/`ci_vm_load_plans`/`ci_vm_load_package`/`ci_vm_load_library`/`ci_vm_run`/`ci_vm_run_args` 返回 `CI_OK`（0）或下列稳定负值。`ci_vm_destroy_ex`、`ci_process_load_package`、`ci_process_unload_package` 和 `ci_process_last_error_code` 也使用同一套 `CI_E_*` 类别。**返回值本身就是类别**：失败时返回对应的 `CI_E_*`；只有 `errorCode` 无法归类的错误才返回 `CI_ERROR`（-1）。`ci_vm_last_error_code` 返回同一类别；`ci_vm_last_error` 仅在 Debug 构建返回具体错误名（如 `BadPackageMagic`），Release 构建返回空字符串。成功的调用（以及 `ci_vm_clear_error`）清空错误文本与类别；`ci_vm_result` 返回上次成功运行的 `main` 返回值，不是状态码。

| 值 | 名称 | 覆盖的错误名 |
| ---: | --- | --- |
| -1 | `CI_ERROR` | `errorCode` 的兜底分支：未归类的错误，正常路径不应出现 |
| -2 | `CI_E_INVALID_ARGUMENT` | `InvalidArgument`、`TooManyArgs` |
| -3 | `CI_E_OUT_OF_MEMORY` | `OutOfMemory` |
| -4 | `CI_E_BAD_PACKAGE` | `BadPackage`、`BadPackageMagic`、`BadPackageVersion`、`BadPackageSize`、`BadMagic`、`BadVersion`、`BadArch`、`BadModule`、`BadLocals`、`TooManyFunctions`、`NameTooLong`、`ModuleTooLarge`、`Truncated`、`TrailingBytes`、`BadImportMagic`、`BadImportVersion`、`TooManyImports`、`TooManyProviders` |
| -5 | `CI_E_TARGET` | `UnsupportedLibc`（musl 运行时） |
| -6 | `CI_E_PLANS` | `NoPlans`、`BadAbi`、`BadPlan`、`BadImportPlan`、`BadImportProvider`、`ImportArchMismatch`、`ImportUnavailable`、`TooManyPlans`、`TooManyLocs`、`BadLocKind` |
| -7 | `CI_E_LINK` | `SymbolNotFound`、`LibraryNotFound`、`SymbolTooLong`、`PathTooLong`、`TooManyLibraries`、`TooManyNativeTargets` |
| -8 | `CI_E_ENTRY` | `EntryNotFound` |
| -9 | `CI_E_RESOURCE` | `StackOverflow`、`FrameOverflow`、`ReturnTooLarge`、`ProcessFull`（超过 64 个进程级 VM） |
| -10 | `CI_E_RUNTIME` | `BadAddress`、`BadOpcode`、`BadFunction`、`BadArgCount`、`BadJump`、`BadCallbackSlot`、`UnsupportedCallback`、`TooManyCallbacks`、`DivisionByZero`、`BadLocal`、`BadLongjmp`、`TooManyJumps`、`TruncatedCode`、`StackUnderflow`、`BadMemorySize`、`NullStruct`、`UnsupportedVaList`、`NestedRun`（同一线程嵌套运行） |
| -11 | `CI_E_DESTROYED` | `VmDestroyed`（VM 正在销毁时注册/执行 callback） |
| -12 | `CI_E_BUSY` | `Busy`（另一线程正在执行该 VM；loader/`ci_vm_destroy_ex(CI_DESTROY_TRY)` 遇到 busy） |

该表与 `runtime/include/cinterp.h` 的枚举及 `runtime/src/vm.zig` 的 `errorCode`（当前 `CI_ABI_VERSION = 2`）一一对应；新增类别只能追加新的负值，不得复用既有数值。

## 8. 限制与兼容性

- `CIVM` 当前 v1；`CIPKG` 当前 v3；`CIPL` 当前 v3；`CIPI` 当前 v1。
- `CIVM` 函数数上限 512、函数名有效上限 128、模块上限 2097152 字节；槽栈默认/上限 8192（`ci_vm_config.stack_size` 只能下调，`0` 表示默认 8192）、帧 512、线性内存默认 1 MiB（`memory_size=0`；上限 16 MiB，32 字节对齐）。
- 每个进程最多 64 个 VM（`MAX_PROCESS_VMS`）；第 65 个 `ci_process_load_package` 返回 `ProcessFull`（`CI_E_RESOURCE`）。每个 VM 默认约 2 MiB（VM 记录 + 8192 槽值栈 + 1 MiB 线性内存）。
- callback trampoline 是进程级固定的 256 个静态槽（不生成可执行内存）：自动 `OP_CREATE_CALLBACK` 槽在 VM 生命周期内保留、跨重复运行复用，VM 销毁/计划重载后退休；显式 `OP_CALLBACK_ACQUIRE` 槽在 `OP_CALLBACK_RELEASE` 后回到可复用集合，未释放的显式槽在 VM 销毁/重载时退休。释放后的旧指针不得再次调用。
- `CIPL` 计划上限 1024、每计划参数 64、每计划返回 loc 8、每参数 loc 8、名称有效上限 128；FFI arg/stack/ret 缓冲区各 4096 字节（`stack_size` 也受 4096 限制）。
- 包不携带目标声明；运行时只根据 CIPL ABI id 和当前平台选择引擎，调用方必须保证包与运行时目标匹配。musl 运行时在 load 阶段显式返回 `UnsupportedLibc`，不会回退到 Linux glibc。
- CIPI 上限 512 entry、每 entry 8 provider、名称/符号 64 字节、版本 32 字节；自动 provider 只允许库名，不允许 CIB 携带任意路径。
- `CIVM` 函数名、CIPL 计划名、CIPI 名称都按字节计数，不是 Unicode 字符数；超限在解析阶段返回 `NameTooLong`。
- 不包含校验和/签名；不可信 `.cib` 应在 OS 沙箱中运行。运行时不提供进程内沙箱或 Safe 模式。
- 运行时共享宿主 libc/stdio；`malloc` 的宿主堆分配跨 run 累积，`dlopen`/`LoadLibrary` 句柄永不卸载，`atexit`/`signal` 是进程全局状态。非 `main` 入口不会执行全局安装代码。
- 自动链接覆盖函数符号和基础 external data（`stdout`/`stderr`/`_environ` 等，`CIPI.kind=data` + `ADDR_EXTERN`）；Windows UCRT 的 `_errno`/`__acrt_iob_func`/`__p__environ` 是函数计划，不是 data provider。向量、复杂聚合全局初始化仍不在范围内。`CIPKG` 本身不携带 `.so`/`.dll` 二进制。
