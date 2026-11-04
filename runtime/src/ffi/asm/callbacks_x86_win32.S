.intel_syntax noprefix

.equ CB_SLOT, 0
.equ CB_STACK, 4
.equ CB_EAX, 8
.equ CB_EDX, 12
.equ CB_ST0, 16
.equ CB_X87, 24
.equ CB_CLEANUP, 28
.equ CB_ST0_F80, 32
.equ CB_FAST_ECX, 48
.equ CB_FAST_EDX, 52

.text

ci_cb_win32_entry:
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
    sub esp, 64
    and esp, -16
    mov ebx, esp
    /* Preserve the two `__fastcall` argument registers before the dispatcher
       call; cdecl/stdcall plans simply ignore these frame fields. */
    mov [ebx + CB_FAST_ECX], ecx
    mov [ebx + CB_FAST_EDX], edx
    mov eax, [ebp + 4]
    mov [ebx + CB_SLOT], eax
    lea eax, [ebp + 12]
    mov [ebx + CB_STACK], eax
    xor eax, eax
    mov [ebx + CB_EAX], eax
    mov [ebx + CB_EDX], eax
    mov [ebx + CB_ST0], eax
    mov [ebx + CB_ST0 + 4], eax
    mov byte ptr [ebx + CB_X87], 0
    sub esp, 4
    push ebx
    push 0
    push dword ptr [ebp + 4]
    call _ci_callback_dispatch
    add esp, 16
    mov eax, [ebx + CB_EAX]
    mov edx, [ebx + CB_EDX]
    cmp byte ptr [ebx + CB_X87], 1
    je .Lcb_x87_f64
    cmp byte ptr [ebx + CB_X87], 2
    je .Lcb_x87_f80
    jmp .Lcb_no_x87
.Lcb_x87_f64:
    fld qword ptr [ebx + CB_ST0]
    jmp .Lcb_no_x87
.Lcb_x87_f80:
    fld tbyte ptr [ebx + CB_ST0_F80]
.Lcb_no_x87:
    /* `ci_callback_dispatch` set CB_CLEANUP to the argument bytes an i686
       `__stdcall` callee must pop (0 for `__cdecl`, where the caller pops).
       Keep the return address in ECX (EAX/EDX hold integer/aggregate returns),
       replace the dead return-address stack slot with the cleanup dword, then
       skip the return address plus the callee-pops bytes and jump back. Using
       `ret` here would pop one of the arguments as the return address. */
    mov ecx, [ebx + CB_CLEANUP]
    lea esp, [ebp - 12]
    pop edi
    pop esi
    pop ebx
    leave
    add esp, 4
    xchg ecx, [esp]
    add esp, 4
    add esp, [esp - 4]
    jmp ecx

.p2align 4
.globl ci_cb_win32_0
ci_cb_win32_0:
    push 0
    jmp ci_cb_win32_entry
.globl ci_cb_win32_1
ci_cb_win32_1:
    push 1
    jmp ci_cb_win32_entry
.globl ci_cb_win32_2
ci_cb_win32_2:
    push 2
    jmp ci_cb_win32_entry
.globl ci_cb_win32_3
ci_cb_win32_3:
    push 3
    jmp ci_cb_win32_entry
.globl ci_cb_win32_4
ci_cb_win32_4:
    push 4
    jmp ci_cb_win32_entry
.globl ci_cb_win32_5
ci_cb_win32_5:
    push 5
    jmp ci_cb_win32_entry
.globl ci_cb_win32_6
ci_cb_win32_6:
    push 6
    jmp ci_cb_win32_entry
.globl ci_cb_win32_7
ci_cb_win32_7:
    push 7
    jmp ci_cb_win32_entry
.globl ci_cb_win32_8
ci_cb_win32_8:
    push 8
    jmp ci_cb_win32_entry
.globl ci_cb_win32_9
ci_cb_win32_9:
    push 9
    jmp ci_cb_win32_entry
.globl ci_cb_win32_10
ci_cb_win32_10:
    push 10
    jmp ci_cb_win32_entry
.globl ci_cb_win32_11
ci_cb_win32_11:
    push 11
    jmp ci_cb_win32_entry
.globl ci_cb_win32_12
ci_cb_win32_12:
    push 12
    jmp ci_cb_win32_entry
.globl ci_cb_win32_13
ci_cb_win32_13:
    push 13
    jmp ci_cb_win32_entry
.globl ci_cb_win32_14
ci_cb_win32_14:
    push 14
    jmp ci_cb_win32_entry
.globl ci_cb_win32_15
ci_cb_win32_15:
    push 15
    jmp ci_cb_win32_entry
.globl ci_cb_win32_16
ci_cb_win32_16:
    push 16
    jmp ci_cb_win32_entry
.globl ci_cb_win32_17
ci_cb_win32_17:
    push 17
    jmp ci_cb_win32_entry
.globl ci_cb_win32_18
ci_cb_win32_18:
    push 18
    jmp ci_cb_win32_entry
.globl ci_cb_win32_19
ci_cb_win32_19:
    push 19
    jmp ci_cb_win32_entry
.globl ci_cb_win32_20
ci_cb_win32_20:
    push 20
    jmp ci_cb_win32_entry
