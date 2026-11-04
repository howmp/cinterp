#include "cinterp.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef CINTERP_EXPECT_VERSION
#define CINTERP_EXPECT_VERSION "0.0.0"
#endif

static unsigned char *read_file(const char *path, size_t *size) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    long n = ftell(f);
    if (n < 0) { fclose(f); return NULL; }
    rewind(f);
    unsigned char *buf = malloc((size_t)n);
    if (!buf) { fclose(f); return NULL; }
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) { free(buf); fclose(f); return NULL; }
    fclose(f);
    *size = (size_t)n;
    return buf;
}

static int load_package(ci_vm *vm, const unsigned char *data, size_t size) {
    int rc = ci_vm_load_package(vm, data, size);
    if (rc != CI_OK) {
        fprintf(stderr, "load failed: %d %s (%d)\n", rc, ci_vm_last_error(vm),
                ci_vm_last_error_code(vm));
    }
    return rc;
}

static uint32_t read_u32(const unsigned char *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

/* A rejected load must return, and record, the CI_E_* category of the defect. */
static int expect_load_error(ci_vm *vm, const unsigned char *data, size_t size, int want) {
    int rc = ci_vm_load_package(vm, data, size);
    if (rc != want) {
        fprintf(stderr, "expected status %d, got %d (%s)\n", want, rc, ci_vm_last_error(vm));
        return 0;
    }
    if (ci_vm_last_error_code(vm) != want) {
        fprintf(stderr, "expected code %d, got %d (%s)\n", want, ci_vm_last_error_code(vm),
                ci_vm_last_error(vm));
        return 0;
    }
    return 1;
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s hello.cib qsort.cib argv.cib\n", argv[0]);
        return 2;
    }
    if (ci_abi_version() != CI_ABI_VERSION) return 3;
    if (strcmp(ci_version(), CINTERP_EXPECT_VERSION) != 0) return 4;

    size_t hello_size = 0, qsort_size = 0, argv_size = 0;
    unsigned char *hello = read_file(argv[1], &hello_size);
    unsigned char *qsort_cib = read_file(argv[2], &qsort_size);
    unsigned char *argv_cib = read_file(argv[3], &argv_size);
    if (!hello || !qsort_cib || !argv_cib) return 5;

    ci_vm_config config = {sizeof(config), 0, 0};
    ci_vm *vm = ci_vm_create_ex(&config);
    if (!vm) return 6;
    if (load_package(vm, hello, hello_size) != CI_OK) return 7;
    if (ci_vm_run(vm, "main") != CI_OK) return 8;
    if (ci_vm_result(vm) != 42) return 9;
    if (ci_vm_last_error(vm)[0] != 0 || ci_vm_last_error_code(vm) != 0) return 10;

    /* A rejected package must not replace the already-loaded one, and the
       status carries the CI_E_* category instead of the generic CI_ERROR. */
    unsigned char *bad = malloc(hello_size);
    if (!bad) return 11;
    memcpy(bad, hello, hello_size);
    bad[0] = 'X';
    if (!expect_load_error(vm, bad, hello_size, CI_E_BAD_PACKAGE)) return 12;
    free(bad);
    if (ci_vm_run(vm, "main") != CI_OK || ci_vm_result(vm) != 42) return 13;

    /* Each package section reports its own category on a bad header. */
    if (hello_size < 25 || memcmp(hello, "CIPKG", 5) != 0 || hello[5] != 2) return 30;
    uint32_t module_len = read_u32(hello + 9);
    uint32_t plan_len = read_u32(hello + 13);
    uint32_t meta_len = read_u32(hello + 17);
    uint32_t import_len = read_u32(hello + 21);
    size_t plan_off = 25 + (size_t)module_len;
    size_t meta_off = plan_off + (size_t)plan_len;
    size_t import_off = meta_off + (size_t)meta_len;
    if (plan_len < 10 || meta_len < 1 || import_len < 4) return 31;
    if (import_off + (size_t)import_len > hello_size) return 31;

    unsigned char *broken = malloc(hello_size);
    if (!broken) return 11;
    memcpy(broken, hello, hello_size);
    broken[meta_off] = 'X';
    if (!expect_load_error(vm, broken, hello_size, CI_E_TARGET)) return 32;

    memcpy(broken, hello, hello_size);
    broken[plan_off + 6] = 0xFF;
    broken[plan_off + 7] = 0xFF;
    if (!expect_load_error(vm, broken, hello_size, CI_E_PLANS)) return 33;

    memcpy(broken, hello, hello_size);
    broken[import_off] = 'X';
    if (!expect_load_error(vm, broken, hello_size, CI_E_BAD_PACKAGE)) return 34;
    free(broken);
    if (ci_vm_run(vm, "main") != CI_OK || ci_vm_result(vm) != 42) return 13;

    char *args[] = {"embed", "x", "7"};
    if (ci_vm_load_package(vm, argv_cib, argv_size) != CI_OK) return 14;
    if (ci_vm_run_args(vm, "main", 3, (const char *const *)args) != CI_OK) return 15;
    if (ci_vm_result(vm) != 7) return 16;
    ci_vm_destroy(vm);

    /* Two VMs with callbacks must not share trampoline state. */
    ci_vm *a = ci_vm_create(0);
    ci_vm *b = ci_vm_create(0);
    if (!a || !b) return 17;
    if (load_package(a, qsort_cib, qsort_size) != CI_OK) return 18;
    if (load_package(b, qsort_cib, qsort_size) != CI_OK) return 19;
    if (ci_vm_run(a, "main") != CI_OK || ci_vm_result(a) != 1) return 20;
    if (ci_vm_run(b, "main") != CI_OK || ci_vm_result(b) != 1) return 21;
    ci_vm_destroy(a);
    if (ci_vm_run(b, "main") != CI_OK || ci_vm_result(b) != 1) return 22;
    ci_vm_destroy(b);

    /* Configurable linear memory, plus the pre-memory_size config layout. */
    ci_vm_config small = {sizeof(small), 0, 0, 64 * 1024};
    ci_vm *m = ci_vm_create_ex(&small);
    if (!m) return 23;
    if (load_package(m, hello, hello_size) != CI_OK) return 24;
    if (ci_vm_run(m, "main") != CI_OK || ci_vm_result(m) != 42) return 25;
    ci_vm_destroy(m);

    ci_vm_config too_big = {sizeof(too_big), 0, 0, (size_t)17 * 1024 * 1024};
    if (ci_vm_create_ex(&too_big) != NULL) return 26;

    struct legacy_config {
        uint32_t struct_size;
        uint32_t flags;
        size_t stack_size;
    } legacy = {sizeof(legacy), 0, 0};
    ci_vm *old = ci_vm_create_ex((const ci_vm_config *)&legacy);
    if (!old) return 27;
    if (load_package(old, hello, hello_size) != CI_OK) return 28;
    if (ci_vm_run(old, "main") != CI_OK || ci_vm_result(old) != 42) return 29;
    ci_vm_destroy(old);

    /* Per-VM execution state: an idle VM is not busy, a failed run keeps the
       last successful result, and CI_DESTROY_TRY frees an idle VM. */
    ci_vm *keep = ci_vm_create(0);
    if (!keep) return 35;
    if (ci_vm_busy(keep) != 0) return 36;
    if (load_package(keep, hello, hello_size) != CI_OK) return 37;
    if (ci_vm_run(keep, "main") != CI_OK) return 38;
    if (ci_vm_result(keep) != 42) return 39;
    if (ci_vm_busy(keep) != 0) return 40;
    if (ci_vm_run(keep, "no-such-entry") != CI_E_ENTRY) return 41;
    if (ci_vm_result(keep) != 42) return 42;
    if (ci_vm_last_error_code(keep) != CI_E_ENTRY) return 43;
    if (ci_vm_destroy_ex(keep, CI_DESTROY_TRY) != CI_OK) return 44;

    /* Process registry: two independent VMs for the same package. */
    ci_process *process = ci_process_create(NULL);
    if (!process) return 45;
    if (ci_process_last_error(process)[0] != 0 || ci_process_last_error_code(process) != 0)
        return 46;
    ci_vm *p1 = NULL;
    ci_vm *p2 = NULL;
    if (ci_process_load_package(process, hello, hello_size, &p1) != CI_OK) return 47;
    if (ci_process_load_package(process, hello, hello_size, &p2) != CI_OK) return 48;
    if (p1 == NULL || p2 == NULL || p1 == p2) return 49;
    if (ci_vm_run(p1, "main") != CI_OK || ci_vm_result(p1) != 42) return 50;
    if (ci_vm_run(p2, "main") != CI_OK || ci_vm_result(p2) != 42) return 51;

    unsigned char *junk = malloc(hello_size);
    if (!junk) return 11;
    memcpy(junk, hello, hello_size);
    junk[0] = 'X';
    ci_vm *unused = NULL;
    if (ci_process_load_package(process, junk, hello_size, &unused) != CI_E_BAD_PACKAGE) return 52;
    if (unused != NULL) return 53;
    if (ci_process_last_error_code(process) != CI_E_BAD_PACKAGE) return 54;
    if (ci_process_last_error(process)[0] == 0) return 54;
    free(junk);
    /* A rejected load left the registry alone. */
    if (ci_vm_run(p2, "main") != CI_OK || ci_vm_result(p2) != 42) return 55;

    if (ci_process_unload_package(process, p1) != CI_OK) return 56;
    if (ci_process_unload_package(process, p2) != CI_OK) return 57;
    ci_process_destroy(process);

    /* The process registry accepts the same pre-memory_size config layout. */
    ci_process *legacy_process = ci_process_create((const ci_vm_config *)&legacy);
    if (!legacy_process) return 58;
    ci_process_destroy(legacy_process);

    free(hello);
    free(qsort_cib);
    free(argv_cib);
    return 0;
}
