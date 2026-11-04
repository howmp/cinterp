#include <stdio.h>
#include <string.h>

int main(void) {
    char buf[128];
    int n = snprintf(buf, sizeof buf, "%Lf", 3.5L);
    if (n <= 0 || buf[0] == '\0') return 1;
    if (strlen(buf) != (size_t)n) return 2;
    return 42;
}
