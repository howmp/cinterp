.intel_syntax noprefix

.equ CB_SLOT, 0
.equ CB_GPR, 8
.equ CB_XMM, 40
.equ CB_STACK, 104
.equ CB_RET_RAX, 112
.equ CB_RET_RDX, 120
.equ CB_RET_XMM0, 128
.equ CB_RET_XMM1, 144
.equ CB_SAVED_XMM, 160

.text

ci_cb_win64_entry:
    push rbp
    mov rbp, rsp
    sub rsp, 352
    lea r10, [rsp + 32]
    mov [r10 + CB_SLOT], r11

    mov [r10 + CB_GPR + 0], rcx
    mov [r10 + CB_GPR + 8], rdx
    mov [r10 + CB_GPR + 16], r8
    mov [r10 + CB_GPR + 24], r9
    movups [r10 + CB_XMM + 0], xmm0
    movups [r10 + CB_XMM + 16], xmm1
    movups [r10 + CB_XMM + 32], xmm2
    movups [r10 + CB_XMM + 48], xmm3
    lea rax, [rbp + 48]
    mov [r10 + CB_STACK], rax
    xor eax, eax
    mov [r10 + CB_RET_RAX], rax
    mov [r10 + CB_RET_RDX], rax
    movups [r10 + CB_RET_XMM0], xmm0
    movups [r10 + CB_RET_XMM1], xmm0
    movups [r10 + CB_SAVED_XMM + 0], xmm6
    movups [r10 + CB_SAVED_XMM + 16], xmm7
    movups [r10 + CB_SAVED_XMM + 32], xmm8
    movups [r10 + CB_SAVED_XMM + 48], xmm9
    movups [r10 + CB_SAVED_XMM + 64], xmm10
    movups [r10 + CB_SAVED_XMM + 80], xmm11
    movups [r10 + CB_SAVED_XMM + 96], xmm12
    movups [r10 + CB_SAVED_XMM + 112], xmm13
    movups [r10 + CB_SAVED_XMM + 128], xmm14
    movups [r10 + CB_SAVED_XMM + 144], xmm15
    mov rcx, r11
    mov rdx, r10
    call ci_callback_dispatch
    lea r10, [rsp + 32]
    mov rax, [r10 + CB_RET_RAX]
    mov rdx, [r10 + CB_RET_RDX]
    movups xmm0, [r10 + CB_RET_XMM0]
    movups xmm1, [r10 + CB_RET_XMM1]
    movups xmm6, [r10 + CB_SAVED_XMM + 0]
    movups xmm7, [r10 + CB_SAVED_XMM + 16]
    movups xmm8, [r10 + CB_SAVED_XMM + 32]
    movups xmm9, [r10 + CB_SAVED_XMM + 48]
    movups xmm10, [r10 + CB_SAVED_XMM + 64]
    movups xmm11, [r10 + CB_SAVED_XMM + 80]
    movups xmm12, [r10 + CB_SAVED_XMM + 96]
    movups xmm13, [r10 + CB_SAVED_XMM + 112]
    movups xmm14, [r10 + CB_SAVED_XMM + 128]
    movups xmm15, [r10 + CB_SAVED_XMM + 144]
    add rsp, 352
    pop rbp
    ret

.p2align 4
.globl ci_cb_win64_0
ci_cb_win64_0:
    mov r11d, 0
    jmp ci_cb_win64_entry
.globl ci_cb_win64_1
ci_cb_win64_1:
    mov r11d, 1
    jmp ci_cb_win64_entry
.globl ci_cb_win64_2
ci_cb_win64_2:
    mov r11d, 2
    jmp ci_cb_win64_entry
.globl ci_cb_win64_3
ci_cb_win64_3:
    mov r11d, 3
    jmp ci_cb_win64_entry
.globl ci_cb_win64_4
ci_cb_win64_4:
    mov r11d, 4
    jmp ci_cb_win64_entry
.globl ci_cb_win64_5
ci_cb_win64_5:
    mov r11d, 5
    jmp ci_cb_win64_entry
.globl ci_cb_win64_6
ci_cb_win64_6:
    mov r11d, 6
    jmp ci_cb_win64_entry
.globl ci_cb_win64_7
ci_cb_win64_7:
    mov r11d, 7
    jmp ci_cb_win64_entry
.globl ci_cb_win64_8
ci_cb_win64_8:
    mov r11d, 8
    jmp ci_cb_win64_entry
.globl ci_cb_win64_9
ci_cb_win64_9:
    mov r11d, 9
    jmp ci_cb_win64_entry
.globl ci_cb_win64_10
ci_cb_win64_10:
    mov r11d, 10
    jmp ci_cb_win64_entry
.globl ci_cb_win64_11
ci_cb_win64_11:
    mov r11d, 11
    jmp ci_cb_win64_entry
.globl ci_cb_win64_12
ci_cb_win64_12:
    mov r11d, 12
    jmp ci_cb_win64_entry
.globl ci_cb_win64_13
ci_cb_win64_13:
    mov r11d, 13
    jmp ci_cb_win64_entry
.globl ci_cb_win64_14
ci_cb_win64_14:
    mov r11d, 14
    jmp ci_cb_win64_entry
.globl ci_cb_win64_15
ci_cb_win64_15:
    mov r11d, 15
    jmp ci_cb_win64_entry
.globl ci_cb_win64_16
ci_cb_win64_16:
    mov r11d, 16
    jmp ci_cb_win64_entry
.globl ci_cb_win64_17
ci_cb_win64_17:
    mov r11d, 17
    jmp ci_cb_win64_entry
.globl ci_cb_win64_18
ci_cb_win64_18:
    mov r11d, 18
    jmp ci_cb_win64_entry
.globl ci_cb_win64_19
ci_cb_win64_19:
    mov r11d, 19
    jmp ci_cb_win64_entry
