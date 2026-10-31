// expect: 14
void qsort(void *base, unsigned long n, unsigned long size,
           int (*cmp)(const void *, const void *));
int cmp(const void *a, const void *b) {
    int x = *(const int *)a;
    int y = *(const int *)b;
    return x - y;
}
int main(void) {
    int a[4] = { 4, 1, 3, 2 };
    qsort(a, 4, sizeof(int), cmp);
    return a[0] * 10 + a[3];
}
