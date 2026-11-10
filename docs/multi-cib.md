# 单进程多 CIB、重复运行与每 VM 线程

本文描述 cinterp 的多 CIB 进程模型、每 VM 执行权、重复运行的全新镜像语义，
以及 CIB 内显式 callback acquire/release。多包/重复/并行通过 C API 使用；CLI
只支持 `<package.cib> [-- ARG...]` 的单包单次运行。C 接口的完整声明见
`runtime/include/cinterp.h`；包格式和操作码见 [`cib.md`](cib.md)，单 VM 嵌入基础见
[`embedding.md`](embedding.md)。

## 1. 进程/VM 模型

- 一个 `ci_vm` 同时只持有一个 CIB。`ci_vm_load_package` 仍是**事务性替换**：失败
  不改变已加载的包，成功则整体替换当前包；不会把第二个包附加到同一个 VM。
- 一个进程可以通过 `ci_process_*` 注册表持有多个 VM。每个 VM 有独立的线性内存、
  全局数据、值栈、帧和 FFI 计划存储，因此一个 CIB 的全局/线性内存状态不会进入另一个
  CIB（宿主堆、libc 和环境仍是进程共享的，见第 7 节）。
- `ci_process_load_package` 每次创建一个新 VM，不复用已加载的 VM。进程内 VM 上限是
  `MAX_PROCESS_VMS = 64`；第 65 个加载返回 `ProcessFull`（`CI_E_RESOURCE`）。
- 同一 CIB 可以在其 VM 上通过 `ci_vm_run*` 重复运行，不需要重新加载包。每次运行都是
  **全新镜像**：线性内存清零、值栈/帧重置、`setjmp` 目标和 native target 重新登记，
  `main` 开头的全局安装代码会重新执行（详见第 4 节）。
- 每个 VM 默认约 2 MiB：约 0.9 MiB 的 VM 记录、8192 槽值栈（64 KiB）和 1 MiB 线性
  内存。小包可以通过 `ci_vm_config.memory_size` 调低线性内存。
- `ci_vm_load_package` 和 `ci_process_load_package` 都会复制包字节，调用方可以在
  成功后释放自己的缓冲区。
- 不支持 CIB-to-CIB 链接、包间导出或跨包函数调用；跨包复用请合并源码后重新编译，
  或由宿主通过 `ci_vm_load_library` 加载普通共享库。

## 2. 进程 API

```c
typedef struct ci_process ci_process;

ci_process *ci_process_create(const ci_vm_config *vm_config);
void ci_process_destroy(ci_process *process);

int ci_process_load_package(ci_process *process,
                            const uint8_t *data, size_t size,
                            ci_vm **out);
int ci_process_unload_package(ci_process *process, ci_vm *vm);

const char *ci_process_last_error(const ci_process *process);
int ci_process_last_error_code(const ci_process *process);
```

- `ci_process_create(NULL)` 使用默认配置。传入 `ci_vm_config` 时按 `struct_size`
  规则校验：`struct_size` 至少覆盖到 `stack_size`，`flags` 必须为 0，
  `memory_size` 为 0 时使用默认 1 MiB；配置非法时返回 NULL。`ci_process` 只拥有
  VM 生命周期，运行策略（哪个 VM、运行几次、在哪个线程）由宿主决定。
- `ci_process_load_package` 成功时把**借出的** `ci_vm *` 写入 `*out`。该句柄不能
  用 `ci_vm_destroy` 销毁，请使用 `ci_process_unload_package`。加载失败时 `*out`
  置 NULL，注册表保持不变，错误记录在 process 上。
- `ci_process_unload_package` 只能卸载本进程注册的空闲 VM；运行中的 VM 返回
  `CI_E_BUSY` 并保持注册，不属于该进程的句柄返回 `CI_E_INVALID_ARGUMENT`。
- `ci_process_destroy` 销毁所有空闲 VM 并释放注册表。若仍有 VM 在其他线程运行，
  它**不等待**：busy VM 与注册表保持存活，`ci_process_last_error` 报告
  `CI_E_BUSY`。宿主必须先 join 运行线程，然后再次调用 `ci_process_destroy`。
  返回 `CI_E_BUSY` 后可以重试；一旦销毁成功，句柄不可再用。
