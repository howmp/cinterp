
.intel_syntax noprefix

.equ CB_SLOT,      0
.equ CB_GPR,       8
.equ CB_XMM,       56
.equ CB_STACK,     184
.equ CB_RET_RAX,   192
.equ CB_RET_RDX,   200
.equ CB_RET_XMM0,  208
.equ CB_RET_XMM1,  224

.text

ci_cb_sysv_entry:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 248
    mov rbx, rsp

    mov [rbx + CB_SLOT], r11

    mov [rbx + CB_GPR + 0], rdi
    mov [rbx + CB_GPR + 8], rsi
    mov [rbx + CB_GPR + 16], rdx
    mov [rbx + CB_GPR + 24], rcx
    mov [rbx + CB_GPR + 32], r8
    mov [rbx + CB_GPR + 40], r9

    movups [rbx + CB_XMM + 0], xmm0
    movups [rbx + CB_XMM + 16], xmm1
    movups [rbx + CB_XMM + 32], xmm2
    movups [rbx + CB_XMM + 48], xmm3
    movups [rbx + CB_XMM + 64], xmm4
    movups [rbx + CB_XMM + 80], xmm5
    movups [rbx + CB_XMM + 96], xmm6
    movups [rbx + CB_XMM + 112], xmm7

    lea rax, [rbp + 16]
    mov [rbx + CB_STACK], rax

    mov rdi, [rbx + CB_SLOT]
    mov rsi, rbx
    call ci_callback_dispatch

    mov rax, [rbx + CB_RET_RAX]
    mov rdx, [rbx + CB_RET_RDX]
    movups xmm0, [rbx + CB_RET_XMM0]
    movups xmm1, [rbx + CB_RET_XMM1]

    lea rsp, [rbp - 40]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

