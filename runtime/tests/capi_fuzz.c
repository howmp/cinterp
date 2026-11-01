#include "cinterp.h"

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    FILE *f = fopen(argv[1], "rb");
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
        ci_vm_run(vm, "main");
    }
    ci_vm_destroy(vm);
    free(buf);
    return 0;
}