.globl ci_cb_win32_21
ci_cb_win32_21:
    push 21
    jmp ci_cb_win32_entry
.globl ci_cb_win32_22
ci_cb_win32_22:
    push 22
    jmp ci_cb_win32_entry
.globl ci_cb_win32_23
ci_cb_win32_23:
    push 23
    jmp ci_cb_win32_entry
.globl ci_cb_win32_24
ci_cb_win32_24:
    push 24
    jmp ci_cb_win32_entry
.globl ci_cb_win32_25
ci_cb_win32_25:
    push 25
    jmp ci_cb_win32_entry
.globl ci_cb_win32_26
ci_cb_win32_26:
    push 26
    jmp ci_cb_win32_entry
.globl ci_cb_win32_27
ci_cb_win32_27:
    push 27
    jmp ci_cb_win32_entry
.globl ci_cb_win32_28
ci_cb_win32_28:
    push 28
    jmp ci_cb_win32_entry
.globl ci_cb_win32_29
ci_cb_win32_29:
    push 29
    jmp ci_cb_win32_entry
.globl ci_cb_win32_30
ci_cb_win32_30:
    push 30
    jmp ci_cb_win32_entry
.globl ci_cb_win32_31
ci_cb_win32_31:
    push 31
    jmp ci_cb_win32_entry
.globl ci_cb_win32_32
ci_cb_win32_32:
    push 32
    jmp ci_cb_win32_entry
.globl ci_cb_win32_33
ci_cb_win32_33:
    push 33
    jmp ci_cb_win32_entry
.globl ci_cb_win32_34
ci_cb_win32_34:
    push 34
    jmp ci_cb_win32_entry
.globl ci_cb_win32_35
ci_cb_win32_35:
    push 35
    jmp ci_cb_win32_entry
.globl ci_cb_win32_36
ci_cb_win32_36:
    push 36
    jmp ci_cb_win32_entry
.globl ci_cb_win32_37
ci_cb_win32_37:
    push 37
    jmp ci_cb_win32_entry
.globl ci_cb_win32_38
ci_cb_win32_38:
    push 38
    jmp ci_cb_win32_entry
.globl ci_cb_win32_39
ci_cb_win32_39:
    push 39
    jmp ci_cb_win32_entry
.globl ci_cb_win32_40
ci_cb_win32_40:
    push 40
    jmp ci_cb_win32_entry
.globl ci_cb_win32_41
ci_cb_win32_41:
    push 41
    jmp ci_cb_win32_entry
.globl ci_cb_win32_42
ci_cb_win32_42:
    push 42
    jmp ci_cb_win32_entry
.globl ci_cb_win32_43
ci_cb_win32_43:
    push 43
    jmp ci_cb_win32_entry
.globl ci_cb_win32_44
ci_cb_win32_44:
    push 44
    jmp ci_cb_win32_entry
.globl ci_cb_win32_45
ci_cb_win32_45:
    push 45
    jmp ci_cb_win32_entry
.globl ci_cb_win32_46
ci_cb_win32_46:
    push 46
    jmp ci_cb_win32_entry
.globl ci_cb_win32_47
ci_cb_win32_47:
    push 47
    jmp ci_cb_win32_entry
.globl ci_cb_win32_48
ci_cb_win32_48:
    push 48
    jmp ci_cb_win32_entry
.globl ci_cb_win32_49
ci_cb_win32_49:
    push 49
    jmp ci_cb_win32_entry
.globl ci_cb_win32_50
ci_cb_win32_50:
    push 50
    jmp ci_cb_win32_entry
.globl ci_cb_win32_51
ci_cb_win32_51:
    push 51
    jmp ci_cb_win32_entry
.globl ci_cb_win32_52
ci_cb_win32_52:
    push 52
    jmp ci_cb_win32_entry
.globl ci_cb_win32_53
ci_cb_win32_53:
    push 53
    jmp ci_cb_win32_entry
.globl ci_cb_win32_54
ci_cb_win32_54:
    push 54
    jmp ci_cb_win32_entry
.globl ci_cb_win32_55
ci_cb_win32_55:
    push 55
    jmp ci_cb_win32_entry
.globl ci_cb_win32_56
ci_cb_win32_56:
    push 56
    jmp ci_cb_win32_entry
.globl ci_cb_win32_57
ci_cb_win32_57:
    push 57
    jmp ci_cb_win32_entry
.globl ci_cb_win32_58
ci_cb_win32_58:
    push 58
    jmp ci_cb_win32_entry
.globl ci_cb_win32_59
ci_cb_win32_59:
    push 59
    jmp ci_cb_win32_entry
.globl ci_cb_win32_60
ci_cb_win32_60:
    push 60
    jmp ci_cb_win32_entry
.globl ci_cb_win32_61
ci_cb_win32_61:
    push 61
    jmp ci_cb_win32_entry
.globl ci_cb_win32_62
ci_cb_win32_62:
    push 62
    jmp ci_cb_win32_entry
.globl ci_cb_win32_63
ci_cb_win32_63:
    push 63
    jmp ci_cb_win32_entry
.globl ci_cb_win32_64
ci_cb_win32_64:
    push 64
    jmp ci_cb_win32_entry
.globl ci_cb_win32_65
ci_cb_win32_65:
    push 65
    jmp ci_cb_win32_entry