- 加载错误记录在 process 上（`ci_process_last_error*`），运行错误仍记录在对应 VM
  上（`ci_vm_last_error*`）。
- `CI_E_BUSY = -12` 是追加到 C ABI 2 的新状态码；既有数值不变，因此不需要提升
  `CI_ABI_VERSION`。

### 2.1 加载/运行/卸载示例

```c
#include <cinterp.h>
#include <stdio.h>

/* hello_bytes/hello_size、math_bytes/math_size 是构建期生成的 .cib 内容。 */
static int load_run_unload(ci_process *process,
                           const uint8_t *bytes, size_t size) {
    ci_vm *vm = NULL;
    int rc = ci_process_load_package(process, bytes, size, &vm);
    if (rc != CI_OK) {
        fprintf(stderr, "load: %s (%d)\n",
                ci_process_last_error(process),
                ci_process_last_error_code(process));
        return 1;
    }

    rc = ci_vm_run(vm, "main");
    if (rc != CI_OK) {
        fprintf(stderr, "run: %s (%d)\n",
                ci_vm_last_error(vm), ci_vm_last_error_code(vm));
        ci_process_unload_package(process, vm);
        return 1;
    }
    printf("result: %lld\n", (long long)ci_vm_result(vm));

    rc = ci_process_unload_package(process, vm);
    if (rc != CI_OK) {
        fprintf(stderr, "unload: %s (%d)\n",
                ci_process_last_error(process),
                ci_process_last_error_code(process));
        return 1;
    }
    return 0;
}

int main(void) {
    ci_process *process = ci_process_create(NULL);
    if (!process) return 1;

    int rc = load_run_unload(process, hello_bytes, hello_size);
    if (rc == 0) rc = load_run_unload(process, math_bytes, math_size);

    ci_process_destroy(process);
    return rc;
}
```

## 3. 线程模型

每个 VM 同一时间只允许一个执行上下文，但不同 VM 可以同时在不同线程上运行。

| 调用 | 另一线程正在运行该 VM | 当前线程已在该 VM 的运行中（嵌套） |
| --- | --- | --- |
| `ci_vm_run` / `ci_vm_run_args` | `CI_E_BUSY` | `CI_E_RUNTIME` |
| `ci_vm_load_module` / `ci_vm_load_package` / `ci_vm_load_library` | `CI_E_BUSY` | `CI_E_BUSY` |
| `ci_vm_load_plans`（v4 不支持裸计划表） | `CI_E_BUSY` | `CI_E_BUSY`；空闲时返回 `CI_E_PLANS`，请使用 `ci_vm_load_package` |
| `ci_vm_destroy` | 等待运行结束，然后释放 | 延迟到最外层运行返回后释放 |
| `ci_vm_destroy_ex(vm, CI_DESTROY_TRY)` | `CI_E_BUSY`，VM 不变 | 成功并延迟释放 |
| `ci_process_unload_package` | `CI_E_BUSY` | `CI_E_BUSY` |
| `ci_process_destroy` | `CI_E_BUSY`（由 `last_error` 报告），注册表保持 | `CI_E_BUSY`，注册表保持 |

- `ci_vm_busy(vm)` 在任意线程正在执行该 VM 时返回 1，否则返回 0；可用于宿主自己
  的调度/关闭检查。
- 嵌套的 `ci_vm_run` 被拒绝为 `CI_E_RUNTIME`，因为它会清空外层运行的值栈和线性
  内存。callback 已经运行在 VM 内，不应再次调用 `ci_vm_run`。
- 每个 VM 有独立的执行锁；不同 VM 之间不会互相阻塞。进程级只有 callback 槽位锁和
  `ci_process` 注册表锁。
- `ci_vm_destroy` 会等待另一线程的运行结束。由正在运行的线程调用时（例如在 callback
  里）无法等待自己，因此标记为延迟销毁，由最外层运行在返回途中释放；此后句柄失效。
