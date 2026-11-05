#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>

static const char *state_name(const char *state) {
    if (strcmp(state, "01") == 0) return "ESTABLISHED";
    if (strcmp(state, "02") == 0) return "SYN_SENT";
    if (strcmp(state, "03") == 0) return "SYN_RECV";
    if (strcmp(state, "04") == 0) return "FIN_WAIT1";
    if (strcmp(state, "05") == 0) return "FIN_WAIT2";
    if (strcmp(state, "06") == 0) return "TIME_WAIT";
    if (strcmp(state, "07") == 0) return "CLOSE";
    if (strcmp(state, "08") == 0) return "CLOSE_WAIT";
    if (strcmp(state, "09") == 0) return "LAST_ACK";
    if (strcmp(state, "0A") == 0) return "LISTEN";
    if (strcmp(state, "0B") == 0) return "CLOSING";
    return state;
}

static void endpoint(const char *text, char *out, size_t size) {
    const char *colon = strchr(text, ':');
    char address[64];
    size_t len;
    unsigned long port;

    if (colon == NULL) {
        snprintf(out, size, "%s", text);
        return;
    }
    len = (size_t)(colon - text);
    if (len >= sizeof(address)) len = sizeof(address) - 1;
    memcpy(address, text, len);
    address[len] = '\0';
    port = strtoul(colon + 1, NULL, 16);

    if (len == 8) {
        unsigned long value = strtoul(address, NULL, 16);
        snprintf(out, size, "%lu.%lu.%lu.%lu:%lu",
                 value & 0xff,
                 (value >> 8) & 0xff,
                 (value >> 16) & 0xff,
                 (value >> 24) & 0xff,
                 port);
    } else if (len == 32) {
        unsigned char bytes[16];
        char text[INET6_ADDRSTRLEN];
        char part[9];
        int i;

        for (i = 0; i < 4; i++) {
            unsigned long word;
            memcpy(part, address + i * 8, 8);
            part[8] = '\0';
            word = strtoul(part, NULL, 16);
            bytes[i * 4 + 0] = (unsigned char)(word & 0xff);
            bytes[i * 4 + 1] = (unsigned char)((word >> 8) & 0xff);
            bytes[i * 4 + 2] = (unsigned char)((word >> 16) & 0xff);
            bytes[i * 4 + 3] = (unsigned char)((word >> 24) & 0xff);
        }
        if (inet_ntop(AF_INET6, bytes, text, sizeof(text)) != NULL)
            snprintf(out, size, "[%s]:%lu", text, port);
        else
            snprintf(out, size, "[%s]:%lu", address, port);
    } else {
        snprintf(out, size, "[%s]:%lu", address, port);
    }
}

static int show_table(const char *path, const char *proto) {
    FILE *f;
    char line[512];
    int entries = 0;

    f = fopen(path, "r");
    if (f == NULL) return 0;

    printf("Active %s connections\n", proto);
    printf("Proto Local Address           Foreign Address         State\n");
    if (fgets(line, sizeof(line), f) == NULL) {
        fclose(f);
        return 0;
    }

    while (fgets(line, sizeof(line), f) != NULL) {
        unsigned int slot;
        char local[64];
        char remote[64];
        char state[8];
        char local_text[96];
        char remote_text[96];

        if (sscanf(line, " %u: %63s %63s %7s", &slot, local, remote, state) != 4)
            continue;
        endpoint(local, local_text, sizeof(local_text));
        endpoint(remote, remote_text, sizeof(remote_text));
        printf("%-5s %-20s %-22s %s\n", proto, local_text, remote_text, state_name(state));
        entries++;
    }
    fclose(f);
    printf("%s entries: %d\n", proto, entries);
    return 1;
}

int main(void) {
    int files = 0;
    files += show_table("/proc/net/tcp", "tcp");
    files += show_table("/proc/net/tcp6", "tcp6");
    files += show_table("/proc/net/udp", "udp");
    files += show_table("/proc/net/udp6", "udp6");
    return files > 0 ? 42 : 1;
}
