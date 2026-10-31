// expect: 42
#include <setjmp.h>
static jmp_buf env;
int main(void) {
    volatile int x = 0;
    if (setjmp(env) == 0) {
        x = 42;
        longjmp(env, 1);
    }
    return x;
}