.globl ci_cb_win32_66
ci_cb_win32_66:
    push 66
    jmp ci_cb_win32_entry
.globl ci_cb_win32_67
ci_cb_win32_67:
    push 67
    jmp ci_cb_win32_entry
.globl ci_cb_win32_68
ci_cb_win32_68:
    push 68
    jmp ci_cb_win32_entry
.globl ci_cb_win32_69
ci_cb_win32_69:
    push 69
    jmp ci_cb_win32_entry
.globl ci_cb_win32_70
ci_cb_win32_70:
    push 70
    jmp ci_cb_win32_entry
.globl ci_cb_win32_71
ci_cb_win32_71:
    push 71
    jmp ci_cb_win32_entry
.globl ci_cb_win32_72
ci_cb_win32_72:
    push 72
    jmp ci_cb_win32_entry
.globl ci_cb_win32_73
ci_cb_win32_73:
    push 73
    jmp ci_cb_win32_entry
.globl ci_cb_win32_74
ci_cb_win32_74:
    push 74
    jmp ci_cb_win32_entry
.globl ci_cb_win32_75
ci_cb_win32_75:
    push 75
    jmp ci_cb_win32_entry
.globl ci_cb_win32_76
ci_cb_win32_76:
    push 76
    jmp ci_cb_win32_entry
.globl ci_cb_win32_77
ci_cb_win32_77:
    push 77
    jmp ci_cb_win32_entry
.globl ci_cb_win32_78
ci_cb_win32_78:
    push 78
    jmp ci_cb_win32_entry
.globl ci_cb_win32_79
ci_cb_win32_79:
    push 79
    jmp ci_cb_win32_entry
.globl ci_cb_win32_80
ci_cb_win32_80:
    push 80
    jmp ci_cb_win32_entry
.globl ci_cb_win32_81
ci_cb_win32_81:
    push 81
    jmp ci_cb_win32_entry
.globl ci_cb_win32_82
ci_cb_win32_82:
    push 82
    jmp ci_cb_win32_entry
.globl ci_cb_win32_83
ci_cb_win32_83:
    push 83
    jmp ci_cb_win32_entry
.globl ci_cb_win32_84
ci_cb_win32_84:
    push 84
    jmp ci_cb_win32_entry
.globl ci_cb_win32_85
ci_cb_win32_85:
    push 85
    jmp ci_cb_win32_entry
.globl ci_cb_win32_86
ci_cb_win32_86:
    push 86
    jmp ci_cb_win32_entry
.globl ci_cb_win32_87
ci_cb_win32_87:
    push 87
    jmp ci_cb_win32_entry
.globl ci_cb_win32_88
ci_cb_win32_88:
    push 88
    jmp ci_cb_win32_entry
.globl ci_cb_win32_89
ci_cb_win32_89:
    push 89
    jmp ci_cb_win32_entry
.globl ci_cb_win32_90
ci_cb_win32_90:
    push 90
    jmp ci_cb_win32_entry
.globl ci_cb_win32_91
ci_cb_win32_91:
    push 91
    jmp ci_cb_win32_entry
.globl ci_cb_win32_92
ci_cb_win32_92:
    push 92
    jmp ci_cb_win32_entry
.globl ci_cb_win32_93
ci_cb_win32_93:
    push 93
    jmp ci_cb_win32_entry
.globl ci_cb_win32_94
ci_cb_win32_94:
    push 94
    jmp ci_cb_win32_entry
.globl ci_cb_win32_95
ci_cb_win32_95:
    push 95
    jmp ci_cb_win32_entry
.globl ci_cb_win32_96
ci_cb_win32_96:
    push 96
    jmp ci_cb_win32_entry
.globl ci_cb_win32_97
ci_cb_win32_97:
    push 97
    jmp ci_cb_win32_entry
.globl ci_cb_win32_98
ci_cb_win32_98:
    push 98
    jmp ci_cb_win32_entry
.globl ci_cb_win32_99
ci_cb_win32_99:
    push 99
    jmp ci_cb_win32_entry
.globl ci_cb_win32_100
ci_cb_win32_100:
    push 100
    jmp ci_cb_win32_entry
.globl ci_cb_win32_101
ci_cb_win32_101:
    push 101
    jmp ci_cb_win32_entry
.globl ci_cb_win32_102
ci_cb_win32_102:
    push 102
    jmp ci_cb_win32_entry
.globl ci_cb_win32_103
ci_cb_win32_103:
    push 103
    jmp ci_cb_win32_entry
.globl ci_cb_win32_104
ci_cb_win32_104:
    push 104
    jmp ci_cb_win32_entry
.globl ci_cb_win32_105
ci_cb_win32_105:
    push 105
    jmp ci_cb_win32_entry
.globl ci_cb_win32_106
ci_cb_win32_106:
    push 106
    jmp ci_cb_win32_entry
.globl ci_cb_win32_107
ci_cb_win32_107:
    push 107
    jmp ci_cb_win32_entry
.globl ci_cb_win32_108
ci_cb_win32_108:
    push 108
    jmp ci_cb_win32_entry
.globl ci_cb_win32_109
ci_cb_win32_109:
    push 109
    jmp ci_cb_win32_entry
