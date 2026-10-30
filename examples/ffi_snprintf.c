int snprintf(char *buf, unsigned long size, const char *fmt, ...);

int main(void) {
    char buf[64];
    snprintf(buf, sizeof buf, "%d %.1f", 7, 2.5);
    return buf[0];
}
