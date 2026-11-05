#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

int main(void) {
    char module[MAX_PATH];
    char computer[256];
    DWORD module_len = GetModuleFileNameA(0, module, MAX_PATH);
    DWORD computer_len = sizeof(computer);
    BOOL computer_ok = GetComputerNameA(computer, &computer_len);
    printf("pid: %lu\n", (unsigned long)GetCurrentProcessId());
    printf("tid: %lu\n", (unsigned long)GetCurrentThreadId());
    printf("module: %s\n", module);
    printf("computer: %s\n", computer);
    return (module_len > 0 && module_len < MAX_PATH && computer_ok && computer_len > 0) ? 7 : 1;
}