.globl ci_cb_win32_110
ci_cb_win32_110:
    push 110
    jmp ci_cb_win32_entry
.globl ci_cb_win32_111
ci_cb_win32_111:
    push 111
    jmp ci_cb_win32_entry
.globl ci_cb_win32_112
ci_cb_win32_112:
    push 112
    jmp ci_cb_win32_entry
.globl ci_cb_win32_113
ci_cb_win32_113:
    push 113
    jmp ci_cb_win32_entry
.globl ci_cb_win32_114
ci_cb_win32_114:
    push 114
    jmp ci_cb_win32_entry
.globl ci_cb_win32_115
ci_cb_win32_115:
    push 115
    jmp ci_cb_win32_entry
.globl ci_cb_win32_116
ci_cb_win32_116:
    push 116
    jmp ci_cb_win32_entry
.globl ci_cb_win32_117
ci_cb_win32_117:
    push 117
    jmp ci_cb_win32_entry
.globl ci_cb_win32_118
ci_cb_win32_118:
    push 118
    jmp ci_cb_win32_entry
.globl ci_cb_win32_119
ci_cb_win32_119:
    push 119
    jmp ci_cb_win32_entry
.globl ci_cb_win32_120
ci_cb_win32_120:
    push 120
    jmp ci_cb_win32_entry
.globl ci_cb_win32_121
ci_cb_win32_121:
    push 121
    jmp ci_cb_win32_entry
.globl ci_cb_win32_122
ci_cb_win32_122:
    push 122
    jmp ci_cb_win32_entry
.globl ci_cb_win32_123
ci_cb_win32_123:
    push 123
    jmp ci_cb_win32_entry
.globl ci_cb_win32_124
ci_cb_win32_124:
    push 124
    jmp ci_cb_win32_entry
.globl ci_cb_win32_125
ci_cb_win32_125:
    push 125
    jmp ci_cb_win32_entry
.globl ci_cb_win32_126
ci_cb_win32_126:
    push 126
    jmp ci_cb_win32_entry
.globl ci_cb_win32_127
ci_cb_win32_127:
    push 127
    jmp ci_cb_win32_entry
.globl ci_cb_win32_128
ci_cb_win32_128:
    push 128
    jmp ci_cb_win32_entry
.globl ci_cb_win32_129
ci_cb_win32_129:
    push 129
    jmp ci_cb_win32_entry
.globl ci_cb_win32_130
ci_cb_win32_130:
    push 130
    jmp ci_cb_win32_entry
.globl ci_cb_win32_131
ci_cb_win32_131:
    push 131
    jmp ci_cb_win32_entry
.globl ci_cb_win32_132
ci_cb_win32_132:
    push 132
    jmp ci_cb_win32_entry
.globl ci_cb_win32_133
ci_cb_win32_133:
    push 133
    jmp ci_cb_win32_entry
.globl ci_cb_win32_134
ci_cb_win32_134:
    push 134
    jmp ci_cb_win32_entry
.globl ci_cb_win32_135
ci_cb_win32_135:
    push 135
    jmp ci_cb_win32_entry
.globl ci_cb_win32_136
ci_cb_win32_136:
    push 136
    jmp ci_cb_win32_entry
.globl ci_cb_win32_137
ci_cb_win32_137:
    push 137
    jmp ci_cb_win32_entry
.globl ci_cb_win32_138
ci_cb_win32_138:
    push 138
    jmp ci_cb_win32_entry
.globl ci_cb_win32_139
ci_cb_win32_139:
    push 139
    jmp ci_cb_win32_entry
.globl ci_cb_win32_140
ci_cb_win32_140:
    push 140
    jmp ci_cb_win32_entry
.globl ci_cb_win32_141
ci_cb_win32_141:
    push 141
    jmp ci_cb_win32_entry
.globl ci_cb_win32_142
ci_cb_win32_142:
    push 142
    jmp ci_cb_win32_entry
.globl ci_cb_win32_143
ci_cb_win32_143:
    push 143
    jmp ci_cb_win32_entry
.globl ci_cb_win32_144
ci_cb_win32_144:
    push 144
    jmp ci_cb_win32_entry
.globl ci_cb_win32_145
ci_cb_win32_145:
    push 145
    jmp ci_cb_win32_entry
.globl ci_cb_win32_146
ci_cb_win32_146:
    push 146
    jmp ci_cb_win32_entry
.globl ci_cb_win32_147
ci_cb_win32_147:
    push 147
    jmp ci_cb_win32_entry
.globl ci_cb_win32_148
ci_cb_win32_148:
    push 148
    jmp ci_cb_win32_entry
.globl ci_cb_win32_149
ci_cb_win32_149:
    push 149
    jmp ci_cb_win32_entry
.globl ci_cb_win32_150
ci_cb_win32_150:
    push 150
    jmp ci_cb_win32_entry
.globl ci_cb_win32_151
ci_cb_win32_151:
    push 151
    jmp ci_cb_win32_entry
.globl ci_cb_win32_152
ci_cb_win32_152:
    push 152
    jmp ci_cb_win32_entry
.globl ci_cb_win32_153
ci_cb_win32_153:
    push 153
    jmp ci_cb_win32_entry
.globl ci_cb_win32_154
ci_cb_win32_154:
    push 154
    jmp ci_cb_win32_entry
