.intel_syntax noprefix

.equ GPR,        0
.equ XMM,        32
.equ SSE_COUNT,  96
.equ STACK,      104
.equ STACK_SIZE, 112
.equ SRET,       120
.equ RET_RAX,    128
.equ RET_RDX,    136
.equ RET_XMM0,   144
.equ RET_XMM1,   160

.text
.globl ci_win64_call
ci_win64_call:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rcx
    mov r12, rdx

    mov rax, [rbx + STACK_SIZE]
    add rax, 32 + 15
    and rax, -16
    add rax, 8
    sub rsp, rax

    mov rsi, [rbx + STACK]
    lea rdi, [rsp + 32]
    mov rcx, [rbx + STACK_SIZE]
    rep movsb

    mov rcx, [rbx + GPR + 0]
    mov rdx, [rbx + GPR + 8]
    mov r8,  [rbx + GPR + 16]
    mov r9,  [rbx + GPR + 24]

    movups xmm0, [rbx + XMM + 0]
    movups xmm1, [rbx + XMM + 16]
    movups xmm2, [rbx + XMM + 32]
    movups xmm3, [rbx + XMM + 48]

    mov al, [rbx + SSE_COUNT]
    call r12

    mov [rbx + RET_RAX], rax
    mov [rbx + RET_RDX], rdx
    movups [rbx + RET_XMM0], xmm0
    movups [rbx + RET_XMM1], xmm1

    lea rsp, [rbp - 40]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
