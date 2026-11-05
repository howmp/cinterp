/* Explicit callback lifetime: `cinterp-cc` force-includes
 * `cinterp_callbacks.h`, so this file needs no `#include`, no include path and
 * no declaration of `ci_callback_acquire`/`ci_callback_release`.
 *
 * `ci_callback_acquire` only accepts a direct function reference of this CIB
 * (the `&` keeps the function-pointer type the macro re-casts the result to)
 * and returns a trampoline address, or NULL when the pool is exhausted.
 * `ci_callback_release` returns 0 once the trampoline is released; the pointer
 * must not be used (or passed to native code) afterwards.
 */

void qsort(void *base, unsigned long n, unsigned long size,
           int (*cmp)(const void *, const void *));

int cmp(const void *a, const void *b) {
    int x = *(const int *)a;
    int y = *(const int *)b;
    return x - y;
}

int main(void) {
    int a[5] = { 3, 1, 4, 2, 5 };
    int (*cb)(const void *, const void *) = ci_callback_acquire(&cmp);
    if (cb == 0) return 1;
    qsort(a, 5, sizeof(int), cb);
    int status = ci_callback_release(cb);
    if (status != 0) return 2;
    return a[0];
}
