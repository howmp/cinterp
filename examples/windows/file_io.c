#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

int main(void) {
    char temp[MAX_PATH];
    char path[MAX_PATH];
    char buf[8];
    DWORD temp_len = GetTempPathA(MAX_PATH, temp);
    BOOL created = GetTempFileNameA(temp, "ci", 0, path);
    HANDLE file = INVALID_HANDLE_VALUE;
    DWORD written = 0;
    DWORD read = 0;
    BOOL wrote = 0;
    BOOL read_ok = 0;
    BOOL closed = 1;
    BOOL deleted = 0;

    if (created) {
        file = CreateFileA(path, GENERIC_WRITE, 0, 0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
        if (file != INVALID_HANDLE_VALUE) {
            wrote = WriteFile(file, "hello", 5, &written, 0);
            closed = CloseHandle(file);
        }
        file = CreateFileA(path, GENERIC_READ, 0, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
        if (file != INVALID_HANDLE_VALUE) {
            read_ok = ReadFile(file, buf, 5, &read, 0);
            closed = CloseHandle(file) && closed;
        }
        deleted = DeleteFileA(path);
    }

    printf("temp: %s\n", temp);
    printf("path: %s\n", path);
    printf("write: %lu read: %lu\n", (unsigned long)written, (unsigned long)read);
    return (temp_len > 0 && created && wrote && read_ok && closed && deleted && written == 5 && read == 5) ? 7 : 1;
}
