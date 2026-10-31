// expect: 118
int g[4] = { 2, 4, 6, 8 };
int main(void) {
    int *p = g;
    int s = 0;
    for (int i = 0; i < 4; i++) s += *(p + i);
    char *text = "abc";
    return s + text[1];
}
