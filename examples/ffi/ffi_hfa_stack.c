typedef struct { double a, b, c, d; } D4;
double c_hfa9(D4 a, D4 b, D4 c, D4 d, D4 e, D4 f, D4 g, D4 h, D4 i);
int main(void) {
    D4 a = {1,0,0,0}, b = {2,0,0,0}, c = {3,0,0,0};
    D4 d = {4,0,0,0}, e = {5,0,0,0}, f = {6,0,0,0};
    D4 g = {7,0,0,0}, h = {8,0,0,0}, i = {9,0,0,0};
    return (int)c_hfa9(a,b,c,d,e,f,g,h,i);
}
