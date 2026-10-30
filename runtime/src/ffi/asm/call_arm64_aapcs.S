.arch armv8-a
.text
.globl ci_arm64_call
.type ci_arm64_call, %function
ci_arm64_call:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov x20, x0
    mov x19, x1

    ldr x9, [x20, #208]
    add x9, x9, #15
    and x9, x9, #-16
    sub sp, sp, x9

    ldr x10, [x20, #200]
    mov x11, sp
    ldr x12, [x20, #208]
    cbz x12, 2f
1:
    ldrb w13, [x10], #1
    strb w13, [x11], #1
    subs x12, x12, #1
    b.ne 1b
2:
    ldp x0, x1, [x20, #0]
    ldp x2, x3, [x20, #16]
    ldp x4, x5, [x20, #32]
    ldp x6, x7, [x20, #48]

    ldp q0, q1, [x20, #64]
    ldp q2, q3, [x20, #96]
    ldp q4, q5, [x20, #128]
    ldp q6, q7, [x20, #160]

    ldr x8, [x20, #192]
    blr x19

    stp x0, x1, [x20, #216]
    stp q0, q1, [x20, #240]

    mov sp, x29
    ldp x21, x22, [sp, #-32]
    ldp x19, x20, [sp, #-16]
    mov sp, x29
    ldp x29, x30, [sp], #16
    ret
.size ci_arm64_call, .-ci_arm64_call

.section .note.GNU-stack,"",@progbits
