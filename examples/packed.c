typedef struct __attribute__((packed)) { char c; int x; } P;
int c_pack(P p);
P c_make_pack(void);
int main(void) { P p = c_make_pack(); return c_pack(p); }