.globl ci_cb_win64_20
ci_cb_win64_20:
    mov r11d, 20
    jmp ci_cb_win64_entry
.globl ci_cb_win64_21
ci_cb_win64_21:
    mov r11d, 21
    jmp ci_cb_win64_entry
.globl ci_cb_win64_22
ci_cb_win64_22:
    mov r11d, 22
    jmp ci_cb_win64_entry
.globl ci_cb_win64_23
ci_cb_win64_23:
    mov r11d, 23
    jmp ci_cb_win64_entry
.globl ci_cb_win64_24
ci_cb_win64_24:
    mov r11d, 24
    jmp ci_cb_win64_entry
.globl ci_cb_win64_25
ci_cb_win64_25:
    mov r11d, 25
    jmp ci_cb_win64_entry
.globl ci_cb_win64_26
ci_cb_win64_26:
    mov r11d, 26
    jmp ci_cb_win64_entry
.globl ci_cb_win64_27
ci_cb_win64_27:
    mov r11d, 27
    jmp ci_cb_win64_entry
.globl ci_cb_win64_28
ci_cb_win64_28:
    mov r11d, 28
    jmp ci_cb_win64_entry
.globl ci_cb_win64_29
ci_cb_win64_29:
    mov r11d, 29
    jmp ci_cb_win64_entry
.globl ci_cb_win64_30
ci_cb_win64_30:
    mov r11d, 30
    jmp ci_cb_win64_entry
.globl ci_cb_win64_31
ci_cb_win64_31:
    mov r11d, 31
    jmp ci_cb_win64_entry
.globl ci_cb_win64_32
ci_cb_win64_32:
    mov r11d, 32
    jmp ci_cb_win64_entry
.globl ci_cb_win64_33
ci_cb_win64_33:
    mov r11d, 33
    jmp ci_cb_win64_entry
.globl ci_cb_win64_34
ci_cb_win64_34:
    mov r11d, 34
    jmp ci_cb_win64_entry
.globl ci_cb_win64_35
ci_cb_win64_35:
    mov r11d, 35
    jmp ci_cb_win64_entry
.globl ci_cb_win64_36
ci_cb_win64_36:
    mov r11d, 36
    jmp ci_cb_win64_entry
.globl ci_cb_win64_37
ci_cb_win64_37:
    mov r11d, 37
    jmp ci_cb_win64_entry
.globl ci_cb_win64_38
ci_cb_win64_38:
    mov r11d, 38
    jmp ci_cb_win64_entry
.globl ci_cb_win64_39
ci_cb_win64_39:
    mov r11d, 39
    jmp ci_cb_win64_entry
.globl ci_cb_win64_40
ci_cb_win64_40:
    mov r11d, 40
    jmp ci_cb_win64_entry
.globl ci_cb_win64_41
ci_cb_win64_41:
    mov r11d, 41
    jmp ci_cb_win64_entry
.globl ci_cb_win64_42
ci_cb_win64_42:
    mov r11d, 42
    jmp ci_cb_win64_entry
.globl ci_cb_win64_43
ci_cb_win64_43:
    mov r11d, 43
    jmp ci_cb_win64_entry
.globl ci_cb_win64_44
ci_cb_win64_44:
    mov r11d, 44
    jmp ci_cb_win64_entry
.globl ci_cb_win64_45
ci_cb_win64_45:
    mov r11d, 45
    jmp ci_cb_win64_entry
.globl ci_cb_win64_46
ci_cb_win64_46:
    mov r11d, 46
    jmp ci_cb_win64_entry
.globl ci_cb_win64_47
ci_cb_win64_47:
    mov r11d, 47
    jmp ci_cb_win64_entry
.globl ci_cb_win64_48
ci_cb_win64_48:
    mov r11d, 48
    jmp ci_cb_win64_entry
.globl ci_cb_win64_49
ci_cb_win64_49:
    mov r11d, 49
    jmp ci_cb_win64_entry
.globl ci_cb_win64_50
ci_cb_win64_50:
    mov r11d, 50
    jmp ci_cb_win64_entry
.globl ci_cb_win64_51
ci_cb_win64_51:
    mov r11d, 51
    jmp ci_cb_win64_entry
.globl ci_cb_win64_52
ci_cb_win64_52:
    mov r11d, 52
    jmp ci_cb_win64_entry
.globl ci_cb_win64_53
ci_cb_win64_53:
    mov r11d, 53
    jmp ci_cb_win64_entry
.globl ci_cb_win64_54
ci_cb_win64_54:
    mov r11d, 54
    jmp ci_cb_win64_entry
.globl ci_cb_win64_55
ci_cb_win64_55:
    mov r11d, 55
    jmp ci_cb_win64_entry
.globl ci_cb_win64_56
ci_cb_win64_56:
    mov r11d, 56
    jmp ci_cb_win64_entry
.globl ci_cb_win64_57
ci_cb_win64_57:
    mov r11d, 57
    jmp ci_cb_win64_entry
.globl ci_cb_win64_58
ci_cb_win64_58:
    mov r11d, 58
    jmp ci_cb_win64_entry
.globl ci_cb_win64_59
ci_cb_win64_59:
    mov r11d, 59
    jmp ci_cb_win64_entry
.globl ci_cb_win64_60
ci_cb_win64_60:
    mov r11d, 60
    jmp ci_cb_win64_entry
.globl ci_cb_win64_61
ci_cb_win64_61:
    mov r11d, 61
    jmp ci_cb_win64_entry
.globl ci_cb_win64_62
ci_cb_win64_62:
    mov r11d, 62
    jmp ci_cb_win64_entry
.globl ci_cb_win64_63
ci_cb_win64_63:
    mov r11d, 63
    jmp ci_cb_win64_entry
