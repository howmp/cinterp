#include <arpa/inet.h>
#include <ifaddrs.h>
#include <linux/if_packet.h>
#include <net/ethernet.h>
#include <net/if.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>

static void print_mac(const unsigned char *addr, unsigned int len) {
    unsigned int i;
    for (i = 0; i < len; i++) {
        if (i != 0) printf(":");
        printf("%02x", (unsigned int)addr[i]);
    }
}

int main(void) {
    struct ifaddrs *list = NULL;
    struct ifaddrs *p;
    char names[32][IFNAMSIZ];
    int interfaces = 0;
    int i;

    if (getifaddrs(&list) != 0) {
        perror("getifaddrs");
        return 1;
    }

    for (p = list; p != NULL; p = p->ifa_next) {
        int seen = 0;
        int j;

        if (p->ifa_name == NULL) continue;
        for (j = 0; j < interfaces; j++) {
            if (strcmp(names[j], p->ifa_name) == 0) {
                seen = 1;
                break;
            }
        }
        if (seen || interfaces >= 32) continue;
        strncpy(names[interfaces], p->ifa_name, IFNAMSIZ - 1);
        names[interfaces][IFNAMSIZ - 1] = '\0';
        interfaces++;
    }

    for (i = 0; i < interfaces; i++) {
        unsigned int flags = 0;
        char addr[INET6_ADDRSTRLEN];

        for (p = list; p != NULL; p = p->ifa_next) {
            if (p->ifa_name != NULL && strcmp(p->ifa_name, names[i]) == 0) {
                flags = p->ifa_flags;
                break;
            }
        }
        printf("%s: flags=0x%x\n", names[i], flags);

        for (p = list; p != NULL; p = p->ifa_next) {
            if (p->ifa_name == NULL || strcmp(p->ifa_name, names[i]) != 0)
                continue;
            if (p->ifa_addr == NULL) continue;

            if (p->ifa_addr->sa_family == AF_INET) {
                struct sockaddr_in *sin = (struct sockaddr_in *)p->ifa_addr;
                if (inet_ntop(AF_INET, &sin->sin_addr, addr, sizeof(addr)) != NULL)
                    printf("  inet %s\n", addr);
            } else if (p->ifa_addr->sa_family == AF_INET6) {
                struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)p->ifa_addr;
                if (inet_ntop(AF_INET6, &sin6->sin6_addr, addr, sizeof(addr)) != NULL)
                    printf("  inet6 %s\n", addr);
            } else if (p->ifa_addr->sa_family == AF_PACKET) {
                struct sockaddr_ll *ll = (struct sockaddr_ll *)p->ifa_addr;
                if (ll->sll_halen > 0) {
                    printf("  ether ");
                    print_mac(ll->sll_addr, ll->sll_halen);
                    printf("\n");
                }
            }
        }
    }

    freeifaddrs(list);
    printf("interfaces: %d\n", interfaces);
    return interfaces > 0 ? 42 : 1;
}
