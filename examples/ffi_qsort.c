void qsort(void *base, unsigned long n, unsigned long size,
           int (*cmp)(const void *, const void *));

int cmp(const void *a, const void *b) {
    int x = *(const int *)a;
    int y = *(const int *)b;
    return x - y;
}

int main(void) {
    int a[5] = { 3, 1, 4, 2, 5 };
    qsort(a, 5, sizeof(int), cmp);
    return a[0];
}
