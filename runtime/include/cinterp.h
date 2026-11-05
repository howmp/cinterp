#ifndef CINTERP_H
#define CINTERP_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * cinterp embedding API, ABI 2.
 *
 * The runtime executes a precompiled CIB package produced by cinterp-cc at
 * build time. It does not need clang or Python at runtime.
 *
 * Ownership and threading
 * -----------------------
 * A VM owns exactly one package at a time. A process may hold any number of
 * VMs (see ci_process_*), each with its own linear memory, globals and plan
 * store, and different VMs may run concurrently on different threads.
 *
 * A single VM may only be executed by one thread at a time:
 *   - ci_vm_run/ci_vm_run_args from a second thread return CI_E_BUSY;
 *   - re-entering ci_vm_run/ci_vm_run_args on the same thread (for example
 *     from a callback) returns CI_E_RUNTIME, because the outer run's image
 *     would be discarded;
 *   - ci_vm_load_module/load_plans/load_package/load_library return CI_E_BUSY
 *     while the VM executes, so a run can never lose its module, plans or
 *     resolved plan cache;
 *   - ci_vm_busy reports whether any thread is executing the VM.
 *
 * Callbacks that native code invokes follow the same rule: on the thread that
 * already runs the VM they re-enter it, on an idle VM the dispatch itself takes
 * the execution right for its duration, and while another thread runs the VM
 * the callback is skipped instead of waiting (see ci_vm_callback_error below).
 * Callbacks must not be treated as a way to run a busy VM: waiting there could
 * deadlock with the thread that is running it.
 *
 * Every run starts from a fresh image: the value stack, linear memory and the
 * alloca bump pointer are cleared and native targets are re-resolved, so a CIB
 * cannot observe state left by an earlier run. ci_vm_result keeps the value of
 * the last *successful* run; a failing run leaves it untouched.
 *
 * Callback trampolines come from a process-wide pool of 256 static slots (no
 * executable memory is generated). There are two lifetimes:
 *
 *   - A CIB that passes `@cb` to a native call gets an automatic trampoline
 *     that stays bound to its VM until that VM is destroyed or its plans are
 *     replaced, and is then retired permanently, so a host function pointer
 *     that outlives its VM can never dispatch into a different one.
 *   - `ci_callback_acquire(fn)` / `ci_callback_release(fn)`, provided by the
 *     header cinterp-cc force-includes (no #include needed), give the CIB
 *     explicit control: acquire returns a trampoline or NULL when the pool is
 *     exhausted, release gives the slot back for reuse and returns 0, CI_E_BUSY
 *     while the callback is still executing, or a negative status for a pointer
 *     this VM does not own. The pointer is dead after a successful release; a
 *     reused slot's old pointer must not be called again. A slot that is still
 *     bound when its VM is destroyed or reloaded stays retired.
 *     ci_callback_pool_stats reports the pool's live/free/retired counts.
 *
 * atexit/signal handlers and native library handles stay process-global:
 * repeated runs and multiple VMs share them.
 */

#define CI_ABI_VERSION 2
typedef struct ci_vm ci_vm;
typedef struct ci_process ci_process;

/*
 * Status values.
 *
 * Functions that return a status return CI_OK on success, or a negative
 * CI_E_* value on failure. CI_ERROR (-1) is only returned when the runtime
 * cannot categorize the failure; all other failures use a specific CI_E_*
 * value. The category of the last failed operation is available from
 * ci_vm_last_error_code(). ci_vm_last_error() returns an error name only in
 * Debug builds; Release builds return an empty string and callers should use
 * the status code.
 *
 * CI_E_BUSY was appended for the per-VM threading model; existing values are
 * unchanged (ABI 2 stays append-only).
 */
enum {
    CI_OK = 0,
    CI_ERROR = -1,
    CI_E_INVALID_ARGUMENT = -2,
    CI_E_OUT_OF_MEMORY = -3,
    CI_E_BAD_PACKAGE = -4,
    CI_E_TARGET = -5,
    CI_E_PLANS = -6,
    CI_E_LINK = -7,
    CI_E_ENTRY = -8,
    CI_E_RESOURCE = -9,
    CI_E_RUNTIME = -10,
    CI_E_DESTROYED = -11,
    CI_E_BUSY = -12
};

/* Flag for ci_vm_destroy_ex: report CI_E_BUSY instead of waiting for a run. */
#define CI_DESTROY_TRY 1u

typedef struct ci_vm_config {
    uint32_t struct_size; /* set to sizeof(ci_vm_config) */
    uint32_t flags;       /* reserved, must be 0 */
    size_t stack_size;    /* 0 = default; upper bound in VM value slots */
    size_t memory_size;   /* 0 = default (1 MiB); linear memory bytes */
} ci_vm_config;

/*
 * ci_vm_create_ex accepts older callers whose struct_size covers only
 * stack_size; memory_size then defaults to 1 MiB. The maximum is 16 MiB.
 */

/* Create a VM. stack_size == 0 selects the default limit. */
ci_vm *ci_vm_create(size_t stack_size);

/* Create a VM from a config. Returns NULL for an invalid config. */
ci_vm *ci_vm_create_ex(const ci_vm_config *config);

/*
 * Destroy a VM.
 *
 * Both forms wait for a run on another thread to finish and then free the VM;
 * a call made by the thread that is currently running the VM (from a callback,
 * for example) cannot wait for itself, so it marks the VM for destruction and
 * the outermost run frees it on the way out. Either way the function never
 * deadlocks, and the VM must not be used after it returned unless the destroy
 * was deferred - in which case it is freed by the run that is already in
 * progress, so the handle is invalid once that run returns.
 *
 * ci_vm_destroy_ex additionally accepts CI_DESTROY_TRY, which returns
 * CI_E_BUSY (and leaves the VM untouched) instead of waiting for a run on
 * another thread. A same-thread (deferred) destroy still succeeds and frees the
 * VM when the current run returns. Unknown flags return CI_E_INVALID_ARGUMENT.
 */
void ci_vm_destroy(ci_vm *vm);
int ci_vm_destroy_ex(ci_vm *vm, unsigned flags);

/*
 * Loaders. They are transactional: a failed load leaves the previous state
 * intact. They return CI_E_BUSY while the VM is executing, from any thread.
 */
int ci_vm_load_module(ci_vm *vm, const uint8_t *data, size_t size);
int ci_vm_load_plans(ci_vm *vm, const uint8_t *data, size_t size);
int ci_vm_load_package(ci_vm *vm, const uint8_t *data, size_t size);

/* Add an explicit host library search handle. */
int ci_vm_load_library(ci_vm *vm, const char *path);

/*
 * Run the named entry. The return value is a status, not main()'s result.
 * Returns CI_E_BUSY when another thread is running the VM and CI_E_RUNTIME
 * when the calling thread already runs it (a nested run).
 */
int ci_vm_run(ci_vm *vm, const char *entry);

/* Run with C argv values, including argv[0] as supplied by the caller. */
int ci_vm_run_args(ci_vm *vm, const char *entry, int argc,
                   const char *const *argv);

/* Result of the last successful run; a failed run does not change it. */
int64_t ci_vm_result(const ci_vm *vm);

/* 1 while the VM is executing on any thread, 0 when it is idle. */
int ci_vm_busy(const ci_vm *vm);

/* Debug error text and a stable category for the last failed operation.
 * Release builds return an empty string from ci_vm_last_error(). */
const char *ci_vm_last_error(const ci_vm *vm);
int ci_vm_last_error_code(const ci_vm *vm);

/*
 * Clear the VM's last error and its callback dispatch error, returning CI_OK
 * (or CI_E_INVALID_ARGUMENT for a NULL VM).
 */
int ci_vm_clear_error(ci_vm *vm);

/*
 * Last failed callback dispatch for this VM as a CI_E_* category, or 0 when
 * none is recorded.
 *
 * A callback that native code invokes while another thread is running the VM
 * is skipped instead of waiting - waiting could deadlock with the run thread,
 * which may itself be waiting for that callback. The skipped call returns
 * deterministic zero values for all non-sret results; an sret buffer supplied
 * by the caller is left unchanged. The skip records CI_E_BUSY here; a VM that
 * is being destroyed records CI_E_DESTROYED. This is a separate channel from
 * ci_vm_last_error/ci_vm_last_error_code, so a host whose native library
 * swallowed the callback result can still observe the skip; it stays until
 * ci_vm_clear_error. Appended to ABI 2.
 */
int ci_vm_callback_error(const ci_vm *vm);

/*
 * Process-wide trampoline pool usage: total is always 256, live slots are
 * bound to a VM, free slots can be acquired, and retired slots can never be
 * used again (their VM was destroyed or replaced its plans while bound). Any
 * output pointer may be NULL. Diagnostic only; appended to ABI 2.
 */
void ci_callback_pool_stats(uint32_t *total, uint32_t *live,
                            uint32_t *free_slots, uint32_t *retired);

/*
 * Process registry: one VM per loaded CIB.
 *
 * A process owns VM lifetimes only; which VM runs, how often and on which
 * thread stays with the host. Every load creates a fresh VM from the stored
 * config, so the returned handle is borrowed: destroy it with
 * ci_process_unload_package, never with ci_vm_destroy. A failed load leaves the
 * registry unchanged and records its CI_E_* category on the process; per-VM
 * run errors stay on the VM (ci_vm_last_error*).
 *
 * The config is validated by ci_process_create (NULL = defaults), and each VM
 * gets the default 1 MiB linear memory unless memory_size is set.
 */
ci_process *ci_process_create(const ci_vm_config *vm_config);

/*
 * Destroy every idle VM and free the registry.
 *
 * A VM that is still executing is left alone: the process and that VM stay
 * alive, ci_process_last_error reports CI_E_BUSY, and the host must join its
 * run threads and call ci_process_destroy again. Blocking here would mean
 * waiting for an unknown thread.
 */
void ci_process_destroy(ci_process *process);

/* Load a package into a new VM. On success *out receives the borrowed VM. */
int ci_process_load_package(ci_process *process, const uint8_t *data,
                            size_t size, ci_vm **out);

/* Unload an idle VM. A VM that is executing is reported as CI_E_BUSY. */
int ci_process_unload_package(ci_process *process, ci_vm *vm);

/* Debug process-level error text and its CI_E_* category.
 * Release builds return an empty string. */
const char *ci_process_last_error(const ci_process *process);
int ci_process_last_error_code(const ci_process *process);

/* Runtime ABI and package version. */
int ci_abi_version(void);
const char *ci_version(void);

#ifdef __cplusplus
}
#endif

#endif /* CINTERP_H */
