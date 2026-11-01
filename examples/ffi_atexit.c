#include <stdio.h>
#include <stdlib.h>
static void bye(void) { printf("bye\n"); }
int main(void) { atexit(bye); return 42; }
