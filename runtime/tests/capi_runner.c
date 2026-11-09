/*
 * Test-only runner for library-backed CIB cases.
 *
 * The production cinterp-run CLI deliberately has no --lib option. Cross
 * tests still need to exercise CIB plans against helper shared libraries, so
 * this harness links libcinterp and uses the C API directly.
 *
 * usage: capi_runner <package.cib> <library-or-empty> [-- args...]
 */
#include "cinterp.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned char *read_file(const char *path, size_t *size) {
    FILE *file = fopen(path, "rb");
    if (!file) return NULL;
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }
    long length = ftell(file);
    if (length < 0 || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    unsigned char *data = (unsigned char *)malloc((size_t)length);
    if (!data && length != 0) {
        fclose(file);
        return NULL;
    }
    if (length != 0 && fread(data, 1, (size_t)length, file) != (size_t)length) {
        free(data);
        fclose(file);
        return NULL;
    }
    fclose(file);
    *size = (size_t)length;
    return data;
}

static int fail(ci_vm *vm, const char *what) {
    const char *message = ci_vm_last_error(vm);
    if (message && message[0] != 0) {
        fprintf(stderr, "capi_runner: %s: %s\n", what, message);
    } else {
        fprintf(stderr, "capi_runner: %s: error %d\n", what, ci_vm_last_error_code(vm));
    }
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <package.cib> <library-or-empty> [-- args...]\n", argv[0]);
        return 2;
    }

    const char *package_path = argv[1];
    const char *library = argc > 2 ? argv[2] : "";
    int first_arg = argc > 3 && strcmp(argv[3], "--") == 0 ? 4 : 3;

    size_t package_size = 0;
    unsigned char *package = read_file(package_path, &package_size);
    if (!package) {
        fprintf(stderr, "capi_runner: cannot read %s\n", package_path);
        return 2;
    }

    ci_vm *vm = ci_vm_create(0);
    if (!vm) {
        free(package);
        fprintf(stderr, "capi_runner: cannot create VM\n");
        return 2;
    }
    if (library[0] != 0 && ci_vm_load_library(vm, library) != CI_OK) {
        int status = fail(vm, "load library");
        free(package);
        return status;
    }
    if (ci_vm_load_package(vm, package, package_size) != CI_OK) {
        int status = fail(vm, "load package");
        free(package);
        return status;
    }
    free(package);

    const char **vm_argv = (const char **)calloc((size_t)(argc - first_arg + 2), sizeof(char *));
    if (!vm_argv) {
        fprintf(stderr, "capi_runner: out of memory\n");
        return 2;
    }
    int vm_argc = 0;
    vm_argv[vm_argc++] = package_path;
    for (int i = first_arg; i < argc; i += 1) vm_argv[vm_argc++] = argv[i];

    if (ci_vm_run_args(vm, "main", vm_argc, vm_argv) != CI_OK) {
        int status = fail(vm, "run");
        free(vm_argv);
        return status;
    }
    free(vm_argv);

    printf("result: %lld\n", (long long)ci_vm_result(vm));
    return 0;
}