- 宿主关闭顺序：先停止派发新运行，join 所有运行线程，再用
  `ci_process_unload_package` / `ci_process_destroy` 释放。不要在运行线程未 join 时
  忙等 `ci_process_destroy` 成功。

### 3.1 pthread 风格的并行示例

每个 VM 只在自己的线程上运行；C API 宿主负责把同一 VM 固定到单一线程。

```c
#define _POSIX_C_SOURCE 200809L
#include <cinterp.h>
#include <pthread.h>
#include <stdio.h>

typedef struct {
    ci_vm *vm;
    int runs;
    int rc;
} vm_job;

static void *run_vm(void *arg) {
    vm_job *job = (vm_job *)arg;
    for (int i = 0; i < job->runs; i++) {
        job->rc = ci_vm_run(job->vm, "main");
        if (job->rc != CI_OK) return NULL;
        printf("%lld\n", (long long)ci_vm_result(job->vm));
    }
    return NULL;
}

int main(void) {
    ci_process *process = ci_process_create(NULL);
    if (!process) return 1;

    ci_vm *a = NULL, *b = NULL;
    /* a_bytes/a_size、b_bytes/b_size 是调用方读入的 .cib 内容。 */
    if (ci_process_load_package(process, a_bytes, a_size, &a) != CI_OK) return 1;
    if (ci_process_load_package(process, b_bytes, b_size, &b) != CI_OK) return 1;

    vm_job ja = { a, 3, CI_OK };
    vm_job jb = { b, 3, CI_OK };
    pthread_t ta, tb;
    pthread_create(&ta, NULL, run_vm, &ja);
    pthread_create(&tb, NULL, run_vm, &jb);
    pthread_join(ta, NULL);
    pthread_join(tb, NULL);

    if (ja.rc != CI_OK || jb.rc != CI_OK) return 1;
    ci_process_unload_package(process, a);
    ci_process_unload_package(process, b);
    ci_process_destroy(process);
    return 0;
}
```

同一个 VM 被两个线程同时 `ci_vm_run` 时，只有一个线程获得执行权，另一个线程得到
`CI_E_BUSY`，不会破坏正在运行的内存。`ci_vm_destroy_ex(vm, CI_DESTROY_TRY)` 提供
非阻塞的关闭尝试；`ci_vm_destroy(vm)`/`ci_vm_destroy_ex(vm, 0)` 则等待空闲。

## 4. 重复运行与全新镜像

`ci_vm_run`/`ci_vm_run_args` 每次进入时都会执行 `resetRunImage`：

- 清零值栈槽位、`sp`、`mem_top`、`arg_area_start`、`frame_count`；
- 清零整个线性内存；
- 清空 `setjmp` 目标表，避免上一次运行的 `longjmp` 命中已经结束的代码；
- 清空按 run 登记的 native target 列表（native plan 缓存保留，因为 plan 索引不变）；
- 重新构建 `argv`/`envp` 区域；`getEnvMap` 每次运行读取宿主环境，环境变量越大，
  可用线性内存越少。

全局数据的安装代码由编译器生成在 `main` 开头（`SET_MEM_TOP` + 全局镜像写入）。
因此重复运行 `main` 会重新安装全局变量。运行时只接受 `main` 入口别名；其他入口名
返回 `CI_E_ENTRY`。

`ci_vm_result(vm)` 返回**最后一次成功运行**的结果。运行失败不会覆盖它；未知入口
在重置镜像之前失败，也不会覆盖。失败后 VM 仍可继续运行。

```c
for (int i = 0; i < 300; i++) {
    if (ci_vm_run(vm, "main") != CI_OK) return 1;
    /* 每次都是全新镜像；ci_vm_result 仍是本次成功运行的结果 */
}
```

## 5. CLI

`cinterp-run` 只保留一个命令形态：

```text
cinterp-run <package.cib> [-- ARG...]
```