.globl ci_cb_win64_64
ci_cb_win64_64:
    mov r11d, 64
    jmp ci_cb_win64_entry
.globl ci_cb_win64_65
ci_cb_win64_65:
    mov r11d, 65
    jmp ci_cb_win64_entry
.globl ci_cb_win64_66
ci_cb_win64_66:
    mov r11d, 66
    jmp ci_cb_win64_entry
.globl ci_cb_win64_67
ci_cb_win64_67:
    mov r11d, 67
    jmp ci_cb_win64_entry
.globl ci_cb_win64_68
ci_cb_win64_68:
    mov r11d, 68
    jmp ci_cb_win64_entry
.globl ci_cb_win64_69
ci_cb_win64_69:
    mov r11d, 69
    jmp ci_cb_win64_entry
.globl ci_cb_win64_70
ci_cb_win64_70:
    mov r11d, 70
    jmp ci_cb_win64_entry
.globl ci_cb_win64_71
ci_cb_win64_71:
    mov r11d, 71
    jmp ci_cb_win64_entry
.globl ci_cb_win64_72
ci_cb_win64_72:
    mov r11d, 72
    jmp ci_cb_win64_entry
.globl ci_cb_win64_73
ci_cb_win64_73:
    mov r11d, 73
    jmp ci_cb_win64_entry
.globl ci_cb_win64_74
ci_cb_win64_74:
    mov r11d, 74
    jmp ci_cb_win64_entry
.globl ci_cb_win64_75
ci_cb_win64_75:
    mov r11d, 75
    jmp ci_cb_win64_entry
.globl ci_cb_win64_76
ci_cb_win64_76:
    mov r11d, 76
    jmp ci_cb_win64_entry
.globl ci_cb_win64_77
ci_cb_win64_77:
    mov r11d, 77
    jmp ci_cb_win64_entry
.globl ci_cb_win64_78
ci_cb_win64_78:
    mov r11d, 78
    jmp ci_cb_win64_entry
.globl ci_cb_win64_79
ci_cb_win64_79:
    mov r11d, 79
    jmp ci_cb_win64_entry
.globl ci_cb_win64_80
ci_cb_win64_80:
    mov r11d, 80
    jmp ci_cb_win64_entry
.globl ci_cb_win64_81
ci_cb_win64_81:
    mov r11d, 81
    jmp ci_cb_win64_entry
.globl ci_cb_win64_82
ci_cb_win64_82:
    mov r11d, 82
    jmp ci_cb_win64_entry
.globl ci_cb_win64_83
ci_cb_win64_83:
    mov r11d, 83
    jmp ci_cb_win64_entry
.globl ci_cb_win64_84
ci_cb_win64_84:
    mov r11d, 84
    jmp ci_cb_win64_entry
.globl ci_cb_win64_85
ci_cb_win64_85:
    mov r11d, 85
    jmp ci_cb_win64_entry
.globl ci_cb_win64_86
ci_cb_win64_86:
    mov r11d, 86
    jmp ci_cb_win64_entry
.globl ci_cb_win64_87
ci_cb_win64_87:
    mov r11d, 87
    jmp ci_cb_win64_entry
.globl ci_cb_win64_88
ci_cb_win64_88:
    mov r11d, 88
    jmp ci_cb_win64_entry
.globl ci_cb_win64_89
ci_cb_win64_89:
    mov r11d, 89
    jmp ci_cb_win64_entry
.globl ci_cb_win64_90
ci_cb_win64_90:
    mov r11d, 90
    jmp ci_cb_win64_entry
.globl ci_cb_win64_91
ci_cb_win64_91:
    mov r11d, 91
    jmp ci_cb_win64_entry
.globl ci_cb_win64_92
ci_cb_win64_92:
    mov r11d, 92
    jmp ci_cb_win64_entry
.globl ci_cb_win64_93
ci_cb_win64_93:
    mov r11d, 93
    jmp ci_cb_win64_entry
.globl ci_cb_win64_94
ci_cb_win64_94:
    mov r11d, 94
    jmp ci_cb_win64_entry
.globl ci_cb_win64_95
ci_cb_win64_95:
    mov r11d, 95
    jmp ci_cb_win64_entry
.globl ci_cb_win64_96
ci_cb_win64_96:
    mov r11d, 96
    jmp ci_cb_win64_entry
.globl ci_cb_win64_97
ci_cb_win64_97:
    mov r11d, 97
    jmp ci_cb_win64_entry
.globl ci_cb_win64_98
ci_cb_win64_98:
    mov r11d, 98
    jmp ci_cb_win64_entry
.globl ci_cb_win64_99
ci_cb_win64_99:
    mov r11d, 99
    jmp ci_cb_win64_entry
.globl ci_cb_win64_100
ci_cb_win64_100:
    mov r11d, 100
    jmp ci_cb_win64_entry
.globl ci_cb_win64_101
ci_cb_win64_101:
    mov r11d, 101
    jmp ci_cb_win64_entry
.globl ci_cb_win64_102
ci_cb_win64_102:
    mov r11d, 102
    jmp ci_cb_win64_entry
.globl ci_cb_win64_103
ci_cb_win64_103:
    mov r11d, 103
    jmp ci_cb_win64_entry
.globl ci_cb_win64_104
ci_cb_win64_104:
    mov r11d, 104
    jmp ci_cb_win64_entry
.globl ci_cb_win64_105
ci_cb_win64_105:
    mov r11d, 105
    jmp ci_cb_win64_entry
.globl ci_cb_win64_106
ci_cb_win64_106:
    mov r11d, 106
    jmp ci_cb_win64_entry
.globl ci_cb_win64_107
ci_cb_win64_107:
    mov r11d, 107
    jmp ci_cb_win64_entry
