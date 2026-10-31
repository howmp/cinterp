// expect: 24
int sum_to(int n) {
    int s = 0;
    for (int i = 0; i < n; i++) {
        if (i == 4) continue;
        if (i == 8) break;
        s += i;
    }
    return s;
}
int main(void) {
    int r = 0;
    switch (sum_to(10)) {
    case 24: r = 24; break;
    default: r = 2; break;
    }
    return r;
}
