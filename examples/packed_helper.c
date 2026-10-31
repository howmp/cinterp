typedef struct __attribute__((packed)) { char c; int x; } P;
int c_pack(P p) { return p.c + p.x; }
P c_make_pack(void) { P p = { 3, 4 }; return p; }
