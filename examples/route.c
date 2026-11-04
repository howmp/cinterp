#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>

static void ipv4_text(const char *hex, char *out, size_t size) {
    unsigned long value = strtoul(hex, NULL, 16);
    snprintf(out, size, "%lu.%lu.%lu.%lu",
             value & 0xff,
             (value >> 8) & 0xff,
             (value >> 16) & 0xff,
             (value >> 24) & 0xff);
}

static int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return 0;
}

static void ipv6_text(const char *hex, char *out, size_t size) {
    unsigned char bytes[16];
    int i;

    for (i = 0; i < 16; i++) {
        bytes[i] = (unsigned char)((hex_digit(hex[i * 2]) << 4) |
                                   hex_digit(hex[i * 2 + 1]));
    }
    if (inet_ntop(AF_INET6, bytes, out, size) == NULL)
        snprintf(out, size, "%s", hex);
}

static int show_ipv4(void) {
    FILE *f;
    char line[512];
    int entries = 0;

    f = fopen("/proc/net/route", "r");
    if (f == NULL) return 0;

    printf("IPv4 routes\n");
    printf("Destination     Gateway         Genmask         Flags Metric Iface\n");
    if (fgets(line, sizeof(line), f) == NULL) {
        fclose(f);
        return 0;
    }
    while (fgets(line, sizeof(line), f) != NULL) {
        char iface[32];
        char dest[16];
        char gateway[16];
        char flags_hex[16];
        char mask[16];
        unsigned int refcnt;
        unsigned int use;
        unsigned int metric;
        unsigned int mtu;
        unsigned int window;
        unsigned int irtt;
        unsigned int flags;
        char dest_text[32];
        char gateway_text[32];
        char mask_text[32];
        char flag_text[8];
        int n;

        n = sscanf(line, " %31s %15s %15s %15s %u %u %u %15s %u %u %u",
                   iface, dest, gateway, flags_hex, &refcnt, &use, &metric,
                   mask, &mtu, &window, &irtt);
        if (n != 11) continue;

        ipv4_text(dest, dest_text, sizeof(dest_text));
        ipv4_text(gateway, gateway_text, sizeof(gateway_text));
        ipv4_text(mask, mask_text, sizeof(mask_text));
        flags = (unsigned int)strtoul(flags_hex, NULL, 16);
        flag_text[0] = (flags & 0x1) ? 'U' : '-';
        flag_text[1] = (flags & 0x2) ? 'G' : '-';
        flag_text[2] = (flags & 0x4) ? 'H' : '-';
        flag_text[3] = (flags & 0x8) ? 'R' : '-';
        flag_text[4] = '\0';

        printf("%-15s %-15s %-15s %-5s %-6u %s\n",
               dest_text, gateway_text, mask_text, flag_text, metric, iface);
        entries++;
    }
    fclose(f);
    printf("IPv4 entries: %d\n", entries);
    return 1;
}

static int show_ipv6(void) {
    FILE *f;
    char line[512];
    int entries = 0;

    f = fopen("/proc/net/ipv6_route", "r");
    if (f == NULL) return 0;

    printf("IPv6 routes\n");
    printf("Destination                     Prefix Gateway                         Iface Flags\n");
    while (fgets(line, sizeof(line), f) != NULL) {
        char dest[40];
        char prefix[8];
        char src[40];
        char src_prefix[8];
        char gateway[40];
        char metric[16];
        char refcnt[16];
        char use[16];
        char flags[16];
        char iface[32];
        char dest_text[INET6_ADDRSTRLEN];
        char gateway_text[INET6_ADDRSTRLEN];
        int n;

        n = sscanf(line, " %39s %7s %39s %7s %39s %15s %15s %15s %15s %31s",
                   dest, prefix, src, src_prefix, gateway, metric, refcnt, use,
                   flags, iface);
        if (n != 10) continue;

        ipv6_text(dest, dest_text, sizeof(dest_text));
        ipv6_text(gateway, gateway_text, sizeof(gateway_text));
        printf("%-31s %-6s %-31s %-5s %s\n",
               dest_text, prefix, gateway_text, iface, flags);
        entries++;
    }
    fclose(f);
    printf("IPv6 entries: %d\n", entries);
    return 1;
}

int main(void) {
    int files = 0;
    files += show_ipv4();
    files += show_ipv6();
    return files > 0 ? 42 : 1;
}
