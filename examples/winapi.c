typedef unsigned long long u64;

__declspec(dllimport) u64 __stdcall GetTickCount64(void);
__declspec(dllimport) int __stdcall GetSystemMetrics(int index);
__declspec(dllimport) void *__stdcall GetModuleHandleA(const char *name);
__declspec(dllimport) int __cdecl wsprintfA(char *buf, const char *fmt, ...);

int main(void) {
    u64 ticks = GetTickCount64();
    int width = GetSystemMetrics(0);
    void *module = GetModuleHandleA(0);
    char buf[32];
    int n = wsprintfA(buf, "%d", 42);
    return (ticks > 0 && width > 0 && module != 0 && n == 2) ? 7 : 1;
}
