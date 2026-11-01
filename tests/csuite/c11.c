// expect: 42
#include <stddef.h>
_Static_assert(sizeof(int) == 4, "int");
_Alignas(16) static int g;
#define T(x) _Generic((x), int: 1, double: 2, default: 0)
static inline int add(int a, int b) { return a + b; }
_Noreturn void never(void);
int main(void) {
    _Alignas(32) char b[3];
    int r = 0;
    r += T(1) == 1;
    r += T(1.0) == 2;
    r += _Alignof(int) == 4;
    r += ((unsigned long)&g % 16) == 0;
    r += ((unsigned long)b % 32) == 0;
    r += add(20, 22) == 42;
    return r == 6 ? 42 : 1;
}