- 单包、单次运行；`--` 后的参数作为 C `argv[1..]`，包路径是 `argv[0]`。
- 没有多包、重复、并行、入口选择、仅加载、dump 或显式库参数。
- 多 VM、并行、重复运行和 `ci_vm_load_library` 通过 C API 使用，见第 2-4 节。
- 成功退出码 0，加载/运行失败 1，用法或 I/O 错误 2；C `main` 的返回值只通过
  `result:` 输出。

## 6. CIB 内显式 callback acquire/release

### 6.1 编译期注入的头文件

`cinterp-cc` 在调用 `zig cc` 时通过 `-include <temp>/cinterp_callbacks.h` 强制包含
内嵌头文件（`compiler/src/data/cinterp_callbacks.h`）。CIB 源码**不需要**写
`#include`，也不需要配置 include path：

```c
/* 不需要 #include；宏由 cinterp-cc 强制注入。 */
int cmp(const void *a, const void *b) {
    return *(const int *)a - *(const int *)b;
}

int main(void) {
    int a[5] = { 3, 1, 4, 2, 5 };
    int (*cb)(const void *, const void *) = ci_callback_acquire(&cmp);
    if (cb == 0) return 1;              /* 池耗尽 */
    qsort(a, 5, sizeof(int), cb);
    int status = ci_callback_release(cb);
    if (status != 0) return 2;
    return a[0];
}
```

`examples/ffi/ffi_callback_scope.c` 就是不写 `#include` 的完整示例。

### 6.2 宏与返回值

```c
ci_callback_fn cb = ci_callback_acquire(my_fn); /* 或 &my_fn */
int status = ci_callback_release(cb);
```

- `ci_callback_acquire(fn)` 只接受**直接函数引用**（可带 cast/`&`）。它返回该函数
  的 trampoline 地址；池耗尽时返回 NULL。传入运行期函数指针变量会在编译期报
  `ci_callback_acquire requires a direct function reference`。
- `ci_callback_release(ptr)` 接受 acquire 返回的指针：成功返回 `0`；callback 仍在
  执行中返回 `CI_E_BUSY`（这次释放未生效，等 dispatch 返回后重试）；指针不属于当前
  VM、已经释放或从未 acquire 时返回 `CI_E_INVALID_ARGUMENT`。
- 释放成功后该指针立即失效；trampoline 槽位可能被下一次 acquire 复用。**再次调用
  已释放的指针属于调用方违约**，可能进入另一个 VM 的 callback。静态 trampoline 不
  携带代际信息，运行时无法检测这种复用。
- 编译器把 `__ci_callback_acquire`/`__ci_callback_release` 识别为内部 builtin，
  不会为它们生成 CIPI import，也不要求运行时导出同名符号。

### 6.3 CIVM 操作码

| code | mnemonic | 操作数 | 栈效果/说明 |
| --- | --- | --- | --- |
| 0xA3 | `CALLBACK_ACQUIRE` | `u16 plan,u16 func` | 为 `func` 分配一个进程级 trampoline 槽并压入地址；池耗尽时压入 NULL |
| 0xA4 | `CALLBACK_RELEASE` | — | `ptr -> status`；释放该 VM 拥有的槽，返回 0/`CI_E_BUSY`/负值 |

这两个操作码由 `ci_callback_acquire`/`ci_callback_release` 宏展开后的 builtin 调用
生成；自动的 `OP_CREATE_CALLBACK`（例如把 `@cb` 直接传给原生函数）保持不变。

### 6.4 槽位生命周期

callback trampoline 是进程级固定的 **256 个静态槽**，不生成动态可执行内存。槽位有
两种生命周期：

- **自动槽**（`OP_CREATE_CALLBACK`）：绑定到所属 VM，跨重复运行一直保留，直到 VM
  销毁或计划重载时永久退休。相同编译期槽位在重复运行中复用，不会每次运行消耗一个
  新槽。
- **显式槽**（`OP_CALLBACK_ACQUIRE`/`OP_CALLBACK_RELEASE`）：每次 acquire 从空闲
  集合取一个槽，release 成功后清空 owner/entry 并放回可复用集合。未 release 的显式
  槽在 VM 销毁或计划重载时退休（不会泄漏给下一个 VM）；已 release 的槽不受影响。
