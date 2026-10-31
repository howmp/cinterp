# Fixed x86-64 System V call engine.
# ci_abi_call_sysv64(frame: *SysV64Frame, target: *const anyopaque)
#
# The Zig marshaler fills the frame; this routine only loads registers/stack,
# calls the target, and captures the return registers.

.intel_syntax noprefix

# SysV64Frame offsets (must match main.zig comptime asserts)
.equ F_GPR,        0
.equ F_XMM,        48
.equ F_SSE,        176
.equ F_STACK,      184
.equ F_STACK_SIZE, 192
.equ F_RET_RAX,    208
.equ F_RET_RDX,    216
.equ F_RET_XMM0,   224
.equ F_RET_XMM1,   240
.equ F_RET_X87,    256
.equ F_RET_ST0,    264

.text
.globl ci_abi_call_sysv64
.type ci_abi_call_sysv64, @function
ci_abi_call_sysv64:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi          # frame
    mov r11, rsi          # target

    # alloc = round_up(stack_size, 16) + 8
    # after the pushes rsp % 16 == 8; alloc % 16 == 8 makes rsp 16-aligned
    mov rcx, [rbx + F_STACK_SIZE]
    lea rax, [rcx + 15]
    and rax, -16
    add rax, 8
    sub rsp, rax

    # copy stack arguments to [rsp]; the call pushes the return address,
    # so the callee sees the first stack arg at [rsp + 8].
    mov rsi, [rbx + F_STACK]
    mov rdi, rsp
    rep movsb

    # load XMM0..XMM7
    movups xmm0, [rbx + F_XMM + 0]
    movups xmm1, [rbx + F_XMM + 16]
    movups xmm2, [rbx + F_XMM + 32]
    movups xmm3, [rbx + F_XMM + 48]
    movups xmm4, [rbx + F_XMM + 64]
    movups xmm5, [rbx + F_XMM + 80]
    movups xmm6, [rbx + F_XMM + 96]
    movups xmm7, [rbx + F_XMM + 112]

    # %al for variadic calls
    mov al, [rbx + F_SSE]

    # load integer arguments
    mov rdi, [rbx + F_GPR + 0]
    mov rsi, [rbx + F_GPR + 8]
    mov rdx, [rbx + F_GPR + 16]
    mov rcx, [rbx + F_GPR + 24]
    mov r8,  [rbx + F_GPR + 32]
    mov r9,  [rbx + F_GPR + 40]

    call r11

    # capture return registers
    mov [rbx + F_RET_RAX], rax
    mov [rbx + F_RET_RDX], rdx
    movups [rbx + F_RET_XMM0], xmm0
    movups [rbx + F_RET_XMM1], xmm1
    cmp byte ptr [rbx + F_RET_X87], 0
    je .Lno_x87
    fstp tbyte ptr [rbx + F_RET_ST0]
.Lno_x87:

    lea rsp, [rbp - 40]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

.size ci_abi_call_sysv64, .-ci_abi_call_sysv64
.section .note.GNU-stack,"",@progbits
