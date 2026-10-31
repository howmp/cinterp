typedef struct { int a, b; } S8;
typedef struct { double a, b; } D16;

long c_take_s8(S8 s);
S8 c_make_s8(int a, int b);
double c_take_d16(D16 s);
D16 c_make_d16(double a, double b);

int main(void) {
    S8 a = { 3, 4 };
    S8 b = c_make_s8(5, 6);
    D16 d = { 1.5, 2.5 };
    D16 e = c_make_d16(3.5, 4.5);
    return (int)(c_take_s8(a) + c_take_s8(b) + (long)c_take_d16(d) + (long)c_take_d16(e));
}