.globl ci_cb_win32_155
ci_cb_win32_155:
    push 155
    jmp ci_cb_win32_entry
.globl ci_cb_win32_156
ci_cb_win32_156:
    push 156
    jmp ci_cb_win32_entry
.globl ci_cb_win32_157
ci_cb_win32_157:
    push 157
    jmp ci_cb_win32_entry
.globl ci_cb_win32_158
ci_cb_win32_158:
    push 158
    jmp ci_cb_win32_entry
.globl ci_cb_win32_159
ci_cb_win32_159:
    push 159
    jmp ci_cb_win32_entry
.globl ci_cb_win32_160
ci_cb_win32_160:
    push 160
    jmp ci_cb_win32_entry
.globl ci_cb_win32_161
ci_cb_win32_161:
    push 161
    jmp ci_cb_win32_entry
.globl ci_cb_win32_162
ci_cb_win32_162:
    push 162
    jmp ci_cb_win32_entry
.globl ci_cb_win32_163
ci_cb_win32_163:
    push 163
    jmp ci_cb_win32_entry
.globl ci_cb_win32_164
ci_cb_win32_164:
    push 164
    jmp ci_cb_win32_entry
.globl ci_cb_win32_165
ci_cb_win32_165:
    push 165
    jmp ci_cb_win32_entry
.globl ci_cb_win32_166
ci_cb_win32_166:
    push 166
    jmp ci_cb_win32_entry
.globl ci_cb_win32_167
ci_cb_win32_167:
    push 167
    jmp ci_cb_win32_entry
.globl ci_cb_win32_168
ci_cb_win32_168:
    push 168
    jmp ci_cb_win32_entry
.globl ci_cb_win32_169
ci_cb_win32_169:
    push 169
    jmp ci_cb_win32_entry
.globl ci_cb_win32_170
ci_cb_win32_170:
    push 170
    jmp ci_cb_win32_entry
.globl ci_cb_win32_171
ci_cb_win32_171:
    push 171
    jmp ci_cb_win32_entry
.globl ci_cb_win32_172
ci_cb_win32_172:
    push 172
    jmp ci_cb_win32_entry
.globl ci_cb_win32_173
ci_cb_win32_173:
    push 173
    jmp ci_cb_win32_entry
.globl ci_cb_win32_174
ci_cb_win32_174:
    push 174
    jmp ci_cb_win32_entry
.globl ci_cb_win32_175
ci_cb_win32_175:
    push 175
    jmp ci_cb_win32_entry
.globl ci_cb_win32_176
ci_cb_win32_176:
    push 176
    jmp ci_cb_win32_entry
.globl ci_cb_win32_177
ci_cb_win32_177:
    push 177
    jmp ci_cb_win32_entry
.globl ci_cb_win32_178
ci_cb_win32_178:
    push 178
    jmp ci_cb_win32_entry
.globl ci_cb_win32_179
ci_cb_win32_179:
    push 179
    jmp ci_cb_win32_entry
.globl ci_cb_win32_180
ci_cb_win32_180:
    push 180
    jmp ci_cb_win32_entry
.globl ci_cb_win32_181
ci_cb_win32_181:
    push 181
    jmp ci_cb_win32_entry
.globl ci_cb_win32_182
ci_cb_win32_182:
    push 182
    jmp ci_cb_win32_entry
.globl ci_cb_win32_183
ci_cb_win32_183:
    push 183
    jmp ci_cb_win32_entry
.globl ci_cb_win32_184
ci_cb_win32_184:
    push 184
    jmp ci_cb_win32_entry
.globl ci_cb_win32_185
ci_cb_win32_185:
    push 185
    jmp ci_cb_win32_entry
.globl ci_cb_win32_186
ci_cb_win32_186:
    push 186
    jmp ci_cb_win32_entry
.globl ci_cb_win32_187
ci_cb_win32_187:
    push 187
    jmp ci_cb_win32_entry
.globl ci_cb_win32_188
ci_cb_win32_188:
    push 188
    jmp ci_cb_win32_entry
.globl ci_cb_win32_189
ci_cb_win32_189:
    push 189
    jmp ci_cb_win32_entry
.globl ci_cb_win32_190
ci_cb_win32_190:
    push 190
    jmp ci_cb_win32_entry
.globl ci_cb_win32_191
ci_cb_win32_191:
    push 191
    jmp ci_cb_win32_entry
.globl ci_cb_win32_192
ci_cb_win32_192:
    push 192
    jmp ci_cb_win32_entry
.globl ci_cb_win32_193
ci_cb_win32_193:
    push 193
    jmp ci_cb_win32_entry
.globl ci_cb_win32_194
ci_cb_win32_194:
    push 194
    jmp ci_cb_win32_entry
.globl ci_cb_win32_195
ci_cb_win32_195:
    push 195
    jmp ci_cb_win32_entry
.globl ci_cb_win32_196
ci_cb_win32_196:
    push 196
    jmp ci_cb_win32_entry
.globl ci_cb_win32_197
ci_cb_win32_197:
    push 197
    jmp ci_cb_win32_entry
.globl ci_cb_win32_198
ci_cb_win32_198:
    push 198
    jmp ci_cb_win32_entry