- 释放正在 dispatch 的槽返回 `CI_E_BUSY`，不会等待；dispatch 结束后重试即可。
- VM 销毁/计划重载只退休**仍归该 VM 所有**的槽；其他 VM 的槽和已释放的槽不受影响。

诊断接口：

```c
uint32_t total, live, free_slots, retired;
ci_callback_pool_stats(&total, &live, &free_slots, &retired);
/* total 恒为 256；free_slots 是可被 acquire 的槽数 */
```

`ci_vm_callback_error(vm)` 返回该 VM 上一次失败 callback dispatch 的 `CI_E_*` 类别
（没有则 0），`ci_vm_clear_error(vm)` 会同时清除该记录。

### 6.5 callback 的线程规则

- 当前线程就是该 VM 的运行者：callback 直接重入 `runCallback`，不展开外层帧。
- VM 空闲：dispatch **尝试**取得执行权，执行完释放；并发的 `ci_vm_run` 可能先取得，
  此时 callback 仍走下面的 skip 路径。
- VM 正被另一线程运行：**fail-fast**，callback 被跳过、不排队；非 sret 返回值写为零，
  sret 缓冲区保持原样，并在 `ci_vm_callback_error` 记录 `CI_E_BUSY`。这里不能阻塞等待，
  否则可能与正在等待该 callback 的运行线程死锁。
- VM 正在销毁：跳过；通常记录 `CI_E_DESTROYED`（销毁快路径可能只返回零值）。
- `ci_vm_callback_error` 是独立、sticky 的错误通道；读取不会清除，只有
  `ci_vm_clear_error` 清除。

原生库在后台线程异步调用 callback 时，应保证 VM 处于空闲状态，或在 VM 自己的运行
线程上同步调用；运行中的 VM 不会为外部线程排队 callback。`libc-test/pthread_tsd`
因这一策略显式 skip。

## 7. 限制与已知边界

- **宿主堆跨 run 累积**：CIB 调用 `malloc` 等分配的是宿主进程堆；重复运行不会回收
  上一次运行的宿主分配。VM 线性内存本身每次清零。
- **原生库句柄不卸载**：`ci_vm_load_library`/CIPI provider 的 `dlopen`/`LoadLibrary` 句柄没有
  `dlclose`/`FreeLibrary`，会一直保持映射到进程退出。
- **`atexit`/`signal` 是进程全局**：多个 VM/重复运行共享这些处理函数；重复运行会
  累积/覆盖注册，且 CLI 为让 `atexit` 执行会保持 VM 到 libc 退出。
- **入口名称**：运行时只接受 `main` 别名（CIVM `entry_func_index`）；其他名称返回
  `CI_E_ENTRY`。
- **不支持 CIB-to-CIB 链接**：没有包间导出/依赖或跨包函数调用。
- **没有进程内沙箱**：运行时执行可信构建产物；不可信 CIB 应在操作系统沙箱/容器中
  运行。
- **共享 libc/stdio**：同进程的所有 VM 共享宿主的 C 运行时、`stdout`/`stderr`、
  环境变量和信号处理，无法按 VM 隔离。
- **callback 池是进程级的**：固定 256 个静态槽，所有 VM 共享；显式 release 可以
  复用，自动槽在 VM 销毁/重载前一直占用。
- **VM 数量**：每个进程最多 64 个 VM（`MAX_PROCESS_VMS`），每个 VM 默认约 2 MiB；
  大量 VM 会线性增加常驻内存。

## 8. 快速验证

```bash
# 单包 + C argv
./runtime/zig-out/bin/cinterp-run build/hello.cib
./runtime/zig-out/bin/cinterp-run build/capi_argv.cib -- x 7
```

多 VM、重复运行和 support library 由 `runtime/tests/capi_multi.c` 及
`ci_vm_load_library` 覆盖。


`runtime/tests/capi_multi.c` 是覆盖进程注册表、每 VM 线程、busy 语义和
`ci_process_destroy` 重试的 C API 回归测试。
