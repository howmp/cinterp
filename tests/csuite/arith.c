// expect: 50
int main(void) {
    int a = 7, b = 3;
    return a * b + a / b + (a << 2) - (b % 2);
}
