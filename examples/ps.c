#include <ctype.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int is_pid(const char *name) {
    if (name == NULL || *name == '\0') return 0;
    while (*name != '\0') {
        if (!isdigit((unsigned char)*name)) return 0;
        name++;
    }
    return 1;
}

static void read_comm(const char *pid, char *out, size_t size) {
    char path[64];
    FILE *f;
    size_t n;

    snprintf(path, sizeof(path), "/proc/%s/comm", pid);
    f = fopen(path, "r");
    if (f == NULL) return;
    if (fgets(out, (int)size, f) != NULL) {
        n = strlen(out);
        if (n > 0 && out[n - 1] == '\n') out[n - 1] = '\0';
    }
    fclose(f);
}

static void read_stat(const char *pid, char *state, int *ppid) {
    char path[64];
    char line[512];
    char *right;
    char *p;
    FILE *f;

    snprintf(path, sizeof(path), "/proc/%s/stat", pid);
    f = fopen(path, "r");
    if (f == NULL || fgets(line, sizeof(line), f) == NULL) {
        if (f != NULL) fclose(f);
        return;
    }
    fclose(f);

    right = strrchr(line, ')');
    if (right == NULL) return;
    p = right + 1;
    while (*p == ' ') p++;
    if (*p != '\0') *state = *p;
    p++;
    while (*p == ' ') p++;
    *ppid = atoi(p);
}

static void read_cmdline(const char *pid, const char *comm, char *out, size_t size) {
    char path[64];
    FILE *f;
    size_t n;
    size_t i;

    out[0] = '\0';
    snprintf(path, sizeof(path), "/proc/%s/cmdline", pid);
    f = fopen(path, "rb");
    if (f != NULL) {
        n = fread(out, 1, size - 1, f);
        fclose(f);
        out[n] = '\0';
        for (i = 0; i < n; i++) {
            if (out[i] == '\0') out[i] = ' ';
        }
        while (n > 0 && out[n - 1] == ' ') n--;
        out[n] = '\0';
    }
    if (out[0] == '\0') {
        strncpy(out, comm, size - 1);
        out[size - 1] = '\0';
    }
}

int main(void) {
    DIR *dir;
    struct dirent *entry;
    int processes = 0;

    dir = opendir("/proc");
    if (dir == NULL) {
        perror("opendir /proc");
        return 1;
    }

    printf("PID   PPID S CMD\n");
    while ((entry = readdir(dir)) != NULL) {
        char comm[64] = "?";
        char state = '?';
        char cmd[256];
        int ppid = 0;

        if (!is_pid(entry->d_name)) continue;
        read_comm(entry->d_name, comm, sizeof(comm));
        read_stat(entry->d_name, &state, &ppid);
        read_cmdline(entry->d_name, comm, cmd, sizeof(cmd));
        printf("%-5s %-5d %c %s\n", entry->d_name, ppid, state, cmd);
        processes++;
    }
    closedir(dir);

    printf("processes: %d\n", processes);
    return processes > 0 ? 42 : 1;
}