.globl ci_cb_sysv_0
ci_cb_sysv_0:
    mov r11d, 0
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_1
ci_cb_sysv_1:
    mov r11d, 1
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_2
ci_cb_sysv_2:
    mov r11d, 2
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_3
ci_cb_sysv_3:
    mov r11d, 3
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_4
ci_cb_sysv_4:
    mov r11d, 4
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_5
ci_cb_sysv_5:
    mov r11d, 5
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_6
ci_cb_sysv_6:
    mov r11d, 6
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_7
ci_cb_sysv_7:
    mov r11d, 7
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_8
ci_cb_sysv_8:
    mov r11d, 8
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_9
ci_cb_sysv_9:
    mov r11d, 9
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_10
ci_cb_sysv_10:
    mov r11d, 10
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_11
ci_cb_sysv_11:
    mov r11d, 11
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_12
ci_cb_sysv_12:
    mov r11d, 12
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_13
ci_cb_sysv_13:
    mov r11d, 13
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_14
ci_cb_sysv_14:
    mov r11d, 14
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_15
ci_cb_sysv_15:
    mov r11d, 15
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_16
ci_cb_sysv_16:
    mov r11d, 16
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_17
ci_cb_sysv_17:
    mov r11d, 17
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_18
ci_cb_sysv_18:
    mov r11d, 18
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_19
ci_cb_sysv_19:
    mov r11d, 19
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_20
ci_cb_sysv_20:
    mov r11d, 20
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_21
ci_cb_sysv_21:
    mov r11d, 21
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_22
ci_cb_sysv_22:
    mov r11d, 22
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_23
ci_cb_sysv_23:
    mov r11d, 23
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_24
ci_cb_sysv_24:
    mov r11d, 24
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_25
ci_cb_sysv_25:
    mov r11d, 25
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_26
ci_cb_sysv_26:
    mov r11d, 26
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_27
ci_cb_sysv_27:
    mov r11d, 27
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_28
ci_cb_sysv_28:
    mov r11d, 28
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_29
ci_cb_sysv_29:
    mov r11d, 29
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_30
ci_cb_sysv_30:
    mov r11d, 30
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_31
ci_cb_sysv_31:
    mov r11d, 31
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_32
ci_cb_sysv_32:
    mov r11d, 32
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_33
ci_cb_sysv_33:
    mov r11d, 33
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_34
ci_cb_sysv_34:
    mov r11d, 34
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_35
ci_cb_sysv_35:
    mov r11d, 35
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_36
ci_cb_sysv_36:
    mov r11d, 36
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_37
ci_cb_sysv_37:
    mov r11d, 37
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_38
ci_cb_sysv_38:
    mov r11d, 38
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_39
ci_cb_sysv_39:
    mov r11d, 39
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_40
ci_cb_sysv_40:
    mov r11d, 40
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_41
ci_cb_sysv_41:
    mov r11d, 41
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_42
ci_cb_sysv_42:
    mov r11d, 42
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_43
ci_cb_sysv_43:
    mov r11d, 43
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_44
ci_cb_sysv_44:
    mov r11d, 44
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_45
ci_cb_sysv_45:
    mov r11d, 45
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_46
ci_cb_sysv_46:
    mov r11d, 46
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_47
ci_cb_sysv_47:
    mov r11d, 47
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_48
ci_cb_sysv_48:
    mov r11d, 48
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_49
ci_cb_sysv_49:
    mov r11d, 49
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_50
ci_cb_sysv_50:
    mov r11d, 50
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_51
ci_cb_sysv_51:
    mov r11d, 51
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_52
ci_cb_sysv_52:
    mov r11d, 52
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_53
ci_cb_sysv_53:
    mov r11d, 53
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_54
ci_cb_sysv_54:
    mov r11d, 54
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_55
ci_cb_sysv_55:
    mov r11d, 55
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_56
ci_cb_sysv_56:
    mov r11d, 56
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_57
ci_cb_sysv_57:
    mov r11d, 57
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_58
ci_cb_sysv_58:
    mov r11d, 58
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_59
ci_cb_sysv_59:
    mov r11d, 59
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_60
ci_cb_sysv_60:
    mov r11d, 60
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_61
ci_cb_sysv_61:
    mov r11d, 61
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_62
ci_cb_sysv_62:
    mov r11d, 62
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_63
ci_cb_sysv_63:
    mov r11d, 63
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_64
ci_cb_sysv_64:
    mov r11d, 64
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_65
ci_cb_sysv_65:
    mov r11d, 65
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_66
ci_cb_sysv_66:
    mov r11d, 66
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_67
ci_cb_sysv_67:
    mov r11d, 67
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_68
ci_cb_sysv_68:
    mov r11d, 68
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_69
ci_cb_sysv_69:
    mov r11d, 69
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_70
ci_cb_sysv_70:
    mov r11d, 70
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_71
ci_cb_sysv_71:
    mov r11d, 71
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_72
ci_cb_sysv_72:
    mov r11d, 72
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_73
ci_cb_sysv_73:
    mov r11d, 73
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_74
ci_cb_sysv_74:
    mov r11d, 74
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_75
ci_cb_sysv_75:
    mov r11d, 75
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_76
ci_cb_sysv_76:
    mov r11d, 76
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_77
ci_cb_sysv_77:
    mov r11d, 77
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_78
ci_cb_sysv_78:
    mov r11d, 78
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_79
ci_cb_sysv_79:
    mov r11d, 79
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_80
ci_cb_sysv_80:
    mov r11d, 80
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_81
ci_cb_sysv_81:
    mov r11d, 81
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_82
ci_cb_sysv_82:
    mov r11d, 82
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_83
ci_cb_sysv_83:
    mov r11d, 83
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_84
ci_cb_sysv_84:
    mov r11d, 84
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_85
ci_cb_sysv_85:
    mov r11d, 85
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_86
ci_cb_sysv_86:
    mov r11d, 86
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_87
ci_cb_sysv_87:
    mov r11d, 87
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_88
ci_cb_sysv_88:
    mov r11d, 88
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_89
ci_cb_sysv_89:
    mov r11d, 89
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_90
ci_cb_sysv_90:
    mov r11d, 90
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_91
ci_cb_sysv_91:
    mov r11d, 91
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_92
ci_cb_sysv_92:
    mov r11d, 92
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_93
ci_cb_sysv_93:
    mov r11d, 93
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_94
ci_cb_sysv_94:
    mov r11d, 94
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_95
ci_cb_sysv_95:
    mov r11d, 95
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_96
ci_cb_sysv_96:
    mov r11d, 96
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_97
ci_cb_sysv_97:
    mov r11d, 97
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_98
ci_cb_sysv_98:
    mov r11d, 98
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_99
ci_cb_sysv_99:
    mov r11d, 99
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_100
ci_cb_sysv_100:
    mov r11d, 100
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_101
ci_cb_sysv_101:
    mov r11d, 101
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_102
ci_cb_sysv_102:
    mov r11d, 102
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_103
ci_cb_sysv_103:
    mov r11d, 103
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_104
ci_cb_sysv_104:
    mov r11d, 104
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_105
ci_cb_sysv_105:
    mov r11d, 105
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_106
ci_cb_sysv_106:
    mov r11d, 106
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_107
ci_cb_sysv_107:
    mov r11d, 107
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_108
ci_cb_sysv_108:
    mov r11d, 108
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_109
ci_cb_sysv_109:
    mov r11d, 109
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_110
ci_cb_sysv_110:
    mov r11d, 110
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_111
ci_cb_sysv_111:
    mov r11d, 111
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_112
ci_cb_sysv_112:
    mov r11d, 112
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_113
ci_cb_sysv_113:
    mov r11d, 113
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_114
ci_cb_sysv_114:
    mov r11d, 114
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_115
ci_cb_sysv_115:
    mov r11d, 115
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_116
ci_cb_sysv_116:
    mov r11d, 116
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_117
ci_cb_sysv_117:
    mov r11d, 117
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_118
ci_cb_sysv_118:
    mov r11d, 118
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_119
ci_cb_sysv_119:
    mov r11d, 119
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_120
ci_cb_sysv_120:
    mov r11d, 120
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_121
ci_cb_sysv_121:
    mov r11d, 121
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_122
ci_cb_sysv_122:
    mov r11d, 122
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_123
ci_cb_sysv_123:
    mov r11d, 123
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_124
ci_cb_sysv_124:
    mov r11d, 124
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_125
ci_cb_sysv_125:
    mov r11d, 125
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_126
ci_cb_sysv_126:
    mov r11d, 126
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_127
ci_cb_sysv_127:
    mov r11d, 127
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_128
ci_cb_sysv_128:
    mov r11d, 128
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_129
ci_cb_sysv_129:
    mov r11d, 129
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_130
ci_cb_sysv_130:
    mov r11d, 130
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_131
ci_cb_sysv_131:
    mov r11d, 131
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_132
ci_cb_sysv_132:
    mov r11d, 132
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_133
ci_cb_sysv_133:
    mov r11d, 133
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_134
ci_cb_sysv_134:
    mov r11d, 134
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_135
ci_cb_sysv_135:
    mov r11d, 135
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_136
ci_cb_sysv_136:
    mov r11d, 136
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_137
ci_cb_sysv_137:
    mov r11d, 137
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_138
ci_cb_sysv_138:
    mov r11d, 138
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_139
ci_cb_sysv_139:
    mov r11d, 139
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_140
ci_cb_sysv_140:
    mov r11d, 140
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_141
ci_cb_sysv_141:
    mov r11d, 141
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_142
ci_cb_sysv_142:
    mov r11d, 142
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_143
ci_cb_sysv_143:
    mov r11d, 143
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_144
ci_cb_sysv_144:
    mov r11d, 144
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_145
ci_cb_sysv_145:
    mov r11d, 145
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_146
ci_cb_sysv_146:
    mov r11d, 146
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_147
ci_cb_sysv_147:
    mov r11d, 147
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_148
ci_cb_sysv_148:
    mov r11d, 148
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_149
ci_cb_sysv_149:
    mov r11d, 149
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_150
ci_cb_sysv_150:
    mov r11d, 150
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_151
ci_cb_sysv_151:
    mov r11d, 151
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_152
ci_cb_sysv_152:
    mov r11d, 152
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_153
ci_cb_sysv_153:
    mov r11d, 153
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_154
ci_cb_sysv_154:
    mov r11d, 154
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_155
ci_cb_sysv_155:
    mov r11d, 155
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_156
ci_cb_sysv_156:
    mov r11d, 156
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_157
ci_cb_sysv_157:
    mov r11d, 157
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_158
ci_cb_sysv_158:
    mov r11d, 158
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_159
ci_cb_sysv_159:
    mov r11d, 159
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_160
ci_cb_sysv_160:
    mov r11d, 160
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_161
ci_cb_sysv_161:
    mov r11d, 161
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_162
ci_cb_sysv_162:
    mov r11d, 162
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_163
ci_cb_sysv_163:
    mov r11d, 163
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_164
ci_cb_sysv_164:
    mov r11d, 164
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_165
ci_cb_sysv_165:
    mov r11d, 165
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_166
ci_cb_sysv_166:
    mov r11d, 166
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_167
ci_cb_sysv_167:
    mov r11d, 167
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_168
ci_cb_sysv_168:
    mov r11d, 168
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_169
ci_cb_sysv_169:
    mov r11d, 169
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_170
ci_cb_sysv_170:
    mov r11d, 170
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_171
ci_cb_sysv_171:
    mov r11d, 171
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_172
ci_cb_sysv_172:
    mov r11d, 172
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_173
ci_cb_sysv_173:
    mov r11d, 173
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_174
ci_cb_sysv_174:
    mov r11d, 174
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_175
ci_cb_sysv_175:
    mov r11d, 175
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_176
ci_cb_sysv_176:
    mov r11d, 176
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_177
ci_cb_sysv_177:
    mov r11d, 177
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_178
ci_cb_sysv_178:
    mov r11d, 178
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_179
ci_cb_sysv_179:
    mov r11d, 179
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_180
ci_cb_sysv_180:
    mov r11d, 180
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_181
ci_cb_sysv_181:
    mov r11d, 181
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_182
ci_cb_sysv_182:
    mov r11d, 182
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_183
ci_cb_sysv_183:
    mov r11d, 183
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_184
ci_cb_sysv_184:
    mov r11d, 184
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_185
ci_cb_sysv_185:
    mov r11d, 185
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_186
ci_cb_sysv_186:
    mov r11d, 186
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_187
ci_cb_sysv_187:
    mov r11d, 187
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_188
ci_cb_sysv_188:
    mov r11d, 188
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_189
ci_cb_sysv_189:
    mov r11d, 189
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_190
ci_cb_sysv_190:
    mov r11d, 190
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_191
ci_cb_sysv_191:
    mov r11d, 191
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_192
ci_cb_sysv_192:
    mov r11d, 192
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_193
ci_cb_sysv_193:
    mov r11d, 193
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_194
ci_cb_sysv_194:
    mov r11d, 194
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_195
ci_cb_sysv_195:
    mov r11d, 195
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_196
ci_cb_sysv_196:
    mov r11d, 196
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_197
ci_cb_sysv_197:
    mov r11d, 197
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_198
ci_cb_sysv_198:
    mov r11d, 198
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_199
ci_cb_sysv_199:
    mov r11d, 199
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_200
ci_cb_sysv_200:
    mov r11d, 200
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_201
ci_cb_sysv_201:
    mov r11d, 201
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_202
ci_cb_sysv_202:
    mov r11d, 202
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_203
ci_cb_sysv_203:
    mov r11d, 203
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_204
ci_cb_sysv_204:
    mov r11d, 204
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_205
ci_cb_sysv_205:
    mov r11d, 205
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_206
ci_cb_sysv_206:
    mov r11d, 206
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_207
ci_cb_sysv_207:
    mov r11d, 207
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_208
ci_cb_sysv_208:
    mov r11d, 208
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_209
ci_cb_sysv_209:
    mov r11d, 209
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_210
ci_cb_sysv_210:
    mov r11d, 210
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_211
ci_cb_sysv_211:
    mov r11d, 211
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_212
ci_cb_sysv_212:
    mov r11d, 212
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_213
ci_cb_sysv_213:
    mov r11d, 213
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_214
ci_cb_sysv_214:
    mov r11d, 214
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_215
ci_cb_sysv_215:
    mov r11d, 215
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_216
ci_cb_sysv_216:
    mov r11d, 216
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_217
ci_cb_sysv_217:
    mov r11d, 217
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_218
ci_cb_sysv_218:
    mov r11d, 218
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_219
ci_cb_sysv_219:
    mov r11d, 219
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_220
ci_cb_sysv_220:
    mov r11d, 220
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_221
ci_cb_sysv_221:
    mov r11d, 221
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_222
ci_cb_sysv_222:
    mov r11d, 222
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_223
ci_cb_sysv_223:
    mov r11d, 223
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_224
ci_cb_sysv_224:
    mov r11d, 224
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_225
ci_cb_sysv_225:
    mov r11d, 225
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_226
ci_cb_sysv_226:
    mov r11d, 226
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_227
ci_cb_sysv_227:
    mov r11d, 227
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_228
ci_cb_sysv_228:
    mov r11d, 228
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_229
ci_cb_sysv_229:
    mov r11d, 229
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_230
ci_cb_sysv_230:
    mov r11d, 230
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_231
ci_cb_sysv_231:
    mov r11d, 231
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_232
ci_cb_sysv_232:
    mov r11d, 232
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_233
ci_cb_sysv_233:
    mov r11d, 233
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_234
ci_cb_sysv_234:
    mov r11d, 234
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_235
ci_cb_sysv_235:
    mov r11d, 235
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_236
ci_cb_sysv_236:
    mov r11d, 236
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_237
ci_cb_sysv_237:
    mov r11d, 237
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_238
ci_cb_sysv_238:
    mov r11d, 238
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_239
ci_cb_sysv_239:
    mov r11d, 239
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_240
ci_cb_sysv_240:
    mov r11d, 240
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_241
ci_cb_sysv_241:
    mov r11d, 241
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_242
ci_cb_sysv_242:
    mov r11d, 242
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_243
ci_cb_sysv_243:
    mov r11d, 243
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_244
ci_cb_sysv_244:
    mov r11d, 244
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_245
ci_cb_sysv_245:
    mov r11d, 245
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_246
ci_cb_sysv_246:
    mov r11d, 246
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_247
ci_cb_sysv_247:
    mov r11d, 247
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_248
ci_cb_sysv_248:
    mov r11d, 248
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_249
ci_cb_sysv_249:
    mov r11d, 249
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_250
ci_cb_sysv_250:
    mov r11d, 250
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_251
ci_cb_sysv_251:
    mov r11d, 251
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_252
ci_cb_sysv_252:
    mov r11d, 252
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_253
ci_cb_sysv_253:
    mov r11d, 253
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_254
ci_cb_sysv_254:
    mov r11d, 254
    jmp ci_cb_sysv_entry

