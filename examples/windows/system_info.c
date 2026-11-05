#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

int main(void) {
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    DWORD ticks = GetTickCount();
    int width = GetSystemMetrics(SM_CXSCREEN);
    printf("processors: %lu\n", (unsigned long)info.dwNumberOfProcessors);
    printf("page size: %lu\n", (unsigned long)info.dwPageSize);
    printf("screen width: %d\n", width);
    printf("uptime ms: %lu\n", (unsigned long)ticks);
    return (info.dwNumberOfProcessors > 0 && info.dwPageSize > 0 && width > 0 && ticks > 0) ? 7 : 1;
}
