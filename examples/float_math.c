float addf(float a, float b) {
    return a + b;
}

int main(void) {
    float x = 1.5f;
    float y = 2.5f;
    float z = addf(x, y) * 2.0f;
    if (z > 7.0f) {
        return (int)z;
    }
    return 0;
}
