#include <stdio.h>
#include <string.h>

#define TAG_MASK 0x0FFFFFFFFFFFFFFFULL
#define HALF_MASK 0x3FFFFFFFU
#define ROUNDS 24

static unsigned int mix32(unsigned int x) {
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}

static unsigned long long mix64(unsigned long long x) {
    x ^= x >> 30;
    x *= 0xbf58476d1ce4e5b9ULL;
    x ^= x >> 27;
    x *= 0x94d049bb133111ebULL;
    x ^= x >> 31;
    return x;
}

static unsigned int hash_a(const char *name, unsigned int len) {
    unsigned int h = 0x811c9dc5U;
    unsigned int i;
    for (i = 0; i < len; i++) {
        h ^= (unsigned char)name[i];
        h *= 16777619U;
    }
    return mix32(h ^ (len * 0x9e3779b9U));
}

static unsigned int hash_b(const char *name, unsigned int len) {
    unsigned int h = 0x9e3779b9U;
    unsigned int i;
    for (i = 0; i < len; i++) {
        h += (unsigned char)name[i] + 0x85ebca6bU;
        h = (h << 7) | (h >> 25);
        h ^= mix32(i + 0xc2b2ae35U);
    }
    return mix32(h ^ len);
}

static unsigned long long name_tag(const char *name) {
    unsigned int len = (unsigned int)strlen(name);
    unsigned int a = hash_a(name, len);
    unsigned int b = hash_b(name, len);
    unsigned long long s = ((unsigned long long)a << 32) | b;
    s = mix64(s ^ (0x9e3779b97f4a7c15ULL * (len + 1)));
    return mix64(s ^ 0x452821e638d01377ULL) & TAG_MASK;
}

static void schedule(unsigned long long tag, unsigned int salt, unsigned int rk[ROUNDS]) {
    unsigned int x = (unsigned int)tag ^ (unsigned int)(tag >> 30) ^
                     (salt * 0x85ebca6bU);
    unsigned int i;
    for (i = 0; i < ROUNDS; i++) {
        x = mix32(x + i * 0x9e3779b9U + 0x7f4a7c15U);
        rk[i] = x & HALF_MASK;
    }
}

static unsigned int round_f(unsigned int r, unsigned int rk) {
    unsigned int x = mix32(r ^ rk);
    x = mix32(x + r * 0x85ebca6bU + 0x9e3779b9U);
    return x & HALF_MASK;
}

static unsigned long long permute(unsigned long long state, unsigned int rk[ROUNDS]) {
    unsigned int l = (unsigned int)(state >> 30) & HALF_MASK;
    unsigned int r = (unsigned int)state & HALF_MASK;
    unsigned int i;
    for (i = 0; i < ROUNDS; i++) {
        unsigned int t = (l ^ round_f(r, rk[i])) & HALF_MASK;
        l = r;
        r = t;
    }
    return ((unsigned long long)l << 30) | r;
}

static int symbol_value(char c) {
    static const char alphabet[] = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
    int i;
    for (i = 0; i < 32; i++) {
        if (alphabet[i] == c) {
            return i;
        }
    }
    return -1;
}

static int parse_serial(const char *s, unsigned int groups[4]) {
    unsigned int i;
    unsigned int g = 0;
    unsigned int value = 0;

    if (strlen(s) != 19) {
        return 0;
    }
    for (i = 0; i < 19; i++) {
        if (i == 4 || i == 9 || i == 14) {
            if (s[i] != '-') {
                return 0;
            }
            groups[g++] = value;
            value = 0;
        } else {
            int d = symbol_value(s[i]);
            if (d < 0) {
                return 0;
            }
            value = (value << 5) | (unsigned int)d;
        }
    }
    groups[3] = value;
    return 1;
}

int main(int argc, char **argv) {
    unsigned int groups[4];
    unsigned int rk[ROUNDS];
    unsigned long long state;
    unsigned long long tag;

    if (argc != 3) {
        printf("usage: %s <name> <serial>\n", argv[0]);
        return 2;
    }

    if (!parse_serial(argv[2], groups)) {
        printf("Malformed serial for '%s'\n", argv[1]);
        return 1;
    }

    state = ((unsigned long long)groups[0] << 40) |
            ((unsigned long long)groups[1] << 20) | groups[2];
    tag = name_tag(argv[1]);
    schedule(tag, groups[3], rk);

    if (permute(state, rk) != tag) {
        printf("Invalid serial for '%s'\n", argv[1]);
        return 1;
    }

    printf("Access granted: welcome, %s!\n", argv[1]);
    return 0;
}