.globl ci_cb_win64_108
ci_cb_win64_108:
    mov r11d, 108
    jmp ci_cb_win64_entry
.globl ci_cb_win64_109
ci_cb_win64_109:
    mov r11d, 109
    jmp ci_cb_win64_entry
.globl ci_cb_win64_110
ci_cb_win64_110:
    mov r11d, 110
    jmp ci_cb_win64_entry
.globl ci_cb_win64_111
ci_cb_win64_111:
    mov r11d, 111
    jmp ci_cb_win64_entry
.globl ci_cb_win64_112
ci_cb_win64_112:
    mov r11d, 112
    jmp ci_cb_win64_entry
.globl ci_cb_win64_113
ci_cb_win64_113:
    mov r11d, 113
    jmp ci_cb_win64_entry
.globl ci_cb_win64_114
ci_cb_win64_114:
    mov r11d, 114
    jmp ci_cb_win64_entry
.globl ci_cb_win64_115
ci_cb_win64_115:
    mov r11d, 115
    jmp ci_cb_win64_entry
.globl ci_cb_win64_116
ci_cb_win64_116:
    mov r11d, 116
    jmp ci_cb_win64_entry
.globl ci_cb_win64_117
ci_cb_win64_117:
    mov r11d, 117
    jmp ci_cb_win64_entry
.globl ci_cb_win64_118
ci_cb_win64_118:
    mov r11d, 118
    jmp ci_cb_win64_entry
.globl ci_cb_win64_119
ci_cb_win64_119:
    mov r11d, 119
    jmp ci_cb_win64_entry
.globl ci_cb_win64_120
ci_cb_win64_120:
    mov r11d, 120
    jmp ci_cb_win64_entry
.globl ci_cb_win64_121
ci_cb_win64_121:
    mov r11d, 121
    jmp ci_cb_win64_entry
.globl ci_cb_win64_122
ci_cb_win64_122:
    mov r11d, 122
    jmp ci_cb_win64_entry
.globl ci_cb_win64_123
ci_cb_win64_123:
    mov r11d, 123
    jmp ci_cb_win64_entry
.globl ci_cb_win64_124
ci_cb_win64_124:
    mov r11d, 124
    jmp ci_cb_win64_entry
.globl ci_cb_win64_125
ci_cb_win64_125:
    mov r11d, 125
    jmp ci_cb_win64_entry
.globl ci_cb_win64_126
ci_cb_win64_126:
    mov r11d, 126
    jmp ci_cb_win64_entry
.globl ci_cb_win64_127
ci_cb_win64_127:
    mov r11d, 127
    jmp ci_cb_win64_entry
.globl ci_cb_win64_128
ci_cb_win64_128:
    mov r11d, 128
    jmp ci_cb_win64_entry
.globl ci_cb_win64_129
ci_cb_win64_129:
    mov r11d, 129
    jmp ci_cb_win64_entry
.globl ci_cb_win64_130
ci_cb_win64_130:
    mov r11d, 130
    jmp ci_cb_win64_entry
.globl ci_cb_win64_131
ci_cb_win64_131:
    mov r11d, 131
    jmp ci_cb_win64_entry
.globl ci_cb_win64_132
ci_cb_win64_132:
    mov r11d, 132
    jmp ci_cb_win64_entry
.globl ci_cb_win64_133
ci_cb_win64_133:
    mov r11d, 133
    jmp ci_cb_win64_entry
.globl ci_cb_win64_134
ci_cb_win64_134:
    mov r11d, 134
    jmp ci_cb_win64_entry
.globl ci_cb_win64_135
ci_cb_win64_135:
    mov r11d, 135
    jmp ci_cb_win64_entry
.globl ci_cb_win64_136
ci_cb_win64_136:
    mov r11d, 136
    jmp ci_cb_win64_entry
.globl ci_cb_win64_137
ci_cb_win64_137:
    mov r11d, 137
    jmp ci_cb_win64_entry
.globl ci_cb_win64_138
ci_cb_win64_138:
    mov r11d, 138
    jmp ci_cb_win64_entry
.globl ci_cb_win64_139
ci_cb_win64_139:
    mov r11d, 139
    jmp ci_cb_win64_entry
.globl ci_cb_win64_140
ci_cb_win64_140:
    mov r11d, 140
    jmp ci_cb_win64_entry
.globl ci_cb_win64_141
ci_cb_win64_141:
    mov r11d, 141
    jmp ci_cb_win64_entry
.globl ci_cb_win64_142
ci_cb_win64_142:
    mov r11d, 142
    jmp ci_cb_win64_entry
.globl ci_cb_win64_143
ci_cb_win64_143:
    mov r11d, 143
    jmp ci_cb_win64_entry
.globl ci_cb_win64_144
ci_cb_win64_144:
    mov r11d, 144
    jmp ci_cb_win64_entry
.globl ci_cb_win64_145
ci_cb_win64_145:
    mov r11d, 145
    jmp ci_cb_win64_entry
.globl ci_cb_win64_146
ci_cb_win64_146:
    mov r11d, 146
    jmp ci_cb_win64_entry
.globl ci_cb_win64_147
ci_cb_win64_147:
    mov r11d, 147
    jmp ci_cb_win64_entry
.globl ci_cb_win64_148
ci_cb_win64_148:
    mov r11d, 148
    jmp ci_cb_win64_entry
.globl ci_cb_win64_149
ci_cb_win64_149:
    mov r11d, 149
    jmp ci_cb_win64_entry
.globl ci_cb_win64_150
ci_cb_win64_150:
    mov r11d, 150
    jmp ci_cb_win64_entry
.globl ci_cb_win64_151
ci_cb_win64_151:
    mov r11d, 151
    jmp ci_cb_win64_entry
.globl ci_cb_win64_152
ci_cb_win64_152:
    mov r11d, 152
    jmp ci_cb_win64_entry
