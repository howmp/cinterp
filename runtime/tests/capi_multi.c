/*
 * Multi-CIB / multi-threaded process test for the cinterp embedding API.
 *
 * One ci_process owns three VMs (hello, math, ffi_qsort). Each VM is run three
 * times on its own pthread, so the test covers the whole process/session
 * contract: one package per VM, fresh image per run, independent ci_vm_result,
 * a rejected load that leaves the registry alone, and the busy semantics of
 * ci_vm_busy / ci_process_unload_package / ci_process_destroy.
 *
 * The optional fourth argument is a CIB whose main spins for about one second
 * of CPU time. It gives the busy checks a window that does not depend on how
 * fast the interpreter happens to be on the build machine; without it only the
 * idle halves of those checks run.
 *
 * Build and run (see scripts/test/test.sh):
 *   capi_multi hello.cib math.cib ffi_qsort.cib [busy.cib]
 */
#define _POSIX_C_SOURCE 200809L

#include "cinterp.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_RESULTS 8

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

/* One VM run `runs` times from its own thread. */
typedef struct {
    ci_vm *vm;
    int runs;
    int rc;                          /* CI_OK, a CI_E_* status, or a local code */
    int64_t results[MAX_RESULTS];
} vm_worker;

static void *vm_worker_main(void *arg) {
    vm_worker *w = (vm_worker *)arg;
    w->rc = CI_OK;
    for (int i = 0; i < w->runs; i++) {
        int rc = ci_vm_run(w->vm, "main");
        if (rc != CI_OK) {
            w->rc = rc;
            return NULL;
        }
        w->results[i] = ci_vm_result(w->vm);
        /* ci_vm_run returned, so this thread released the execution right. */
        if (ci_vm_busy(w->vm) != 0) {
            w->rc = -100;
            return NULL;
        }
    }
    return NULL;
}

/* Run a VM once; used by the busy-window checks. */
typedef struct {
    ci_vm *vm;
    int rc;
    int64_t result;
} run_once;

static void *run_once_main(void *arg) {
    run_once *w = (run_once *)arg;
    w->rc = ci_vm_run(w->vm, "main");
    w->result = ci_vm_result(w->vm);
    return NULL;
}

/* Wait until another thread is executing the VM (the busy CIB spins for about
   a second of CPU time, so a 1 ms poll resolves the window immediately). */
static int wait_until_busy(ci_vm *vm) {
    struct timespec pause = {0, 1000000L}; /* 1 ms */
    for (int i = 0; i < 10000; i++) {      /* up to 10 s */
        if (ci_vm_busy(vm) == 1) return 1;
        nanosleep(&pause, NULL);
    }
    return 0;
}

static int expect(int condition, int code, const char *what) {
    if (condition) return 0;
    fprintf(stderr, "capi_multi: %s (code %d)\n", what, code);
    return code;
}

