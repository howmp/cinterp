// expect: 42
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#if !defined(_WIN32)
#include <unistd.h>
#include <time.h>
#include <getopt.h>
extern char **environ;
#endif
int main(void) {
    errno = 0;
    int *e = &errno;
#if !defined(_WIN32)
    char *tz = tzname[0];
    return (environ && stdin && stdout && stderr && e && optind >= 0 && tz)
        ? 42 : 1;
#else
    return (stdin && stdout && stderr && e) ? 42 : 1;
#endif
}
