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
 * build time. It does not need clang or Python at runtime. A VM owns one
 * package at a time and is intended to be used by one thread at a time.
 * Separate VM instances may be used independently; callback trampolines are
 * process-wide and are retired permanently when their owning VM is destroyed.
 */

#define CI_ABI_VERSION 2
typedef struct ci_vm ci_vm;

/* Status values. Functions return CI_OK or a negative CI_E_* value. */
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
    CI_E_DESTROYED = -11
};

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

void ci_vm_destroy(ci_vm *vm);

/* Loaders are transactional: a failed load leaves the previous state intact. */
int ci_vm_load_module(ci_vm *vm, const uint8_t *data, size_t size);
int ci_vm_load_plans(ci_vm *vm, const uint8_t *data, size_t size);
int ci_vm_load_package(ci_vm *vm, const uint8_t *data, size_t size);

/* Add an explicit host library search handle. */
int ci_vm_load_library(ci_vm *vm, const char *path);

/* Run the named entry. The return value is a status, not main()'s result. */
int ci_vm_run(ci_vm *vm, const char *entry);

/* Run with C argv values, including argv[0] as supplied by the caller. */
int ci_vm_run_args(ci_vm *vm, const char *entry, int argc,
                   const char *const *argv);

/* Result of the last successful run. */
int64_t ci_vm_result(const ci_vm *vm);

/* Error text and a stable category for the last failed operation. */
const char *ci_vm_last_error(const ci_vm *vm);
int ci_vm_last_error_code(const ci_vm *vm);
int ci_vm_clear_error(ci_vm *vm);

/* Runtime ABI and package version. */
int ci_abi_version(void);
const char *ci_version(void);

#ifdef __cplusplus
}
#endif

#endif /* CINTERP_H */
