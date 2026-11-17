#include "cinterp.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    int load_only = 0;
    const char *path;
    if (argc == 3 && strcmp(argv[1], "--load-only") == 0) {
        load_only = 1;
        path = argv[2];
    } else if (argc == 2) {
        path = argv[1];
    } else {
        return 2;
    }
    FILE *f = fopen(path, "rb");
    if (!f) return 3;
    if (fseek(f, 0, SEEK_END) != 0) return 3;
    long n = ftell(f);
    if (n < 0) return 3;
    rewind(f);
    unsigned char *buf = malloc((size_t)n);
    if (!buf) return 4;
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) return 4;
    fclose(f);

    ci_vm *vm = ci_vm_create(0);
    if (!vm) return 5;
    if (ci_vm_load_package(vm, buf, (size_t)n) == CI_OK) {
        if (!load_only) ci_vm_run(vm, "main");
    }
    ci_vm_destroy(vm);
    free(buf);
    return 0;
}
