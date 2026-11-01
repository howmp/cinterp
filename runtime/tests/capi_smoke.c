#include "cinterp.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s hello.cib qsort.cib argv.cib\n", argv[0]);
        return 2;
    }
    if (ci_abi_version() != CI_ABI_VERSION) return 3;
    if (strcmp(ci_version(), "0.1.0") != 0) return 4;

    size_t hello_size = 0, qsort_size = 0, argv_size = 0;
    unsigned char *hello = read_file(argv[1], &hello_size);
    unsigned char *qsort_cib = read_file(argv[2], &qsort_size);
    unsigned char *argv_cib = read_file(argv[3], &argv_size);
    if (!hello || !qsort_cib || !argv_cib) return 5;

    ci_vm_config config = {sizeof(config), CI_CONFIG_SAFE, 0};
    ci_vm *vm = ci_vm_create_ex(&config);
    if (!vm) return 6;
    if (load_package(vm, hello, hello_size) != CI_OK) return 7;
    if (ci_vm_run(vm, "main") != CI_OK) return 8;
    if (ci_vm_result(vm) != 42) return 9;
    if (ci_vm_last_error(vm)[0] != 0 || ci_vm_last_error_code(vm) != 0) return 10;

    /* A rejected package must not replace the already-loaded one. */
    unsigned char *bad = malloc(hello_size);
    if (!bad) return 11;
    memcpy(bad, hello, hello_size);
    bad[0] = 'X';
    if (ci_vm_load_package(vm, bad, hello_size) >= 0) return 12;
    free(bad);
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

    free(hello);
    free(qsort_cib);
    free(argv_cib);
    return 0;
}