int main(int argc, char **argv) {
    if (argc != 4 && argc != 5) {
        fprintf(stderr, "usage: %s hello.cib math.cib ffi_qsort.cib [busy.cib]\n", argv[0]);
        return 2;
    }
    if (ci_abi_version() != CI_ABI_VERSION) return 3;

    size_t hello_size = 0, math_size = 0, qsort_size = 0, busy_size = 0;
    unsigned char *hello = read_file(argv[1], &hello_size);
    unsigned char *math = read_file(argv[2], &math_size);
    unsigned char *qsort_cib = read_file(argv[3], &qsort_size);
    unsigned char *busy = NULL;
    if (argc == 5) busy = read_file(argv[4], &busy_size);
    if (!hello || !math || !qsort_cib || (argc == 5 && !busy)) return 4;

    /* One process, three packages, three VMs, no package sharing. */
    ci_process *process = ci_process_create(NULL);
    if (!process) return 5;
    ci_vm *vms[3] = {NULL, NULL, NULL};
    const unsigned char *packages[3] = {hello, math, qsort_cib};
    const size_t package_sizes[3] = {hello_size, math_size, qsort_size};
    const int64_t expected[3] = {42, 8, 1};
    for (int i = 0; i < 3; i++) {
        int rc = ci_process_load_package(process, packages[i], package_sizes[i], &vms[i]);
        if (rc != CI_OK) {
            fprintf(stderr, "load %s failed: %d %s\n", argv[i + 1], rc,
                    ci_process_last_error(process));
            return 6;
        }
        if (!vms[i]) return 7;
        if (expect(ci_vm_busy(vms[i]) == 0, 8, "freshly loaded VM is not idle")) return 8;
    }
    if (vms[0] == vms[1] || vms[1] == vms[2] || vms[0] == vms[2]) return 9;

    /* Three threads, three VMs, three fresh-image runs each. Results must be
       independent: a VM never sees another VM's package or result. */
    pthread_t threads[3];
    vm_worker workers[3];
    memset(workers, 0, sizeof(workers));
    for (int i = 0; i < 3; i++) {
        workers[i].vm = vms[i];
        workers[i].runs = 3;
        if (pthread_create(&threads[i], NULL, vm_worker_main, &workers[i]) != 0) return 10;
    }
    for (int i = 0; i < 3; i++) pthread_join(threads[i], NULL);
    for (int i = 0; i < 3; i++) {
        if (workers[i].rc != CI_OK) {
            fprintf(stderr, "run %s failed: %d %s\n", argv[i + 1], workers[i].rc,
                    ci_vm_last_error(vms[i]));
            return 11;
        }
        for (int r = 0; r < 3; r++) {
            if (workers[i].results[r] != expected[i]) {
                fprintf(stderr, "%s run %d: expected %lld, got %lld\n", argv[i + 1], r,
                        (long long)expected[i], (long long)workers[i].results[r]);
                return 12;
            }
        }
        if (ci_vm_result(vms[i]) != expected[i]) return 13;
        if (expect(ci_vm_busy(vms[i]) == 0, 14, "VM still busy after its run finished")) return 14;
    }

    /* A rejected package must not enter the registry and must not disturb the
       VMs that are already loaded. */
    unsigned char *bad = malloc(hello_size);
    if (!bad) return 15;
    memcpy(bad, hello, hello_size);
    bad[0] = 'X';
    ci_vm *rejected = NULL;
    int rc = ci_process_load_package(process, bad, hello_size, &rejected);
    if (rc != CI_E_BAD_PACKAGE) {
        fprintf(stderr, "bad package: expected CI_E_BAD_PACKAGE, got %d (%s)\n", rc,
                ci_process_last_error(process));
        return 16;
    }
    if (rejected != NULL) return 17;
    if (ci_process_last_error_code(process) != CI_E_BAD_PACKAGE) return 18;
    free(bad);

    if (ci_vm_run(vms[0], "main") != CI_OK || ci_vm_result(vms[0]) != 42) return 20;
    if (ci_vm_run(vms[1], "main") != CI_OK || ci_vm_result(vms[1]) != 8) return 21;

    /* Unloading is per VM: the remaining VMs keep running afterwards. */
    if (ci_process_unload_package(process, vms[2]) != CI_OK) return 22;
    if (ci_process_unload_package(process, vms[2]) != CI_E_INVALID_ARGUMENT) return 23;
    if (ci_vm_run(vms[0], "main") != CI_OK || ci_vm_result(vms[0]) != 42) return 24;

    /* Busy window: a VM that is executing on another thread reports busy, and
       every API that would free or replace its package refuses with CI_E_BUSY
       instead of touching the running image. */
    if (busy) {
        ci_vm *spin = NULL;
        if (ci_process_load_package(process, busy, busy_size, &spin) != CI_OK) return 25;
        run_once spinning = {spin, CI_OK, 0};
        pthread_t spinner;
        if (pthread_create(&spinner, NULL, run_once_main, &spinning) != 0) return 26;
        if (!wait_until_busy(spin)) {
            pthread_join(spinner, NULL);
            return 27;
        }
        if (ci_vm_busy(spin) != 1) return 28;
        /* A second thread may not run the same VM... */
        if (ci_vm_run(spin, "main") != CI_E_BUSY) return 29;
        /* ...and no loader may replace the module under the running frame. */
        if (ci_vm_load_package(spin, hello, hello_size) != CI_E_BUSY) return 30;
        /* ...and the process registry will not free it. */
        if (ci_process_unload_package(process, spin) != CI_E_BUSY) return 31;
        if (ci_process_last_error_code(process) != CI_E_BUSY) return 32;
        pthread_join(spinner, NULL);
        if (spinning.rc != CI_OK) return 33;
        if (spinning.result != 7) return 34;
        if (expect(ci_vm_busy(spin) == 0, 35, "VM still busy after the spinner joined")) return 35;
        if (ci_process_unload_package(process, spin) != CI_OK) return 36;
    }

    /* ci_process_destroy reports a running VM and keeps the registry alive
       instead of waiting for an unknown thread; a second call after the join
       frees everything. */
    if (busy) {
        ci_process *second = ci_process_create(NULL);
        if (!second) return 37;
        ci_vm *spin = NULL;
        if (ci_process_load_package(second, busy, busy_size, &spin) != CI_OK) return 38;
        run_once spinning = {spin, CI_OK, 0};
        pthread_t spinner;
        if (pthread_create(&spinner, NULL, run_once_main, &spinning) != 0) return 39;
        if (!wait_until_busy(spin)) {
            pthread_join(spinner, NULL);
            ci_process_destroy(second);
            return 40;
        }
        ci_process_destroy(second);
        if (ci_process_last_error_code(second) != CI_E_BUSY) return 41;
        if (ci_vm_busy(spin) != 1) return 42;
        pthread_join(spinner, NULL);
        if (spinning.rc != CI_OK || spinning.result != 7) return 43;
        ci_process_destroy(second); /* idle now: registry and VM are freed */
    }

    if (ci_process_unload_package(process, vms[0]) != CI_OK) return 44;
    if (ci_process_unload_package(process, vms[1]) != CI_OK) return 45;
    ci_process_destroy(process);

    free(hello);
    free(math);
    free(qsort_cib);
    free(busy);
    return 0;
}
