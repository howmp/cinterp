// expect: 42
#include <stdlib.h>
struct S { int n; int a[]; };
int main(void) {
    int n = 4;
    int sum = 0;
    for (int i = 0; i < 3; i++) {
        int a[n];
        a[0] = i;
        sum += a[0];
    }
    int a[n];
    a[3] = 36;
    struct S *p = malloc(sizeof(struct S) + 3 * sizeof(int));
    p->n = 3;
    p->a[0] = 1;
    p->a[1] = 1;
    p->a[2] = 1;
    sum += a[3] + p->a[0] + p->a[1] + p->a[2];
    free(p);
    return sum == 42 ? 42 : 1;
}
