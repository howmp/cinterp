#include <signal.h>
static volatile sig_atomic_t seen = 0;
static void handler(int sig) { seen = sig; }
int main(void) {
    signal(SIGUSR1, handler);
    raise(SIGUSR1);
    return seen == SIGUSR1 ? 42 : 1;
}
