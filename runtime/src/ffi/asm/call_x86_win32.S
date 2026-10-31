.intel_syntax noprefix

.equ RET_EAX,    0
.equ RET_EDX,    4
.equ RET_ST0,    8
.equ STACK,      16
.equ STACK_SIZE, 20
.equ CONV,       24
.equ RET_X87,    28
.equ RET_ST0_F80, 32

.text
.globl _ci_win32_call
_ci_win32_call:
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi

    mov ebx, [ebp + 8]
    mov esi, [ebp + 12]
    mov edi, [ebp + 16]

    push esi
    push edi
    mov edx, [ebx + STACK_SIZE]
    sub esp, edx
    mov esi, [ebx + STACK]
    mov edi, esp
    mov ecx, edx
    cld
    rep movsb
    mov edi, [esp + edx]
    mov esi, [esp + edx + 4]
    cmp edi, 2
    jne no_fastcall
    mov ecx, [ebx + RET_EAX]
    mov edx, [ebx + RET_EDX]
no_fastcall:
    call esi

    mov [ebx + RET_EAX], eax
    mov [ebx + RET_EDX], edx
    cmp byte ptr [ebx + RET_X87], 0
    je no_x87
    cmp byte ptr [ebx + RET_X87], 2
    je x87_tbyte
    fstp qword ptr [ebx + RET_ST0]
    jmp no_x87
x87_tbyte:
    fstp tbyte ptr [ebx + RET_ST0_F80]
no_x87:
    test edi, edi
    jne no_clean
    mov ecx, [ebx + STACK_SIZE]
    add esp, ecx
no_clean:
    add esp, 8
    pop edi
    pop esi
    pop ebx
    leave
    ret

.text
.globl _test_ret42
_test_ret42:
    mov eax, 42
    ret