.globl ci_cb_win64_153
ci_cb_win64_153:
    mov r11d, 153
    jmp ci_cb_win64_entry
.globl ci_cb_win64_154
ci_cb_win64_154:
    mov r11d, 154
    jmp ci_cb_win64_entry
.globl ci_cb_win64_155
ci_cb_win64_155:
    mov r11d, 155
    jmp ci_cb_win64_entry
.globl ci_cb_win64_156
ci_cb_win64_156:
    mov r11d, 156
    jmp ci_cb_win64_entry
.globl ci_cb_win64_157
ci_cb_win64_157:
    mov r11d, 157
    jmp ci_cb_win64_entry
.globl ci_cb_win64_158
ci_cb_win64_158:
    mov r11d, 158
    jmp ci_cb_win64_entry
.globl ci_cb_win64_159
ci_cb_win64_159:
    mov r11d, 159
    jmp ci_cb_win64_entry
.globl ci_cb_win64_160
ci_cb_win64_160:
    mov r11d, 160
    jmp ci_cb_win64_entry
.globl ci_cb_win64_161
ci_cb_win64_161:
    mov r11d, 161
    jmp ci_cb_win64_entry
.globl ci_cb_win64_162
ci_cb_win64_162:
    mov r11d, 162
    jmp ci_cb_win64_entry
.globl ci_cb_win64_163
ci_cb_win64_163:
    mov r11d, 163
    jmp ci_cb_win64_entry
.globl ci_cb_win64_164
ci_cb_win64_164:
    mov r11d, 164
    jmp ci_cb_win64_entry
.globl ci_cb_win64_165
ci_cb_win64_165:
    mov r11d, 165
    jmp ci_cb_win64_entry
.globl ci_cb_win64_166
ci_cb_win64_166:
    mov r11d, 166
    jmp ci_cb_win64_entry
.globl ci_cb_win64_167
ci_cb_win64_167:
    mov r11d, 167
    jmp ci_cb_win64_entry
.globl ci_cb_win64_168
ci_cb_win64_168:
    mov r11d, 168
    jmp ci_cb_win64_entry
.globl ci_cb_win64_169
ci_cb_win64_169:
    mov r11d, 169
    jmp ci_cb_win64_entry
.globl ci_cb_win64_170
ci_cb_win64_170:
    mov r11d, 170
    jmp ci_cb_win64_entry
.globl ci_cb_win64_171
ci_cb_win64_171:
    mov r11d, 171
    jmp ci_cb_win64_entry
.globl ci_cb_win64_172
ci_cb_win64_172:
    mov r11d, 172
    jmp ci_cb_win64_entry
.globl ci_cb_win64_173
ci_cb_win64_173:
    mov r11d, 173
    jmp ci_cb_win64_entry
.globl ci_cb_win64_174
ci_cb_win64_174:
    mov r11d, 174
    jmp ci_cb_win64_entry
.globl ci_cb_win64_175
ci_cb_win64_175:
    mov r11d, 175
    jmp ci_cb_win64_entry
.globl ci_cb_win64_176
ci_cb_win64_176:
    mov r11d, 176
    jmp ci_cb_win64_entry
.globl ci_cb_win64_177
ci_cb_win64_177:
    mov r11d, 177
    jmp ci_cb_win64_entry
.globl ci_cb_win64_178
ci_cb_win64_178:
    mov r11d, 178
    jmp ci_cb_win64_entry
.globl ci_cb_win64_179
ci_cb_win64_179:
    mov r11d, 179
    jmp ci_cb_win64_entry
.globl ci_cb_win64_180
ci_cb_win64_180:
    mov r11d, 180
    jmp ci_cb_win64_entry
.globl ci_cb_win64_181
ci_cb_win64_181:
    mov r11d, 181
    jmp ci_cb_win64_entry
.globl ci_cb_win64_182
ci_cb_win64_182:
    mov r11d, 182
    jmp ci_cb_win64_entry
.globl ci_cb_win64_183
ci_cb_win64_183:
    mov r11d, 183
    jmp ci_cb_win64_entry
.globl ci_cb_win64_184
ci_cb_win64_184:
    mov r11d, 184
    jmp ci_cb_win64_entry
.globl ci_cb_win64_185
ci_cb_win64_185:
    mov r11d, 185
    jmp ci_cb_win64_entry
.globl ci_cb_win64_186
ci_cb_win64_186:
    mov r11d, 186
    jmp ci_cb_win64_entry
.globl ci_cb_win64_187
ci_cb_win64_187:
    mov r11d, 187
    jmp ci_cb_win64_entry
.globl ci_cb_win64_188
ci_cb_win64_188:
    mov r11d, 188
    jmp ci_cb_win64_entry
.globl ci_cb_win64_189
ci_cb_win64_189:
    mov r11d, 189
    jmp ci_cb_win64_entry
.globl ci_cb_win64_190
ci_cb_win64_190:
    mov r11d, 190
    jmp ci_cb_win64_entry
.globl ci_cb_win64_191
ci_cb_win64_191:
    mov r11d, 191
    jmp ci_cb_win64_entry
.globl ci_cb_win64_192
ci_cb_win64_192:
    mov r11d, 192
    jmp ci_cb_win64_entry
.globl ci_cb_win64_193
ci_cb_win64_193:
    mov r11d, 193
    jmp ci_cb_win64_entry
.globl ci_cb_win64_194
ci_cb_win64_194:
    mov r11d, 194
    jmp ci_cb_win64_entry
.globl ci_cb_win64_195
ci_cb_win64_195:
    mov r11d, 195
    jmp ci_cb_win64_entry
.globl ci_cb_win64_196
ci_cb_win64_196:
    mov r11d, 196
    jmp ci_cb_win64_entry
