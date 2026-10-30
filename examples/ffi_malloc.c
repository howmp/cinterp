void *malloc(unsigned long size);
void free(void *p);

int main(void) {
    int *p = (int *)malloc(sizeof(int));
    *p = 42;
    int value = *p;
    free(p);
    return value;
}
