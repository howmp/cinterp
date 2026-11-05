#define WIN32_LEAN_AND_MEAN
#include <windows.h>

int main(void) {
    ULONGLONG ticks = GetTickCount64();
    int width = GetSystemMetrics(SM_CXSCREEN);
    HMODULE module = GetModuleHandleA(0);
    char buf[32];
    int n = wsprintfA(buf, "%d", 42);
    return (ticks > 0 && width > 0 && module != 0 && n == 2) ? 7 : 1;
}