.globl ci_cb_win64_197
ci_cb_win64_197:
    mov r11d, 197
    jmp ci_cb_win64_entry
.globl ci_cb_win64_198
ci_cb_win64_198:
    mov r11d, 198
    jmp ci_cb_win64_entry
.globl ci_cb_win64_199
ci_cb_win64_199:
    mov r11d, 199
    jmp ci_cb_win64_entry
.globl ci_cb_win64_200
ci_cb_win64_200:
    mov r11d, 200
    jmp ci_cb_win64_entry
.globl ci_cb_win64_201
ci_cb_win64_201:
    mov r11d, 201
    jmp ci_cb_win64_entry
.globl ci_cb_win64_202
ci_cb_win64_202:
    mov r11d, 202
    jmp ci_cb_win64_entry
.globl ci_cb_win64_203
ci_cb_win64_203:
    mov r11d, 203
    jmp ci_cb_win64_entry
.globl ci_cb_win64_204
ci_cb_win64_204:
    mov r11d, 204
    jmp ci_cb_win64_entry
.globl ci_cb_win64_205
ci_cb_win64_205:
    mov r11d, 205
    jmp ci_cb_win64_entry
.globl ci_cb_win64_206
ci_cb_win64_206:
    mov r11d, 206
    jmp ci_cb_win64_entry
.globl ci_cb_win64_207
ci_cb_win64_207:
    mov r11d, 207
    jmp ci_cb_win64_entry
.globl ci_cb_win64_208
ci_cb_win64_208:
    mov r11d, 208
    jmp ci_cb_win64_entry
.globl ci_cb_win64_209
ci_cb_win64_209:
    mov r11d, 209
    jmp ci_cb_win64_entry
.globl ci_cb_win64_210
ci_cb_win64_210:
    mov r11d, 210
    jmp ci_cb_win64_entry
.globl ci_cb_win64_211
ci_cb_win64_211:
    mov r11d, 211
    jmp ci_cb_win64_entry
.globl ci_cb_win64_212
ci_cb_win64_212:
    mov r11d, 212
    jmp ci_cb_win64_entry
.globl ci_cb_win64_213
ci_cb_win64_213:
    mov r11d, 213
    jmp ci_cb_win64_entry
.globl ci_cb_win64_214
ci_cb_win64_214:
    mov r11d, 214
    jmp ci_cb_win64_entry
.globl ci_cb_win64_215
ci_cb_win64_215:
    mov r11d, 215
    jmp ci_cb_win64_entry
.globl ci_cb_win64_216
ci_cb_win64_216:
    mov r11d, 216
    jmp ci_cb_win64_entry
.globl ci_cb_win64_217
ci_cb_win64_217:
    mov r11d, 217
    jmp ci_cb_win64_entry
.globl ci_cb_win64_218
ci_cb_win64_218:
    mov r11d, 218
    jmp ci_cb_win64_entry
.globl ci_cb_win64_219
ci_cb_win64_219:
    mov r11d, 219
    jmp ci_cb_win64_entry
.globl ci_cb_win64_220
ci_cb_win64_220:
    mov r11d, 220
    jmp ci_cb_win64_entry
.globl ci_cb_win64_221
ci_cb_win64_221:
    mov r11d, 221
    jmp ci_cb_win64_entry
.globl ci_cb_win64_222
ci_cb_win64_222:
    mov r11d, 222
    jmp ci_cb_win64_entry
.globl ci_cb_win64_223
ci_cb_win64_223:
    mov r11d, 223
    jmp ci_cb_win64_entry
.globl ci_cb_win64_224
ci_cb_win64_224:
    mov r11d, 224
    jmp ci_cb_win64_entry
.globl ci_cb_win64_225
ci_cb_win64_225:
    mov r11d, 225
    jmp ci_cb_win64_entry
.globl ci_cb_win64_226
ci_cb_win64_226:
    mov r11d, 226
    jmp ci_cb_win64_entry
.globl ci_cb_win64_227
ci_cb_win64_227:
    mov r11d, 227
    jmp ci_cb_win64_entry
.globl ci_cb_win64_228
ci_cb_win64_228:
    mov r11d, 228
    jmp ci_cb_win64_entry
.globl ci_cb_win64_229
ci_cb_win64_229:
    mov r11d, 229
    jmp ci_cb_win64_entry
.globl ci_cb_win64_230
ci_cb_win64_230:
    mov r11d, 230
    jmp ci_cb_win64_entry
.globl ci_cb_win64_231
ci_cb_win64_231:
    mov r11d, 231
    jmp ci_cb_win64_entry
.globl ci_cb_win64_232
ci_cb_win64_232:
    mov r11d, 232
    jmp ci_cb_win64_entry
.globl ci_cb_win64_233
ci_cb_win64_233:
    mov r11d, 233
    jmp ci_cb_win64_entry
.globl ci_cb_win64_234
ci_cb_win64_234:
    mov r11d, 234
    jmp ci_cb_win64_entry
.globl ci_cb_win64_235
ci_cb_win64_235:
    mov r11d, 235
    jmp ci_cb_win64_entry
.globl ci_cb_win64_236
ci_cb_win64_236:
    mov r11d, 236
    jmp ci_cb_win64_entry
.globl ci_cb_win64_237
ci_cb_win64_237:
    mov r11d, 237
    jmp ci_cb_win64_entry
.globl ci_cb_win64_238
ci_cb_win64_238:
    mov r11d, 238
    jmp ci_cb_win64_entry
.globl ci_cb_win64_239
ci_cb_win64_239:
    mov r11d, 239
    jmp ci_cb_win64_entry
.globl ci_cb_win64_240
ci_cb_win64_240:
    mov r11d, 240
    jmp ci_cb_win64_entry
.globl ci_cb_win64_241
ci_cb_win64_241:
    mov r11d, 241
    jmp ci_cb_win64_entry
