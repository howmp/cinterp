.arch armv8-a
.text

ci_cb_arm64_entry:
    mov x10, sp
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #384
    mov x11, sp
    str x9, [x11, #0]
    stp x0, x1, [x11, #8]
    stp x2, x3, [x11, #24]
    stp x4, x5, [x11, #40]
    stp x6, x7, [x11, #56]
    stp q0, q1, [x11, #80]
    stp q2, q3, [x11, #112]
    stp q4, q5, [x11, #144]
    stp q6, q7, [x11, #176]
    str x10, [x11, #208]
    str x8, [x11, #368]
    stp xzr, xzr, [x11, #216]
    str xzr, [x11, #232]
    stp xzr, xzr, [x11, #240]
    stp xzr, xzr, [x11, #256]
    stp xzr, xzr, [x11, #336]
    stp xzr, xzr, [x11, #352]
    stp d8, d9, [x11, #272]
    stp d10, d11, [x11, #288]
    stp d12, d13, [x11, #304]
    stp d14, d15, [x11, #320]
    mov x0, x9
    mov x1, x11
    bl ci_callback_dispatch
    sub x11, x29, #384
    ldp x0, x1, [x11, #216]
    ldp q0, q1, [x11, #240]
    ldp q2, q3, [x11, #336]
    ldp d8, d9, [x11, #272]
    ldp d10, d11, [x11, #288]
    ldp d12, d13, [x11, #304]
    ldp d14, d15, [x11, #320]
    mov sp, x29
    ldp x29, x30, [sp], #16
    ret

.p2align 4
.globl ci_cb_arm64_0
ci_cb_arm64_0:
    mov x9, #0
    b ci_cb_arm64_entry
.globl ci_cb_arm64_1
ci_cb_arm64_1:
    mov x9, #1
    b ci_cb_arm64_entry
.globl ci_cb_arm64_2
ci_cb_arm64_2:
    mov x9, #2
    b ci_cb_arm64_entry
.globl ci_cb_arm64_3
ci_cb_arm64_3:
    mov x9, #3
    b ci_cb_arm64_entry
.globl ci_cb_arm64_4
ci_cb_arm64_4:
    mov x9, #4
    b ci_cb_arm64_entry
.globl ci_cb_arm64_5
ci_cb_arm64_5:
    mov x9, #5
    b ci_cb_arm64_entry
.globl ci_cb_arm64_6
ci_cb_arm64_6:
    mov x9, #6
    b ci_cb_arm64_entry
.globl ci_cb_arm64_7
ci_cb_arm64_7:
    mov x9, #7
    b ci_cb_arm64_entry
.globl ci_cb_arm64_8
ci_cb_arm64_8:
    mov x9, #8
    b ci_cb_arm64_entry
.globl ci_cb_arm64_9
ci_cb_arm64_9:
    mov x9, #9
    b ci_cb_arm64_entry
.globl ci_cb_arm64_10
ci_cb_arm64_10:
    mov x9, #10
    b ci_cb_arm64_entry
.globl ci_cb_arm64_11
ci_cb_arm64_11:
    mov x9, #11
    b ci_cb_arm64_entry
.globl ci_cb_arm64_12
ci_cb_arm64_12:
    mov x9, #12
    b ci_cb_arm64_entry
.globl ci_cb_arm64_13
ci_cb_arm64_13:
    mov x9, #13
    b ci_cb_arm64_entry
.globl ci_cb_arm64_14
ci_cb_arm64_14:
    mov x9, #14
    b ci_cb_arm64_entry
.globl ci_cb_arm64_15
ci_cb_arm64_15:
    mov x9, #15
    b ci_cb_arm64_entry
.globl ci_cb_arm64_16
ci_cb_arm64_16:
    mov x9, #16
    b ci_cb_arm64_entry
.globl ci_cb_arm64_17
ci_cb_arm64_17:
    mov x9, #17
    b ci_cb_arm64_entry
.globl ci_cb_arm64_18
ci_cb_arm64_18:
    mov x9, #18
    b ci_cb_arm64_entry
.globl ci_cb_arm64_19
ci_cb_arm64_19:
    mov x9, #19
    b ci_cb_arm64_entry
.globl ci_cb_arm64_20
ci_cb_arm64_20:
    mov x9, #20
    b ci_cb_arm64_entry
.globl ci_cb_arm64_21
ci_cb_arm64_21:
    mov x9, #21
    b ci_cb_arm64_entry
.globl ci_cb_arm64_22
ci_cb_arm64_22:
    mov x9, #22
    b ci_cb_arm64_entry
.globl ci_cb_arm64_23
ci_cb_arm64_23:
    mov x9, #23
    b ci_cb_arm64_entry
.globl ci_cb_arm64_24
ci_cb_arm64_24:
    mov x9, #24
    b ci_cb_arm64_entry
.globl ci_cb_arm64_25
ci_cb_arm64_25:
    mov x9, #25
    b ci_cb_arm64_entry
.globl ci_cb_arm64_26
ci_cb_arm64_26:
    mov x9, #26
    b ci_cb_arm64_entry
.globl ci_cb_arm64_27
ci_cb_arm64_27:
    mov x9, #27
    b ci_cb_arm64_entry
.globl ci_cb_arm64_28
ci_cb_arm64_28:
    mov x9, #28
    b ci_cb_arm64_entry
.globl ci_cb_arm64_29
ci_cb_arm64_29:
    mov x9, #29
    b ci_cb_arm64_entry
.globl ci_cb_arm64_30
ci_cb_arm64_30:
    mov x9, #30
    b ci_cb_arm64_entry
.globl ci_cb_arm64_31
ci_cb_arm64_31:
    mov x9, #31
    b ci_cb_arm64_entry
.globl ci_cb_arm64_32
ci_cb_arm64_32:
    mov x9, #32
    b ci_cb_arm64_entry
.globl ci_cb_arm64_33
ci_cb_arm64_33:
    mov x9, #33
    b ci_cb_arm64_entry
.globl ci_cb_arm64_34
ci_cb_arm64_34:
    mov x9, #34
    b ci_cb_arm64_entry
.globl ci_cb_arm64_35
ci_cb_arm64_35:
    mov x9, #35
    b ci_cb_arm64_entry
.globl ci_cb_arm64_36
ci_cb_arm64_36:
    mov x9, #36
    b ci_cb_arm64_entry
.globl ci_cb_arm64_37
ci_cb_arm64_37:
    mov x9, #37
    b ci_cb_arm64_entry
.globl ci_cb_arm64_38
ci_cb_arm64_38:
    mov x9, #38
    b ci_cb_arm64_entry
.globl ci_cb_arm64_39
ci_cb_arm64_39:
    mov x9, #39
    b ci_cb_arm64_entry
.globl ci_cb_arm64_40
ci_cb_arm64_40:
    mov x9, #40
    b ci_cb_arm64_entry
.globl ci_cb_arm64_41
ci_cb_arm64_41:
    mov x9, #41
    b ci_cb_arm64_entry
.globl ci_cb_arm64_42
ci_cb_arm64_42:
    mov x9, #42
    b ci_cb_arm64_entry
.globl ci_cb_arm64_43
ci_cb_arm64_43:
    mov x9, #43
    b ci_cb_arm64_entry
.globl ci_cb_arm64_44
ci_cb_arm64_44:
    mov x9, #44
    b ci_cb_arm64_entry
.globl ci_cb_arm64_45
ci_cb_arm64_45:
    mov x9, #45
    b ci_cb_arm64_entry
.globl ci_cb_arm64_46
ci_cb_arm64_46:
    mov x9, #46
    b ci_cb_arm64_entry
.globl ci_cb_arm64_47
ci_cb_arm64_47:
    mov x9, #47
    b ci_cb_arm64_entry
.globl ci_cb_arm64_48
ci_cb_arm64_48:
    mov x9, #48
    b ci_cb_arm64_entry
.globl ci_cb_arm64_49
ci_cb_arm64_49:
    mov x9, #49
    b ci_cb_arm64_entry
.globl ci_cb_arm64_50
ci_cb_arm64_50:
    mov x9, #50
    b ci_cb_arm64_entry
.globl ci_cb_arm64_51
ci_cb_arm64_51:
    mov x9, #51
    b ci_cb_arm64_entry
.globl ci_cb_arm64_52
ci_cb_arm64_52:
    mov x9, #52
    b ci_cb_arm64_entry
.globl ci_cb_arm64_53
ci_cb_arm64_53:
    mov x9, #53
    b ci_cb_arm64_entry
.globl ci_cb_arm64_54
ci_cb_arm64_54:
    mov x9, #54
    b ci_cb_arm64_entry
.globl ci_cb_arm64_55
ci_cb_arm64_55:
    mov x9, #55
    b ci_cb_arm64_entry
.globl ci_cb_arm64_56
ci_cb_arm64_56:
    mov x9, #56
    b ci_cb_arm64_entry
.globl ci_cb_arm64_57
ci_cb_arm64_57:
    mov x9, #57
    b ci_cb_arm64_entry
.globl ci_cb_arm64_58
ci_cb_arm64_58:
    mov x9, #58
    b ci_cb_arm64_entry
.globl ci_cb_arm64_59
ci_cb_arm64_59:
    mov x9, #59
    b ci_cb_arm64_entry
.globl ci_cb_arm64_60
ci_cb_arm64_60:
    mov x9, #60
    b ci_cb_arm64_entry
.globl ci_cb_arm64_61
ci_cb_arm64_61:
    mov x9, #61
    b ci_cb_arm64_entry
.globl ci_cb_arm64_62
ci_cb_arm64_62:
    mov x9, #62
    b ci_cb_arm64_entry
.globl ci_cb_arm64_63
ci_cb_arm64_63:
    mov x9, #63
    b ci_cb_arm64_entry
.globl ci_cb_arm64_64
ci_cb_arm64_64:
    mov x9, #64
    b ci_cb_arm64_entry
.globl ci_cb_arm64_65
ci_cb_arm64_65:
    mov x9, #65
    b ci_cb_arm64_entry
.globl ci_cb_arm64_66
ci_cb_arm64_66:
    mov x9, #66
    b ci_cb_arm64_entry
.globl ci_cb_arm64_67
ci_cb_arm64_67:
    mov x9, #67
    b ci_cb_arm64_entry
.globl ci_cb_arm64_68
ci_cb_arm64_68:
    mov x9, #68
    b ci_cb_arm64_entry
.globl ci_cb_arm64_69
ci_cb_arm64_69:
    mov x9, #69
    b ci_cb_arm64_entry
.globl ci_cb_arm64_70
ci_cb_arm64_70:
    mov x9, #70
    b ci_cb_arm64_entry
.globl ci_cb_arm64_71
ci_cb_arm64_71:
    mov x9, #71
    b ci_cb_arm64_entry
.globl ci_cb_arm64_72
ci_cb_arm64_72:
    mov x9, #72
    b ci_cb_arm64_entry
.globl ci_cb_arm64_73
ci_cb_arm64_73:
    mov x9, #73
    b ci_cb_arm64_entry
.globl ci_cb_arm64_74
ci_cb_arm64_74:
    mov x9, #74
    b ci_cb_arm64_entry
.globl ci_cb_arm64_75
ci_cb_arm64_75:
    mov x9, #75
    b ci_cb_arm64_entry
.globl ci_cb_arm64_76
ci_cb_arm64_76:
    mov x9, #76
    b ci_cb_arm64_entry
.globl ci_cb_arm64_77
ci_cb_arm64_77:
    mov x9, #77
    b ci_cb_arm64_entry
.globl ci_cb_arm64_78
ci_cb_arm64_78:
    mov x9, #78
    b ci_cb_arm64_entry
.globl ci_cb_arm64_79
ci_cb_arm64_79:
    mov x9, #79
    b ci_cb_arm64_entry
.globl ci_cb_arm64_80
ci_cb_arm64_80:
    mov x9, #80
    b ci_cb_arm64_entry
.globl ci_cb_arm64_81
ci_cb_arm64_81:
    mov x9, #81
    b ci_cb_arm64_entry
.globl ci_cb_arm64_82
ci_cb_arm64_82:
    mov x9, #82
    b ci_cb_arm64_entry
.globl ci_cb_arm64_83
ci_cb_arm64_83:
    mov x9, #83
    b ci_cb_arm64_entry
.globl ci_cb_arm64_84
ci_cb_arm64_84:
    mov x9, #84
    b ci_cb_arm64_entry
.globl ci_cb_arm64_85
ci_cb_arm64_85:
    mov x9, #85
    b ci_cb_arm64_entry
.globl ci_cb_arm64_86
ci_cb_arm64_86:
    mov x9, #86
    b ci_cb_arm64_entry
.globl ci_cb_arm64_87
ci_cb_arm64_87:
    mov x9, #87
    b ci_cb_arm64_entry
.globl ci_cb_arm64_88
ci_cb_arm64_88:
    mov x9, #88
    b ci_cb_arm64_entry
.globl ci_cb_arm64_89
ci_cb_arm64_89:
    mov x9, #89
    b ci_cb_arm64_entry
.globl ci_cb_arm64_90
ci_cb_arm64_90:
    mov x9, #90
    b ci_cb_arm64_entry
.globl ci_cb_arm64_91
ci_cb_arm64_91:
    mov x9, #91
    b ci_cb_arm64_entry
.globl ci_cb_arm64_92
ci_cb_arm64_92:
    mov x9, #92
    b ci_cb_arm64_entry
.globl ci_cb_arm64_93
ci_cb_arm64_93:
    mov x9, #93
    b ci_cb_arm64_entry
.globl ci_cb_arm64_94
ci_cb_arm64_94:
    mov x9, #94
    b ci_cb_arm64_entry
.globl ci_cb_arm64_95
ci_cb_arm64_95:
    mov x9, #95
    b ci_cb_arm64_entry
.globl ci_cb_arm64_96
ci_cb_arm64_96:
    mov x9, #96
    b ci_cb_arm64_entry
.globl ci_cb_arm64_97
ci_cb_arm64_97:
    mov x9, #97
    b ci_cb_arm64_entry
.globl ci_cb_arm64_98
ci_cb_arm64_98:
    mov x9, #98
    b ci_cb_arm64_entry
.globl ci_cb_arm64_99
ci_cb_arm64_99:
    mov x9, #99
    b ci_cb_arm64_entry
.globl ci_cb_arm64_100
ci_cb_arm64_100:
    mov x9, #100
    b ci_cb_arm64_entry
.globl ci_cb_arm64_101
ci_cb_arm64_101:
    mov x9, #101
    b ci_cb_arm64_entry
.globl ci_cb_arm64_102
ci_cb_arm64_102:
    mov x9, #102
    b ci_cb_arm64_entry
.globl ci_cb_arm64_103
ci_cb_arm64_103:
    mov x9, #103
    b ci_cb_arm64_entry
.globl ci_cb_arm64_104
ci_cb_arm64_104:
    mov x9, #104
    b ci_cb_arm64_entry
.globl ci_cb_arm64_105
ci_cb_arm64_105:
    mov x9, #105
    b ci_cb_arm64_entry
.globl ci_cb_arm64_106
ci_cb_arm64_106:
    mov x9, #106
    b ci_cb_arm64_entry
.globl ci_cb_arm64_107
ci_cb_arm64_107:
    mov x9, #107
    b ci_cb_arm64_entry
.globl ci_cb_arm64_108
ci_cb_arm64_108:
    mov x9, #108
    b ci_cb_arm64_entry
.globl ci_cb_arm64_109
ci_cb_arm64_109:
    mov x9, #109
    b ci_cb_arm64_entry
.globl ci_cb_arm64_110
ci_cb_arm64_110:
    mov x9, #110
    b ci_cb_arm64_entry
.globl ci_cb_arm64_111
ci_cb_arm64_111:
    mov x9, #111
    b ci_cb_arm64_entry
.globl ci_cb_arm64_112
ci_cb_arm64_112:
    mov x9, #112
    b ci_cb_arm64_entry
.globl ci_cb_arm64_113
ci_cb_arm64_113:
    mov x9, #113
    b ci_cb_arm64_entry
.globl ci_cb_arm64_114
ci_cb_arm64_114:
    mov x9, #114
    b ci_cb_arm64_entry
.globl ci_cb_arm64_115
ci_cb_arm64_115:
    mov x9, #115
    b ci_cb_arm64_entry
.globl ci_cb_arm64_116
ci_cb_arm64_116:
    mov x9, #116
    b ci_cb_arm64_entry
.globl ci_cb_arm64_117
ci_cb_arm64_117:
    mov x9, #117
    b ci_cb_arm64_entry
.globl ci_cb_arm64_118
ci_cb_arm64_118:
    mov x9, #118
    b ci_cb_arm64_entry
.globl ci_cb_arm64_119
ci_cb_arm64_119:
    mov x9, #119
    b ci_cb_arm64_entry
.globl ci_cb_arm64_120
ci_cb_arm64_120:
    mov x9, #120
    b ci_cb_arm64_entry
.globl ci_cb_arm64_121
ci_cb_arm64_121:
    mov x9, #121
    b ci_cb_arm64_entry
.globl ci_cb_arm64_122
ci_cb_arm64_122:
    mov x9, #122
    b ci_cb_arm64_entry
.globl ci_cb_arm64_123
ci_cb_arm64_123:
    mov x9, #123
    b ci_cb_arm64_entry
.globl ci_cb_arm64_124
ci_cb_arm64_124:
    mov x9, #124
    b ci_cb_arm64_entry
.globl ci_cb_arm64_125
ci_cb_arm64_125:
    mov x9, #125
    b ci_cb_arm64_entry
.globl ci_cb_arm64_126
ci_cb_arm64_126:
    mov x9, #126
    b ci_cb_arm64_entry
.globl ci_cb_arm64_127
ci_cb_arm64_127:
    mov x9, #127
    b ci_cb_arm64_entry
.globl ci_cb_arm64_128
ci_cb_arm64_128:
    mov x9, #128
    b ci_cb_arm64_entry
.globl ci_cb_arm64_129
ci_cb_arm64_129:
    mov x9, #129
    b ci_cb_arm64_entry
.globl ci_cb_arm64_130
ci_cb_arm64_130:
    mov x9, #130
    b ci_cb_arm64_entry
.globl ci_cb_arm64_131
ci_cb_arm64_131:
    mov x9, #131
    b ci_cb_arm64_entry
.globl ci_cb_arm64_132
ci_cb_arm64_132:
    mov x9, #132
    b ci_cb_arm64_entry
.globl ci_cb_arm64_133
ci_cb_arm64_133:
    mov x9, #133
    b ci_cb_arm64_entry
.globl ci_cb_arm64_134
ci_cb_arm64_134:
    mov x9, #134
    b ci_cb_arm64_entry
.globl ci_cb_arm64_135
ci_cb_arm64_135:
    mov x9, #135
    b ci_cb_arm64_entry
.globl ci_cb_arm64_136
ci_cb_arm64_136:
    mov x9, #136
    b ci_cb_arm64_entry
.globl ci_cb_arm64_137
ci_cb_arm64_137:
    mov x9, #137
    b ci_cb_arm64_entry
.globl ci_cb_arm64_138
ci_cb_arm64_138:
    mov x9, #138
    b ci_cb_arm64_entry
.globl ci_cb_arm64_139
ci_cb_arm64_139:
    mov x9, #139
    b ci_cb_arm64_entry
.globl ci_cb_arm64_140
ci_cb_arm64_140:
    mov x9, #140
    b ci_cb_arm64_entry
.globl ci_cb_arm64_141
ci_cb_arm64_141:
    mov x9, #141
    b ci_cb_arm64_entry
.globl ci_cb_arm64_142
ci_cb_arm64_142:
    mov x9, #142
    b ci_cb_arm64_entry
.globl ci_cb_arm64_143
ci_cb_arm64_143:
    mov x9, #143
    b ci_cb_arm64_entry
.globl ci_cb_arm64_144
ci_cb_arm64_144:
    mov x9, #144
    b ci_cb_arm64_entry
.globl ci_cb_arm64_145
ci_cb_arm64_145:
    mov x9, #145
    b ci_cb_arm64_entry
.globl ci_cb_arm64_146
ci_cb_arm64_146:
    mov x9, #146
    b ci_cb_arm64_entry
.globl ci_cb_arm64_147
ci_cb_arm64_147:
    mov x9, #147
    b ci_cb_arm64_entry
.globl ci_cb_arm64_148
ci_cb_arm64_148:
    mov x9, #148
    b ci_cb_arm64_entry
.globl ci_cb_arm64_149
ci_cb_arm64_149:
    mov x9, #149
    b ci_cb_arm64_entry
.globl ci_cb_arm64_150
ci_cb_arm64_150:
    mov x9, #150
    b ci_cb_arm64_entry
.globl ci_cb_arm64_151
ci_cb_arm64_151:
    mov x9, #151
    b ci_cb_arm64_entry
.globl ci_cb_arm64_152
ci_cb_arm64_152:
    mov x9, #152
    b ci_cb_arm64_entry
.globl ci_cb_arm64_153
ci_cb_arm64_153:
    mov x9, #153
    b ci_cb_arm64_entry
.globl ci_cb_arm64_154
ci_cb_arm64_154:
    mov x9, #154
    b ci_cb_arm64_entry
.globl ci_cb_arm64_155
ci_cb_arm64_155:
    mov x9, #155
    b ci_cb_arm64_entry
.globl ci_cb_arm64_156
ci_cb_arm64_156:
    mov x9, #156
    b ci_cb_arm64_entry
.globl ci_cb_arm64_157
ci_cb_arm64_157:
    mov x9, #157
    b ci_cb_arm64_entry
.globl ci_cb_arm64_158
ci_cb_arm64_158:
    mov x9, #158
    b ci_cb_arm64_entry
.globl ci_cb_arm64_159
ci_cb_arm64_159:
    mov x9, #159
    b ci_cb_arm64_entry
.globl ci_cb_arm64_160
ci_cb_arm64_160:
    mov x9, #160
    b ci_cb_arm64_entry
.globl ci_cb_arm64_161
ci_cb_arm64_161:
    mov x9, #161
    b ci_cb_arm64_entry
.globl ci_cb_arm64_162
ci_cb_arm64_162:
    mov x9, #162
    b ci_cb_arm64_entry
.globl ci_cb_arm64_163
ci_cb_arm64_163:
    mov x9, #163
    b ci_cb_arm64_entry
.globl ci_cb_arm64_164
ci_cb_arm64_164:
    mov x9, #164
    b ci_cb_arm64_entry
.globl ci_cb_arm64_165
ci_cb_arm64_165:
    mov x9, #165
    b ci_cb_arm64_entry
.globl ci_cb_arm64_166
ci_cb_arm64_166:
    mov x9, #166
    b ci_cb_arm64_entry
.globl ci_cb_arm64_167
ci_cb_arm64_167:
    mov x9, #167
    b ci_cb_arm64_entry
.globl ci_cb_arm64_168
ci_cb_arm64_168:
    mov x9, #168
    b ci_cb_arm64_entry
.globl ci_cb_arm64_169
ci_cb_arm64_169:
    mov x9, #169
    b ci_cb_arm64_entry
.globl ci_cb_arm64_170
ci_cb_arm64_170:
    mov x9, #170
    b ci_cb_arm64_entry
.globl ci_cb_arm64_171
ci_cb_arm64_171:
    mov x9, #171
    b ci_cb_arm64_entry
.globl ci_cb_arm64_172
ci_cb_arm64_172:
    mov x9, #172
    b ci_cb_arm64_entry
.globl ci_cb_arm64_173
ci_cb_arm64_173:
    mov x9, #173
    b ci_cb_arm64_entry
.globl ci_cb_arm64_174
ci_cb_arm64_174:
    mov x9, #174
    b ci_cb_arm64_entry
.globl ci_cb_arm64_175
ci_cb_arm64_175:
    mov x9, #175
    b ci_cb_arm64_entry
.globl ci_cb_arm64_176
ci_cb_arm64_176:
    mov x9, #176
    b ci_cb_arm64_entry
.globl ci_cb_arm64_177
ci_cb_arm64_177:
    mov x9, #177
    b ci_cb_arm64_entry
.globl ci_cb_arm64_178
ci_cb_arm64_178:
    mov x9, #178
    b ci_cb_arm64_entry
.globl ci_cb_arm64_179
ci_cb_arm64_179:
    mov x9, #179
    b ci_cb_arm64_entry
.globl ci_cb_arm64_180
ci_cb_arm64_180:
    mov x9, #180
    b ci_cb_arm64_entry
.globl ci_cb_arm64_181
ci_cb_arm64_181:
    mov x9, #181
    b ci_cb_arm64_entry
.globl ci_cb_arm64_182
ci_cb_arm64_182:
    mov x9, #182
    b ci_cb_arm64_entry
.globl ci_cb_arm64_183
ci_cb_arm64_183:
    mov x9, #183
    b ci_cb_arm64_entry
.globl ci_cb_arm64_184
ci_cb_arm64_184:
    mov x9, #184
    b ci_cb_arm64_entry
.globl ci_cb_arm64_185
ci_cb_arm64_185:
    mov x9, #185
    b ci_cb_arm64_entry
.globl ci_cb_arm64_186
ci_cb_arm64_186:
    mov x9, #186
    b ci_cb_arm64_entry
.globl ci_cb_arm64_187
ci_cb_arm64_187:
    mov x9, #187
    b ci_cb_arm64_entry
.globl ci_cb_arm64_188
ci_cb_arm64_188:
    mov x9, #188
    b ci_cb_arm64_entry
.globl ci_cb_arm64_189
ci_cb_arm64_189:
    mov x9, #189
    b ci_cb_arm64_entry
.globl ci_cb_arm64_190
ci_cb_arm64_190:
    mov x9, #190
    b ci_cb_arm64_entry
.globl ci_cb_arm64_191
ci_cb_arm64_191:
    mov x9, #191
    b ci_cb_arm64_entry
.globl ci_cb_arm64_192
ci_cb_arm64_192:
    mov x9, #192
    b ci_cb_arm64_entry
.globl ci_cb_arm64_193
ci_cb_arm64_193:
    mov x9, #193
    b ci_cb_arm64_entry
.globl ci_cb_arm64_194
ci_cb_arm64_194:
    mov x9, #194
    b ci_cb_arm64_entry
.globl ci_cb_arm64_195
ci_cb_arm64_195:
    mov x9, #195
    b ci_cb_arm64_entry
.globl ci_cb_arm64_196
ci_cb_arm64_196:
    mov x9, #196
    b ci_cb_arm64_entry
.globl ci_cb_arm64_197
ci_cb_arm64_197:
    mov x9, #197
    b ci_cb_arm64_entry
.globl ci_cb_arm64_198
ci_cb_arm64_198:
    mov x9, #198
    b ci_cb_arm64_entry
.globl ci_cb_arm64_199
ci_cb_arm64_199:
    mov x9, #199
    b ci_cb_arm64_entry
.globl ci_cb_arm64_200
ci_cb_arm64_200:
    mov x9, #200
    b ci_cb_arm64_entry
.globl ci_cb_arm64_201
ci_cb_arm64_201:
    mov x9, #201
    b ci_cb_arm64_entry
.globl ci_cb_arm64_202
ci_cb_arm64_202:
    mov x9, #202
    b ci_cb_arm64_entry
.globl ci_cb_arm64_203
ci_cb_arm64_203:
    mov x9, #203
    b ci_cb_arm64_entry
.globl ci_cb_arm64_204
ci_cb_arm64_204:
    mov x9, #204
    b ci_cb_arm64_entry
.globl ci_cb_arm64_205
ci_cb_arm64_205:
    mov x9, #205
    b ci_cb_arm64_entry
.globl ci_cb_arm64_206
ci_cb_arm64_206:
    mov x9, #206
    b ci_cb_arm64_entry
.globl ci_cb_arm64_207
ci_cb_arm64_207:
    mov x9, #207
    b ci_cb_arm64_entry
.globl ci_cb_arm64_208
ci_cb_arm64_208:
    mov x9, #208
    b ci_cb_arm64_entry
.globl ci_cb_arm64_209
ci_cb_arm64_209:
    mov x9, #209
    b ci_cb_arm64_entry
.globl ci_cb_arm64_210
ci_cb_arm64_210:
    mov x9, #210
    b ci_cb_arm64_entry
.globl ci_cb_arm64_211
ci_cb_arm64_211:
    mov x9, #211
    b ci_cb_arm64_entry
.globl ci_cb_arm64_212
ci_cb_arm64_212:
    mov x9, #212
    b ci_cb_arm64_entry
.globl ci_cb_arm64_213
ci_cb_arm64_213:
    mov x9, #213
    b ci_cb_arm64_entry
.globl ci_cb_arm64_214
ci_cb_arm64_214:
    mov x9, #214
    b ci_cb_arm64_entry
.globl ci_cb_arm64_215
ci_cb_arm64_215:
    mov x9, #215
    b ci_cb_arm64_entry
.globl ci_cb_arm64_216
ci_cb_arm64_216:
    mov x9, #216
    b ci_cb_arm64_entry
.globl ci_cb_arm64_217
ci_cb_arm64_217:
    mov x9, #217
    b ci_cb_arm64_entry
.globl ci_cb_arm64_218
ci_cb_arm64_218:
    mov x9, #218
    b ci_cb_arm64_entry
.globl ci_cb_arm64_219
ci_cb_arm64_219:
    mov x9, #219
    b ci_cb_arm64_entry
.globl ci_cb_arm64_220
ci_cb_arm64_220:
    mov x9, #220
    b ci_cb_arm64_entry
.globl ci_cb_arm64_221
ci_cb_arm64_221:
    mov x9, #221
    b ci_cb_arm64_entry
.globl ci_cb_arm64_222
ci_cb_arm64_222:
    mov x9, #222
    b ci_cb_arm64_entry
.globl ci_cb_arm64_223
ci_cb_arm64_223:
    mov x9, #223
    b ci_cb_arm64_entry
.globl ci_cb_arm64_224
ci_cb_arm64_224:
    mov x9, #224
    b ci_cb_arm64_entry
.globl ci_cb_arm64_225
ci_cb_arm64_225:
    mov x9, #225
    b ci_cb_arm64_entry
.globl ci_cb_arm64_226
ci_cb_arm64_226:
    mov x9, #226
    b ci_cb_arm64_entry
.globl ci_cb_arm64_227
ci_cb_arm64_227:
    mov x9, #227
    b ci_cb_arm64_entry
.globl ci_cb_arm64_228
ci_cb_arm64_228:
    mov x9, #228
    b ci_cb_arm64_entry
.globl ci_cb_arm64_229
ci_cb_arm64_229:
    mov x9, #229
    b ci_cb_arm64_entry
.globl ci_cb_arm64_230
ci_cb_arm64_230:
    mov x9, #230
    b ci_cb_arm64_entry
.globl ci_cb_arm64_231
ci_cb_arm64_231:
    mov x9, #231
    b ci_cb_arm64_entry
.globl ci_cb_arm64_232
ci_cb_arm64_232:
    mov x9, #232
    b ci_cb_arm64_entry
.globl ci_cb_arm64_233
ci_cb_arm64_233:
    mov x9, #233
    b ci_cb_arm64_entry
.globl ci_cb_arm64_234
ci_cb_arm64_234:
    mov x9, #234
    b ci_cb_arm64_entry
.globl ci_cb_arm64_235
ci_cb_arm64_235:
    mov x9, #235
    b ci_cb_arm64_entry
.globl ci_cb_arm64_236
ci_cb_arm64_236:
    mov x9, #236
    b ci_cb_arm64_entry
.globl ci_cb_arm64_237
ci_cb_arm64_237:
    mov x9, #237
    b ci_cb_arm64_entry
.globl ci_cb_arm64_238
ci_cb_arm64_238:
    mov x9, #238
    b ci_cb_arm64_entry
.globl ci_cb_arm64_239
ci_cb_arm64_239:
    mov x9, #239
    b ci_cb_arm64_entry
.globl ci_cb_arm64_240
ci_cb_arm64_240:
    mov x9, #240
    b ci_cb_arm64_entry
.globl ci_cb_arm64_241
ci_cb_arm64_241:
    mov x9, #241
    b ci_cb_arm64_entry
.globl ci_cb_arm64_242
ci_cb_arm64_242:
    mov x9, #242
    b ci_cb_arm64_entry
.globl ci_cb_arm64_243
ci_cb_arm64_243:
    mov x9, #243
    b ci_cb_arm64_entry
.globl ci_cb_arm64_244
ci_cb_arm64_244:
    mov x9, #244
    b ci_cb_arm64_entry
.globl ci_cb_arm64_245
ci_cb_arm64_245:
    mov x9, #245
    b ci_cb_arm64_entry
.globl ci_cb_arm64_246
ci_cb_arm64_246:
    mov x9, #246
    b ci_cb_arm64_entry
.globl ci_cb_arm64_247
ci_cb_arm64_247:
    mov x9, #247
    b ci_cb_arm64_entry
.globl ci_cb_arm64_248
ci_cb_arm64_248:
    mov x9, #248
    b ci_cb_arm64_entry
.globl ci_cb_arm64_249
ci_cb_arm64_249:
    mov x9, #249
    b ci_cb_arm64_entry
.globl ci_cb_arm64_250
ci_cb_arm64_250:
    mov x9, #250
    b ci_cb_arm64_entry
.globl ci_cb_arm64_251
ci_cb_arm64_251:
    mov x9, #251
    b ci_cb_arm64_entry
.globl ci_cb_arm64_252
ci_cb_arm64_252:
    mov x9, #252
    b ci_cb_arm64_entry
.globl ci_cb_arm64_253
ci_cb_arm64_253:
    mov x9, #253
    b ci_cb_arm64_entry
.globl ci_cb_arm64_254
ci_cb_arm64_254:
    mov x9, #254
    b ci_cb_arm64_entry
.globl ci_cb_arm64_255
ci_cb_arm64_255:
    mov x9, #255
    b ci_cb_arm64_entry

.data
.globl ci_cb_table
.p2align 3
ci_cb_table:
    .quad ci_cb_arm64_0
    .quad ci_cb_arm64_1
    .quad ci_cb_arm64_2
    .quad ci_cb_arm64_3
    .quad ci_cb_arm64_4
    .quad ci_cb_arm64_5
    .quad ci_cb_arm64_6
    .quad ci_cb_arm64_7
    .quad ci_cb_arm64_8
    .quad ci_cb_arm64_9
    .quad ci_cb_arm64_10
    .quad ci_cb_arm64_11
    .quad ci_cb_arm64_12
    .quad ci_cb_arm64_13
    .quad ci_cb_arm64_14
    .quad ci_cb_arm64_15
    .quad ci_cb_arm64_16
    .quad ci_cb_arm64_17
    .quad ci_cb_arm64_18
    .quad ci_cb_arm64_19
    .quad ci_cb_arm64_20
    .quad ci_cb_arm64_21
    .quad ci_cb_arm64_22
    .quad ci_cb_arm64_23
    .quad ci_cb_arm64_24
    .quad ci_cb_arm64_25
    .quad ci_cb_arm64_26
    .quad ci_cb_arm64_27
    .quad ci_cb_arm64_28
    .quad ci_cb_arm64_29
    .quad ci_cb_arm64_30
    .quad ci_cb_arm64_31
    .quad ci_cb_arm64_32
    .quad ci_cb_arm64_33
    .quad ci_cb_arm64_34
    .quad ci_cb_arm64_35
    .quad ci_cb_arm64_36
    .quad ci_cb_arm64_37
    .quad ci_cb_arm64_38
    .quad ci_cb_arm64_39
    .quad ci_cb_arm64_40
    .quad ci_cb_arm64_41
    .quad ci_cb_arm64_42
    .quad ci_cb_arm64_43
    .quad ci_cb_arm64_44
    .quad ci_cb_arm64_45
    .quad ci_cb_arm64_46
    .quad ci_cb_arm64_47
    .quad ci_cb_arm64_48
    .quad ci_cb_arm64_49
    .quad ci_cb_arm64_50
    .quad ci_cb_arm64_51
    .quad ci_cb_arm64_52
    .quad ci_cb_arm64_53
    .quad ci_cb_arm64_54
    .quad ci_cb_arm64_55
    .quad ci_cb_arm64_56
    .quad ci_cb_arm64_57
    .quad ci_cb_arm64_58
    .quad ci_cb_arm64_59
    .quad ci_cb_arm64_60
    .quad ci_cb_arm64_61
    .quad ci_cb_arm64_62
    .quad ci_cb_arm64_63
    .quad ci_cb_arm64_64
    .quad ci_cb_arm64_65
    .quad ci_cb_arm64_66
    .quad ci_cb_arm64_67
    .quad ci_cb_arm64_68
    .quad ci_cb_arm64_69
    .quad ci_cb_arm64_70
    .quad ci_cb_arm64_71
    .quad ci_cb_arm64_72
    .quad ci_cb_arm64_73
    .quad ci_cb_arm64_74
    .quad ci_cb_arm64_75
    .quad ci_cb_arm64_76
    .quad ci_cb_arm64_77
    .quad ci_cb_arm64_78
    .quad ci_cb_arm64_79
    .quad ci_cb_arm64_80
    .quad ci_cb_arm64_81
    .quad ci_cb_arm64_82
    .quad ci_cb_arm64_83
    .quad ci_cb_arm64_84
    .quad ci_cb_arm64_85
    .quad ci_cb_arm64_86
    .quad ci_cb_arm64_87
    .quad ci_cb_arm64_88
    .quad ci_cb_arm64_89
    .quad ci_cb_arm64_90
    .quad ci_cb_arm64_91
    .quad ci_cb_arm64_92
    .quad ci_cb_arm64_93
    .quad ci_cb_arm64_94
    .quad ci_cb_arm64_95
    .quad ci_cb_arm64_96
    .quad ci_cb_arm64_97
    .quad ci_cb_arm64_98
    .quad ci_cb_arm64_99
    .quad ci_cb_arm64_100
    .quad ci_cb_arm64_101
    .quad ci_cb_arm64_102
    .quad ci_cb_arm64_103
    .quad ci_cb_arm64_104
    .quad ci_cb_arm64_105
    .quad ci_cb_arm64_106
    .quad ci_cb_arm64_107
    .quad ci_cb_arm64_108
    .quad ci_cb_arm64_109
    .quad ci_cb_arm64_110
    .quad ci_cb_arm64_111
    .quad ci_cb_arm64_112
    .quad ci_cb_arm64_113
    .quad ci_cb_arm64_114
    .quad ci_cb_arm64_115
    .quad ci_cb_arm64_116
    .quad ci_cb_arm64_117
    .quad ci_cb_arm64_118
    .quad ci_cb_arm64_119
    .quad ci_cb_arm64_120
    .quad ci_cb_arm64_121
    .quad ci_cb_arm64_122
    .quad ci_cb_arm64_123
    .quad ci_cb_arm64_124
    .quad ci_cb_arm64_125
    .quad ci_cb_arm64_126
    .quad ci_cb_arm64_127
    .quad ci_cb_arm64_128
    .quad ci_cb_arm64_129
    .quad ci_cb_arm64_130
    .quad ci_cb_arm64_131
    .quad ci_cb_arm64_132
    .quad ci_cb_arm64_133
    .quad ci_cb_arm64_134
    .quad ci_cb_arm64_135
    .quad ci_cb_arm64_136
    .quad ci_cb_arm64_137
    .quad ci_cb_arm64_138
    .quad ci_cb_arm64_139
    .quad ci_cb_arm64_140
    .quad ci_cb_arm64_141
    .quad ci_cb_arm64_142
    .quad ci_cb_arm64_143
    .quad ci_cb_arm64_144
    .quad ci_cb_arm64_145
    .quad ci_cb_arm64_146
    .quad ci_cb_arm64_147
    .quad ci_cb_arm64_148
    .quad ci_cb_arm64_149
    .quad ci_cb_arm64_150
    .quad ci_cb_arm64_151
    .quad ci_cb_arm64_152
    .quad ci_cb_arm64_153
    .quad ci_cb_arm64_154
    .quad ci_cb_arm64_155
    .quad ci_cb_arm64_156
    .quad ci_cb_arm64_157
    .quad ci_cb_arm64_158
    .quad ci_cb_arm64_159
    .quad ci_cb_arm64_160
    .quad ci_cb_arm64_161
    .quad ci_cb_arm64_162
    .quad ci_cb_arm64_163
    .quad ci_cb_arm64_164
    .quad ci_cb_arm64_165
    .quad ci_cb_arm64_166
    .quad ci_cb_arm64_167
    .quad ci_cb_arm64_168
    .quad ci_cb_arm64_169
    .quad ci_cb_arm64_170
    .quad ci_cb_arm64_171
    .quad ci_cb_arm64_172
    .quad ci_cb_arm64_173
    .quad ci_cb_arm64_174
    .quad ci_cb_arm64_175
    .quad ci_cb_arm64_176
    .quad ci_cb_arm64_177
    .quad ci_cb_arm64_178
    .quad ci_cb_arm64_179
    .quad ci_cb_arm64_180
    .quad ci_cb_arm64_181
    .quad ci_cb_arm64_182
    .quad ci_cb_arm64_183
    .quad ci_cb_arm64_184
    .quad ci_cb_arm64_185
    .quad ci_cb_arm64_186
    .quad ci_cb_arm64_187
    .quad ci_cb_arm64_188
    .quad ci_cb_arm64_189
    .quad ci_cb_arm64_190
    .quad ci_cb_arm64_191
    .quad ci_cb_arm64_192
    .quad ci_cb_arm64_193
    .quad ci_cb_arm64_194
    .quad ci_cb_arm64_195
    .quad ci_cb_arm64_196
    .quad ci_cb_arm64_197
    .quad ci_cb_arm64_198
    .quad ci_cb_arm64_199
    .quad ci_cb_arm64_200
    .quad ci_cb_arm64_201
    .quad ci_cb_arm64_202
    .quad ci_cb_arm64_203
    .quad ci_cb_arm64_204
    .quad ci_cb_arm64_205
    .quad ci_cb_arm64_206
    .quad ci_cb_arm64_207
    .quad ci_cb_arm64_208
    .quad ci_cb_arm64_209
    .quad ci_cb_arm64_210
    .quad ci_cb_arm64_211
    .quad ci_cb_arm64_212
    .quad ci_cb_arm64_213
    .quad ci_cb_arm64_214
    .quad ci_cb_arm64_215
    .quad ci_cb_arm64_216
    .quad ci_cb_arm64_217
    .quad ci_cb_arm64_218
    .quad ci_cb_arm64_219
    .quad ci_cb_arm64_220
    .quad ci_cb_arm64_221
    .quad ci_cb_arm64_222
    .quad ci_cb_arm64_223
    .quad ci_cb_arm64_224
    .quad ci_cb_arm64_225
    .quad ci_cb_arm64_226
    .quad ci_cb_arm64_227
    .quad ci_cb_arm64_228
    .quad ci_cb_arm64_229
    .quad ci_cb_arm64_230
    .quad ci_cb_arm64_231
    .quad ci_cb_arm64_232
    .quad ci_cb_arm64_233
    .quad ci_cb_arm64_234
    .quad ci_cb_arm64_235
    .quad ci_cb_arm64_236
    .quad ci_cb_arm64_237
    .quad ci_cb_arm64_238
    .quad ci_cb_arm64_239
    .quad ci_cb_arm64_240
    .quad ci_cb_arm64_241
    .quad ci_cb_arm64_242
    .quad ci_cb_arm64_243
    .quad ci_cb_arm64_244
    .quad ci_cb_arm64_245
    .quad ci_cb_arm64_246
    .quad ci_cb_arm64_247
    .quad ci_cb_arm64_248
    .quad ci_cb_arm64_249
    .quad ci_cb_arm64_250
    .quad ci_cb_arm64_251
    .quad ci_cb_arm64_252
    .quad ci_cb_arm64_253
    .quad ci_cb_arm64_254
    .quad ci_cb_arm64_255
