// expect: 20
double avg(double a, double b) { return (a + b) / 2.0; }
int main(void) {
    float x = 1.5f;
    double y = 2.5;
    double z = avg((double)x, y);
    return (int)(z * 10.0);
}