.globl ci_cb_win64_242
ci_cb_win64_242:
    mov r11d, 242
    jmp ci_cb_win64_entry
.globl ci_cb_win64_243
ci_cb_win64_243:
    mov r11d, 243
    jmp ci_cb_win64_entry
.globl ci_cb_win64_244
ci_cb_win64_244:
    mov r11d, 244
    jmp ci_cb_win64_entry
.globl ci_cb_win64_245
ci_cb_win64_245:
    mov r11d, 245
    jmp ci_cb_win64_entry
.globl ci_cb_win64_246
ci_cb_win64_246:
    mov r11d, 246
    jmp ci_cb_win64_entry
.globl ci_cb_win64_247
ci_cb_win64_247:
    mov r11d, 247
    jmp ci_cb_win64_entry
.globl ci_cb_win64_248
ci_cb_win64_248:
    mov r11d, 248
    jmp ci_cb_win64_entry
.globl ci_cb_win64_249
ci_cb_win64_249:
    mov r11d, 249
    jmp ci_cb_win64_entry
.globl ci_cb_win64_250
ci_cb_win64_250:
    mov r11d, 250
    jmp ci_cb_win64_entry
.globl ci_cb_win64_251
ci_cb_win64_251:
    mov r11d, 251
    jmp ci_cb_win64_entry
.globl ci_cb_win64_252
ci_cb_win64_252:
    mov r11d, 252
    jmp ci_cb_win64_entry
.globl ci_cb_win64_253
ci_cb_win64_253:
    mov r11d, 253
    jmp ci_cb_win64_entry
.globl ci_cb_win64_254
ci_cb_win64_254:
    mov r11d, 254
    jmp ci_cb_win64_entry
.globl ci_cb_win64_255
ci_cb_win64_255:
    mov r11d, 255
    jmp ci_cb_win64_entry