.globl ci_cb_win32_199
ci_cb_win32_199:
    push 199
    jmp ci_cb_win32_entry
.globl ci_cb_win32_200
ci_cb_win32_200:
    push 200
    jmp ci_cb_win32_entry
.globl ci_cb_win32_201
ci_cb_win32_201:
    push 201
    jmp ci_cb_win32_entry
.globl ci_cb_win32_202
ci_cb_win32_202:
    push 202
    jmp ci_cb_win32_entry
.globl ci_cb_win32_203
ci_cb_win32_203:
    push 203
    jmp ci_cb_win32_entry
.globl ci_cb_win32_204
ci_cb_win32_204:
    push 204
    jmp ci_cb_win32_entry
.globl ci_cb_win32_205
ci_cb_win32_205:
    push 205
    jmp ci_cb_win32_entry
.globl ci_cb_win32_206
ci_cb_win32_206:
    push 206
    jmp ci_cb_win32_entry
.globl ci_cb_win32_207
ci_cb_win32_207:
    push 207
    jmp ci_cb_win32_entry
.globl ci_cb_win32_208
ci_cb_win32_208:
    push 208
    jmp ci_cb_win32_entry
.globl ci_cb_win32_209
ci_cb_win32_209:
    push 209
    jmp ci_cb_win32_entry
.globl ci_cb_win32_210
ci_cb_win32_210:
    push 210
    jmp ci_cb_win32_entry
.globl ci_cb_win32_211
ci_cb_win32_211:
    push 211
    jmp ci_cb_win32_entry
.globl ci_cb_win32_212
ci_cb_win32_212:
    push 212
    jmp ci_cb_win32_entry
.globl ci_cb_win32_213
ci_cb_win32_213:
    push 213
    jmp ci_cb_win32_entry
.globl ci_cb_win32_214
ci_cb_win32_214:
    push 214
    jmp ci_cb_win32_entry
.globl ci_cb_win32_215
ci_cb_win32_215:
    push 215
    jmp ci_cb_win32_entry
.globl ci_cb_win32_216
ci_cb_win32_216:
    push 216
    jmp ci_cb_win32_entry
.globl ci_cb_win32_217
ci_cb_win32_217:
    push 217
    jmp ci_cb_win32_entry
.globl ci_cb_win32_218
ci_cb_win32_218:
    push 218
    jmp ci_cb_win32_entry
.globl ci_cb_win32_219
ci_cb_win32_219:
    push 219
    jmp ci_cb_win32_entry
.globl ci_cb_win32_220
ci_cb_win32_220:
    push 220
    jmp ci_cb_win32_entry
.globl ci_cb_win32_221
ci_cb_win32_221:
    push 221
    jmp ci_cb_win32_entry
.globl ci_cb_win32_222
ci_cb_win32_222:
    push 222
    jmp ci_cb_win32_entry
.globl ci_cb_win32_223
ci_cb_win32_223:
    push 223
    jmp ci_cb_win32_entry
.globl ci_cb_win32_224
ci_cb_win32_224:
    push 224
    jmp ci_cb_win32_entry
.globl ci_cb_win32_225
ci_cb_win32_225:
    push 225
    jmp ci_cb_win32_entry
.globl ci_cb_win32_226
ci_cb_win32_226:
    push 226
    jmp ci_cb_win32_entry
.globl ci_cb_win32_227
ci_cb_win32_227:
    push 227
    jmp ci_cb_win32_entry
.globl ci_cb_win32_228
ci_cb_win32_228:
    push 228
    jmp ci_cb_win32_entry
.globl ci_cb_win32_229
ci_cb_win32_229:
    push 229
    jmp ci_cb_win32_entry
.globl ci_cb_win32_230
ci_cb_win32_230:
    push 230
    jmp ci_cb_win32_entry
.globl ci_cb_win32_231
ci_cb_win32_231:
    push 231
    jmp ci_cb_win32_entry
.globl ci_cb_win32_232
ci_cb_win32_232:
    push 232
    jmp ci_cb_win32_entry
.globl ci_cb_win32_233
ci_cb_win32_233:
    push 233
    jmp ci_cb_win32_entry
.globl ci_cb_win32_234
ci_cb_win32_234:
    push 234
    jmp ci_cb_win32_entry
.globl ci_cb_win32_235
ci_cb_win32_235:
    push 235
    jmp ci_cb_win32_entry
.globl ci_cb_win32_236
ci_cb_win32_236:
    push 236
    jmp ci_cb_win32_entry
.globl ci_cb_win32_237
ci_cb_win32_237:
    push 237
    jmp ci_cb_win32_entry
.globl ci_cb_win32_238
ci_cb_win32_238:
    push 238
    jmp ci_cb_win32_entry
.globl ci_cb_win32_239
ci_cb_win32_239:
    push 239
    jmp ci_cb_win32_entry
.globl ci_cb_win32_240
ci_cb_win32_240:
    push 240
    jmp ci_cb_win32_entry
.globl ci_cb_win32_241
ci_cb_win32_241:
    push 241
    jmp ci_cb_win32_entry
.globl ci_cb_win32_242
ci_cb_win32_242:
    push 242
    jmp ci_cb_win32_entry
.globl ci_cb_win32_243
ci_cb_win32_243:
    push 243
    jmp ci_cb_win32_entry