.globl ci_cb_sysv_255
ci_cb_sysv_255:
    mov r11d, 255
    jmp ci_cb_sysv_entry

.section .data.rel.ro,"aw",@progbits
.p2align 3
.globl ci_cb_sysv_table
ci_cb_sysv_table:
    .quad ci_cb_sysv_0
    .quad ci_cb_sysv_1
    .quad ci_cb_sysv_2
    .quad ci_cb_sysv_3
    .quad ci_cb_sysv_4
    .quad ci_cb_sysv_5
    .quad ci_cb_sysv_6
    .quad ci_cb_sysv_7
    .quad ci_cb_sysv_8
    .quad ci_cb_sysv_9
    .quad ci_cb_sysv_10
    .quad ci_cb_sysv_11
    .quad ci_cb_sysv_12
    .quad ci_cb_sysv_13
    .quad ci_cb_sysv_14
    .quad ci_cb_sysv_15
    .quad ci_cb_sysv_16
    .quad ci_cb_sysv_17
    .quad ci_cb_sysv_18
    .quad ci_cb_sysv_19
    .quad ci_cb_sysv_20
    .quad ci_cb_sysv_21
    .quad ci_cb_sysv_22
    .quad ci_cb_sysv_23
    .quad ci_cb_sysv_24
    .quad ci_cb_sysv_25
    .quad ci_cb_sysv_26
    .quad ci_cb_sysv_27
    .quad ci_cb_sysv_28
    .quad ci_cb_sysv_29
    .quad ci_cb_sysv_30
    .quad ci_cb_sysv_31
    .quad ci_cb_sysv_32
    .quad ci_cb_sysv_33
    .quad ci_cb_sysv_34
    .quad ci_cb_sysv_35
    .quad ci_cb_sysv_36
    .quad ci_cb_sysv_37
    .quad ci_cb_sysv_38
    .quad ci_cb_sysv_39
    .quad ci_cb_sysv_40
    .quad ci_cb_sysv_41
    .quad ci_cb_sysv_42
    .quad ci_cb_sysv_43
    .quad ci_cb_sysv_44
    .quad ci_cb_sysv_45
    .quad ci_cb_sysv_46
    .quad ci_cb_sysv_47
    .quad ci_cb_sysv_48
    .quad ci_cb_sysv_49
    .quad ci_cb_sysv_50
    .quad ci_cb_sysv_51
    .quad ci_cb_sysv_52
    .quad ci_cb_sysv_53
    .quad ci_cb_sysv_54
    .quad ci_cb_sysv_55
    .quad ci_cb_sysv_56
    .quad ci_cb_sysv_57
    .quad ci_cb_sysv_58
    .quad ci_cb_sysv_59
    .quad ci_cb_sysv_60
    .quad ci_cb_sysv_61
    .quad ci_cb_sysv_62
    .quad ci_cb_sysv_63
    .quad ci_cb_sysv_64
    .quad ci_cb_sysv_65
    .quad ci_cb_sysv_66
    .quad ci_cb_sysv_67
    .quad ci_cb_sysv_68
    .quad ci_cb_sysv_69
    .quad ci_cb_sysv_70
    .quad ci_cb_sysv_71
    .quad ci_cb_sysv_72
    .quad ci_cb_sysv_73
    .quad ci_cb_sysv_74
    .quad ci_cb_sysv_75
    .quad ci_cb_sysv_76
    .quad ci_cb_sysv_77
    .quad ci_cb_sysv_78
    .quad ci_cb_sysv_79
    .quad ci_cb_sysv_80
    .quad ci_cb_sysv_81
    .quad ci_cb_sysv_82
    .quad ci_cb_sysv_83
    .quad ci_cb_sysv_84
    .quad ci_cb_sysv_85
    .quad ci_cb_sysv_86
    .quad ci_cb_sysv_87
    .quad ci_cb_sysv_88
    .quad ci_cb_sysv_89
    .quad ci_cb_sysv_90
    .quad ci_cb_sysv_91
    .quad ci_cb_sysv_92
    .quad ci_cb_sysv_93
    .quad ci_cb_sysv_94
    .quad ci_cb_sysv_95
    .quad ci_cb_sysv_96
    .quad ci_cb_sysv_97
    .quad ci_cb_sysv_98
    .quad ci_cb_sysv_99
    .quad ci_cb_sysv_100
    .quad ci_cb_sysv_101
    .quad ci_cb_sysv_102
    .quad ci_cb_sysv_103
    .quad ci_cb_sysv_104
    .quad ci_cb_sysv_105
    .quad ci_cb_sysv_106
    .quad ci_cb_sysv_107
    .quad ci_cb_sysv_108
    .quad ci_cb_sysv_109
    .quad ci_cb_sysv_110
    .quad ci_cb_sysv_111
    .quad ci_cb_sysv_112
    .quad ci_cb_sysv_113
    .quad ci_cb_sysv_114
    .quad ci_cb_sysv_115
    .quad ci_cb_sysv_116
    .quad ci_cb_sysv_117
    .quad ci_cb_sysv_118
    .quad ci_cb_sysv_119
    .quad ci_cb_sysv_120
    .quad ci_cb_sysv_121
    .quad ci_cb_sysv_122
    .quad ci_cb_sysv_123
    .quad ci_cb_sysv_124
    .quad ci_cb_sysv_125
    .quad ci_cb_sysv_126
    .quad ci_cb_sysv_127
    .quad ci_cb_sysv_128
    .quad ci_cb_sysv_129
    .quad ci_cb_sysv_130
    .quad ci_cb_sysv_131
    .quad ci_cb_sysv_132
    .quad ci_cb_sysv_133
    .quad ci_cb_sysv_134
    .quad ci_cb_sysv_135
    .quad ci_cb_sysv_136
    .quad ci_cb_sysv_137
    .quad ci_cb_sysv_138
    .quad ci_cb_sysv_139
    .quad ci_cb_sysv_140
    .quad ci_cb_sysv_141
    .quad ci_cb_sysv_142
    .quad ci_cb_sysv_143
    .quad ci_cb_sysv_144
    .quad ci_cb_sysv_145
    .quad ci_cb_sysv_146
    .quad ci_cb_sysv_147
    .quad ci_cb_sysv_148
    .quad ci_cb_sysv_149
    .quad ci_cb_sysv_150
    .quad ci_cb_sysv_151
    .quad ci_cb_sysv_152
    .quad ci_cb_sysv_153
    .quad ci_cb_sysv_154
    .quad ci_cb_sysv_155
    .quad ci_cb_sysv_156
    .quad ci_cb_sysv_157
    .quad ci_cb_sysv_158
    .quad ci_cb_sysv_159
    .quad ci_cb_sysv_160
    .quad ci_cb_sysv_161
    .quad ci_cb_sysv_162
    .quad ci_cb_sysv_163
    .quad ci_cb_sysv_164
    .quad ci_cb_sysv_165
    .quad ci_cb_sysv_166
    .quad ci_cb_sysv_167
    .quad ci_cb_sysv_168
    .quad ci_cb_sysv_169
    .quad ci_cb_sysv_170
    .quad ci_cb_sysv_171
    .quad ci_cb_sysv_172
    .quad ci_cb_sysv_173
    .quad ci_cb_sysv_174
    .quad ci_cb_sysv_175
    .quad ci_cb_sysv_176
    .quad ci_cb_sysv_177
    .quad ci_cb_sysv_178
    .quad ci_cb_sysv_179
    .quad ci_cb_sysv_180
    .quad ci_cb_sysv_181
    .quad ci_cb_sysv_182
    .quad ci_cb_sysv_183
    .quad ci_cb_sysv_184
    .quad ci_cb_sysv_185
    .quad ci_cb_sysv_186
    .quad ci_cb_sysv_187
    .quad ci_cb_sysv_188
    .quad ci_cb_sysv_189
    .quad ci_cb_sysv_190
    .quad ci_cb_sysv_191
    .quad ci_cb_sysv_192
    .quad ci_cb_sysv_193
    .quad ci_cb_sysv_194
    .quad ci_cb_sysv_195
    .quad ci_cb_sysv_196
    .quad ci_cb_sysv_197
    .quad ci_cb_sysv_198
    .quad ci_cb_sysv_199
    .quad ci_cb_sysv_200
    .quad ci_cb_sysv_201
    .quad ci_cb_sysv_202
    .quad ci_cb_sysv_203
    .quad ci_cb_sysv_204
    .quad ci_cb_sysv_205
    .quad ci_cb_sysv_206
    .quad ci_cb_sysv_207
    .quad ci_cb_sysv_208
    .quad ci_cb_sysv_209
    .quad ci_cb_sysv_210
    .quad ci_cb_sysv_211
    .quad ci_cb_sysv_212
    .quad ci_cb_sysv_213
    .quad ci_cb_sysv_214
    .quad ci_cb_sysv_215
    .quad ci_cb_sysv_216
    .quad ci_cb_sysv_217
    .quad ci_cb_sysv_218
    .quad ci_cb_sysv_219
    .quad ci_cb_sysv_220
    .quad ci_cb_sysv_221
    .quad ci_cb_sysv_222
    .quad ci_cb_sysv_223
    .quad ci_cb_sysv_224
    .quad ci_cb_sysv_225
    .quad ci_cb_sysv_226
    .quad ci_cb_sysv_227
    .quad ci_cb_sysv_228
    .quad ci_cb_sysv_229
    .quad ci_cb_sysv_230
    .quad ci_cb_sysv_231
    .quad ci_cb_sysv_232
    .quad ci_cb_sysv_233
    .quad ci_cb_sysv_234
    .quad ci_cb_sysv_235
    .quad ci_cb_sysv_236
    .quad ci_cb_sysv_237
    .quad ci_cb_sysv_238
    .quad ci_cb_sysv_239
    .quad ci_cb_sysv_240
    .quad ci_cb_sysv_241
    .quad ci_cb_sysv_242
    .quad ci_cb_sysv_243
    .quad ci_cb_sysv_244
    .quad ci_cb_sysv_245
    .quad ci_cb_sysv_246
    .quad ci_cb_sysv_247
    .quad ci_cb_sysv_248
    .quad ci_cb_sysv_249
    .quad ci_cb_sysv_250
    .quad ci_cb_sysv_251
    .quad ci_cb_sysv_252
    .quad ci_cb_sysv_253
    .quad ci_cb_sysv_254
    .quad ci_cb_sysv_255

.section .note.GNU-stack,"",@progbits