.section .data
.globl ci_cb_table
.p2align 3
ci_cb_table:
    .quad ci_cb_win64_0
    .quad ci_cb_win64_1
    .quad ci_cb_win64_2
    .quad ci_cb_win64_3
    .quad ci_cb_win64_4
    .quad ci_cb_win64_5
    .quad ci_cb_win64_6
    .quad ci_cb_win64_7
    .quad ci_cb_win64_8
    .quad ci_cb_win64_9
    .quad ci_cb_win64_10
    .quad ci_cb_win64_11
    .quad ci_cb_win64_12
    .quad ci_cb_win64_13
    .quad ci_cb_win64_14
    .quad ci_cb_win64_15
    .quad ci_cb_win64_16
    .quad ci_cb_win64_17
    .quad ci_cb_win64_18
    .quad ci_cb_win64_19
    .quad ci_cb_win64_20
    .quad ci_cb_win64_21
    .quad ci_cb_win64_22
    .quad ci_cb_win64_23
    .quad ci_cb_win64_24
    .quad ci_cb_win64_25
    .quad ci_cb_win64_26
    .quad ci_cb_win64_27
    .quad ci_cb_win64_28
    .quad ci_cb_win64_29
    .quad ci_cb_win64_30
    .quad ci_cb_win64_31
    .quad ci_cb_win64_32
    .quad ci_cb_win64_33
    .quad ci_cb_win64_34
    .quad ci_cb_win64_35
    .quad ci_cb_win64_36
    .quad ci_cb_win64_37
    .quad ci_cb_win64_38
    .quad ci_cb_win64_39
    .quad ci_cb_win64_40
    .quad ci_cb_win64_41
    .quad ci_cb_win64_42
    .quad ci_cb_win64_43
    .quad ci_cb_win64_44
    .quad ci_cb_win64_45
    .quad ci_cb_win64_46
    .quad ci_cb_win64_47
    .quad ci_cb_win64_48
    .quad ci_cb_win64_49
    .quad ci_cb_win64_50
    .quad ci_cb_win64_51
    .quad ci_cb_win64_52
    .quad ci_cb_win64_53
    .quad ci_cb_win64_54
    .quad ci_cb_win64_55
    .quad ci_cb_win64_56
    .quad ci_cb_win64_57
    .quad ci_cb_win64_58
    .quad ci_cb_win64_59
    .quad ci_cb_win64_60
    .quad ci_cb_win64_61
    .quad ci_cb_win64_62
    .quad ci_cb_win64_63
    .quad ci_cb_win64_64
    .quad ci_cb_win64_65
    .quad ci_cb_win64_66
    .quad ci_cb_win64_67
    .quad ci_cb_win64_68
    .quad ci_cb_win64_69
    .quad ci_cb_win64_70
    .quad ci_cb_win64_71
    .quad ci_cb_win64_72
    .quad ci_cb_win64_73
    .quad ci_cb_win64_74
    .quad ci_cb_win64_75
    .quad ci_cb_win64_76
    .quad ci_cb_win64_77
    .quad ci_cb_win64_78
    .quad ci_cb_win64_79
    .quad ci_cb_win64_80
    .quad ci_cb_win64_81
    .quad ci_cb_win64_82
    .quad ci_cb_win64_83
    .quad ci_cb_win64_84
    .quad ci_cb_win64_85
    .quad ci_cb_win64_86
    .quad ci_cb_win64_87
    .quad ci_cb_win64_88
    .quad ci_cb_win64_89
    .quad ci_cb_win64_90
    .quad ci_cb_win64_91
    .quad ci_cb_win64_92
    .quad ci_cb_win64_93
    .quad ci_cb_win64_94
    .quad ci_cb_win64_95
    .quad ci_cb_win64_96
    .quad ci_cb_win64_97
    .quad ci_cb_win64_98
    .quad ci_cb_win64_99
    .quad ci_cb_win64_100
    .quad ci_cb_win64_101
    .quad ci_cb_win64_102
    .quad ci_cb_win64_103
    .quad ci_cb_win64_104
    .quad ci_cb_win64_105
    .quad ci_cb_win64_106
    .quad ci_cb_win64_107
    .quad ci_cb_win64_108
    .quad ci_cb_win64_109
    .quad ci_cb_win64_110
    .quad ci_cb_win64_111
    .quad ci_cb_win64_112
    .quad ci_cb_win64_113
    .quad ci_cb_win64_114
    .quad ci_cb_win64_115
    .quad ci_cb_win64_116
    .quad ci_cb_win64_117
    .quad ci_cb_win64_118
    .quad ci_cb_win64_119
    .quad ci_cb_win64_120
    .quad ci_cb_win64_121
    .quad ci_cb_win64_122
    .quad ci_cb_win64_123
    .quad ci_cb_win64_124
    .quad ci_cb_win64_125
    .quad ci_cb_win64_126
    .quad ci_cb_win64_127
    .quad ci_cb_win64_128
    .quad ci_cb_win64_129
    .quad ci_cb_win64_130
    .quad ci_cb_win64_131
    .quad ci_cb_win64_132
    .quad ci_cb_win64_133
    .quad ci_cb_win64_134
    .quad ci_cb_win64_135
    .quad ci_cb_win64_136
    .quad ci_cb_win64_137
    .quad ci_cb_win64_138
    .quad ci_cb_win64_139
    .quad ci_cb_win64_140
    .quad ci_cb_win64_141
    .quad ci_cb_win64_142
    .quad ci_cb_win64_143
    .quad ci_cb_win64_144
    .quad ci_cb_win64_145
    .quad ci_cb_win64_146
    .quad ci_cb_win64_147
    .quad ci_cb_win64_148
    .quad ci_cb_win64_149
    .quad ci_cb_win64_150
    .quad ci_cb_win64_151
    .quad ci_cb_win64_152
    .quad ci_cb_win64_153
    .quad ci_cb_win64_154
    .quad ci_cb_win64_155
    .quad ci_cb_win64_156
    .quad ci_cb_win64_157
    .quad ci_cb_win64_158
    .quad ci_cb_win64_159
    .quad ci_cb_win64_160
    .quad ci_cb_win64_161
    .quad ci_cb_win64_162
    .quad ci_cb_win64_163
    .quad ci_cb_win64_164
    .quad ci_cb_win64_165
    .quad ci_cb_win64_166
    .quad ci_cb_win64_167
    .quad ci_cb_win64_168
    .quad ci_cb_win64_169
    .quad ci_cb_win64_170
    .quad ci_cb_win64_171
    .quad ci_cb_win64_172
    .quad ci_cb_win64_173
    .quad ci_cb_win64_174
    .quad ci_cb_win64_175
    .quad ci_cb_win64_176
    .quad ci_cb_win64_177
    .quad ci_cb_win64_178
    .quad ci_cb_win64_179
    .quad ci_cb_win64_180
    .quad ci_cb_win64_181
    .quad ci_cb_win64_182
    .quad ci_cb_win64_183
    .quad ci_cb_win64_184
    .quad ci_cb_win64_185
    .quad ci_cb_win64_186
    .quad ci_cb_win64_187
    .quad ci_cb_win64_188
    .quad ci_cb_win64_189
    .quad ci_cb_win64_190
    .quad ci_cb_win64_191
    .quad ci_cb_win64_192
    .quad ci_cb_win64_193
    .quad ci_cb_win64_194
    .quad ci_cb_win64_195
    .quad ci_cb_win64_196
    .quad ci_cb_win64_197
    .quad ci_cb_win64_198
    .quad ci_cb_win64_199
    .quad ci_cb_win64_200
    .quad ci_cb_win64_201
    .quad ci_cb_win64_202
    .quad ci_cb_win64_203
    .quad ci_cb_win64_204
    .quad ci_cb_win64_205
    .quad ci_cb_win64_206
    .quad ci_cb_win64_207
    .quad ci_cb_win64_208
    .quad ci_cb_win64_209
    .quad ci_cb_win64_210
    .quad ci_cb_win64_211
    .quad ci_cb_win64_212
    .quad ci_cb_win64_213
    .quad ci_cb_win64_214
    .quad ci_cb_win64_215
    .quad ci_cb_win64_216
    .quad ci_cb_win64_217
    .quad ci_cb_win64_218
    .quad ci_cb_win64_219
    .quad ci_cb_win64_220
    .quad ci_cb_win64_221
    .quad ci_cb_win64_222
    .quad ci_cb_win64_223
    .quad ci_cb_win64_224
    .quad ci_cb_win64_225
    .quad ci_cb_win64_226
    .quad ci_cb_win64_227
    .quad ci_cb_win64_228
    .quad ci_cb_win64_229
    .quad ci_cb_win64_230
    .quad ci_cb_win64_231
    .quad ci_cb_win64_232
    .quad ci_cb_win64_233
    .quad ci_cb_win64_234
    .quad ci_cb_win64_235
    .quad ci_cb_win64_236
    .quad ci_cb_win64_237
    .quad ci_cb_win64_238
    .quad ci_cb_win64_239
    .quad ci_cb_win64_240
    .quad ci_cb_win64_241
    .quad ci_cb_win64_242
    .quad ci_cb_win64_243
    .quad ci_cb_win64_244
    .quad ci_cb_win64_245
    .quad ci_cb_win64_246
    .quad ci_cb_win64_247
    .quad ci_cb_win64_248
    .quad ci_cb_win64_249
    .quad ci_cb_win64_250
    .quad ci_cb_win64_251
    .quad ci_cb_win64_252
    .quad ci_cb_win64_253
    .quad ci_cb_win64_254
    .quad ci_cb_win64_255