.globl ci_cb_win32_244
ci_cb_win32_244:
    push 244
    jmp ci_cb_win32_entry
.globl ci_cb_win32_245
ci_cb_win32_245:
    push 245
    jmp ci_cb_win32_entry
.globl ci_cb_win32_246
ci_cb_win32_246:
    push 246
    jmp ci_cb_win32_entry
.globl ci_cb_win32_247
ci_cb_win32_247:
    push 247
    jmp ci_cb_win32_entry
.globl ci_cb_win32_248
ci_cb_win32_248:
    push 248
    jmp ci_cb_win32_entry
.globl ci_cb_win32_249
ci_cb_win32_249:
    push 249
    jmp ci_cb_win32_entry
.globl ci_cb_win32_250
ci_cb_win32_250:
    push 250
    jmp ci_cb_win32_entry
.globl ci_cb_win32_251
ci_cb_win32_251:
    push 251
    jmp ci_cb_win32_entry
.globl ci_cb_win32_252
ci_cb_win32_252:
    push 252
    jmp ci_cb_win32_entry
.globl ci_cb_win32_253
ci_cb_win32_253:
    push 253
    jmp ci_cb_win32_entry
.globl ci_cb_win32_254
ci_cb_win32_254:
    push 254
    jmp ci_cb_win32_entry
.globl ci_cb_win32_255
ci_cb_win32_255:
    push 255
    jmp ci_cb_win32_entry

