double add(double a, double b) {
    return a + b;
}

int main(void) {
    double x = 1.5;
    double y = 2.5;
    double z = add(x, y) * 2.0;
    if (z > 7.0) {
        return (int)z;
    }
    return 0;
}