.section .data
.globl _ci_cb_table
.p2align 2
_ci_cb_table:
    .long ci_cb_win32_0
    .long ci_cb_win32_1
    .long ci_cb_win32_2
    .long ci_cb_win32_3
    .long ci_cb_win32_4
    .long ci_cb_win32_5
    .long ci_cb_win32_6
    .long ci_cb_win32_7
    .long ci_cb_win32_8
    .long ci_cb_win32_9
    .long ci_cb_win32_10
    .long ci_cb_win32_11
    .long ci_cb_win32_12
    .long ci_cb_win32_13
    .long ci_cb_win32_14
    .long ci_cb_win32_15
    .long ci_cb_win32_16
    .long ci_cb_win32_17
    .long ci_cb_win32_18
    .long ci_cb_win32_19
    .long ci_cb_win32_20
    .long ci_cb_win32_21
    .long ci_cb_win32_22
    .long ci_cb_win32_23
    .long ci_cb_win32_24
    .long ci_cb_win32_25
    .long ci_cb_win32_26
    .long ci_cb_win32_27
    .long ci_cb_win32_28
    .long ci_cb_win32_29
    .long ci_cb_win32_30
    .long ci_cb_win32_31
    .long ci_cb_win32_32
    .long ci_cb_win32_33
    .long ci_cb_win32_34
    .long ci_cb_win32_35
    .long ci_cb_win32_36
    .long ci_cb_win32_37
    .long ci_cb_win32_38
    .long ci_cb_win32_39
    .long ci_cb_win32_40
    .long ci_cb_win32_41
    .long ci_cb_win32_42
    .long ci_cb_win32_43
    .long ci_cb_win32_44
    .long ci_cb_win32_45
    .long ci_cb_win32_46
    .long ci_cb_win32_47
    .long ci_cb_win32_48
    .long ci_cb_win32_49
    .long ci_cb_win32_50
    .long ci_cb_win32_51
    .long ci_cb_win32_52
    .long ci_cb_win32_53
    .long ci_cb_win32_54
    .long ci_cb_win32_55
    .long ci_cb_win32_56
    .long ci_cb_win32_57
    .long ci_cb_win32_58
    .long ci_cb_win32_59
    .long ci_cb_win32_60
    .long ci_cb_win32_61
    .long ci_cb_win32_62
    .long ci_cb_win32_63
    .long ci_cb_win32_64
    .long ci_cb_win32_65
    .long ci_cb_win32_66
    .long ci_cb_win32_67
    .long ci_cb_win32_68
    .long ci_cb_win32_69
    .long ci_cb_win32_70
    .long ci_cb_win32_71
    .long ci_cb_win32_72
    .long ci_cb_win32_73
    .long ci_cb_win32_74
    .long ci_cb_win32_75
    .long ci_cb_win32_76
    .long ci_cb_win32_77
    .long ci_cb_win32_78
    .long ci_cb_win32_79
    .long ci_cb_win32_80
    .long ci_cb_win32_81
    .long ci_cb_win32_82
    .long ci_cb_win32_83
    .long ci_cb_win32_84
    .long ci_cb_win32_85
    .long ci_cb_win32_86
    .long ci_cb_win32_87
    .long ci_cb_win32_88
    .long ci_cb_win32_89
    .long ci_cb_win32_90
    .long ci_cb_win32_91
    .long ci_cb_win32_92
    .long ci_cb_win32_93
    .long ci_cb_win32_94
    .long ci_cb_win32_95
    .long ci_cb_win32_96
    .long ci_cb_win32_97
    .long ci_cb_win32_98
    .long ci_cb_win32_99
    .long ci_cb_win32_100
    .long ci_cb_win32_101
    .long ci_cb_win32_102
    .long ci_cb_win32_103
    .long ci_cb_win32_104
    .long ci_cb_win32_105
    .long ci_cb_win32_106
    .long ci_cb_win32_107
    .long ci_cb_win32_108
    .long ci_cb_win32_109
    .long ci_cb_win32_110
    .long ci_cb_win32_111
    .long ci_cb_win32_112
    .long ci_cb_win32_113
    .long ci_cb_win32_114
    .long ci_cb_win32_115
    .long ci_cb_win32_116
    .long ci_cb_win32_117
    .long ci_cb_win32_118
    .long ci_cb_win32_119
    .long ci_cb_win32_120
    .long ci_cb_win32_121
    .long ci_cb_win32_122
    .long ci_cb_win32_123
    .long ci_cb_win32_124
    .long ci_cb_win32_125
    .long ci_cb_win32_126
    .long ci_cb_win32_127
    .long ci_cb_win32_128
    .long ci_cb_win32_129
    .long ci_cb_win32_130
    .long ci_cb_win32_131
    .long ci_cb_win32_132
    .long ci_cb_win32_133
    .long ci_cb_win32_134
    .long ci_cb_win32_135
    .long ci_cb_win32_136
    .long ci_cb_win32_137
    .long ci_cb_win32_138
    .long ci_cb_win32_139
    .long ci_cb_win32_140
    .long ci_cb_win32_141
    .long ci_cb_win32_142
    .long ci_cb_win32_143
    .long ci_cb_win32_144
    .long ci_cb_win32_145
    .long ci_cb_win32_146
    .long ci_cb_win32_147
    .long ci_cb_win32_148
    .long ci_cb_win32_149
    .long ci_cb_win32_150
    .long ci_cb_win32_151
    .long ci_cb_win32_152
    .long ci_cb_win32_153
    .long ci_cb_win32_154
    .long ci_cb_win32_155
    .long ci_cb_win32_156
    .long ci_cb_win32_157
    .long ci_cb_win32_158
    .long ci_cb_win32_159
    .long ci_cb_win32_160
    .long ci_cb_win32_161
    .long ci_cb_win32_162
    .long ci_cb_win32_163
    .long ci_cb_win32_164
    .long ci_cb_win32_165
    .long ci_cb_win32_166
    .long ci_cb_win32_167
    .long ci_cb_win32_168
    .long ci_cb_win32_169
    .long ci_cb_win32_170
    .long ci_cb_win32_171
    .long ci_cb_win32_172
    .long ci_cb_win32_173
    .long ci_cb_win32_174
    .long ci_cb_win32_175
    .long ci_cb_win32_176
    .long ci_cb_win32_177
    .long ci_cb_win32_178
    .long ci_cb_win32_179
    .long ci_cb_win32_180
    .long ci_cb_win32_181
    .long ci_cb_win32_182
    .long ci_cb_win32_183
    .long ci_cb_win32_184
    .long ci_cb_win32_185
    .long ci_cb_win32_186
    .long ci_cb_win32_187
    .long ci_cb_win32_188
    .long ci_cb_win32_189
    .long ci_cb_win32_190
    .long ci_cb_win32_191
    .long ci_cb_win32_192
    .long ci_cb_win32_193
    .long ci_cb_win32_194
    .long ci_cb_win32_195
    .long ci_cb_win32_196
    .long ci_cb_win32_197
    .long ci_cb_win32_198
    .long ci_cb_win32_199
    .long ci_cb_win32_200
    .long ci_cb_win32_201
    .long ci_cb_win32_202
    .long ci_cb_win32_203
    .long ci_cb_win32_204
    .long ci_cb_win32_205
    .long ci_cb_win32_206
    .long ci_cb_win32_207
    .long ci_cb_win32_208
    .long ci_cb_win32_209
    .long ci_cb_win32_210
    .long ci_cb_win32_211
    .long ci_cb_win32_212
    .long ci_cb_win32_213
    .long ci_cb_win32_214
    .long ci_cb_win32_215
    .long ci_cb_win32_216
    .long ci_cb_win32_217
    .long ci_cb_win32_218
    .long ci_cb_win32_219
    .long ci_cb_win32_220
    .long ci_cb_win32_221
    .long ci_cb_win32_222
    .long ci_cb_win32_223
    .long ci_cb_win32_224
    .long ci_cb_win32_225
    .long ci_cb_win32_226
    .long ci_cb_win32_227
    .long ci_cb_win32_228
    .long ci_cb_win32_229
    .long ci_cb_win32_230
    .long ci_cb_win32_231
    .long ci_cb_win32_232
    .long ci_cb_win32_233
    .long ci_cb_win32_234
    .long ci_cb_win32_235
    .long ci_cb_win32_236
    .long ci_cb_win32_237
    .long ci_cb_win32_238
    .long ci_cb_win32_239
    .long ci_cb_win32_240
    .long ci_cb_win32_241
    .long ci_cb_win32_242
    .long ci_cb_win32_243
    .long ci_cb_win32_244
    .long ci_cb_win32_245
    .long ci_cb_win32_246
    .long ci_cb_win32_247
    .long ci_cb_win32_248
    .long ci_cb_win32_249
    .long ci_cb_win32_250
    .long ci_cb_win32_251
    .long ci_cb_win32_252
    .long ci_cb_win32_253
    .long ci_cb_win32_254
    .long ci_cb_win32_255
