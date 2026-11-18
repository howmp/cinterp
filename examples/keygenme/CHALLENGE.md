# keygenme 挑战

## 目标

给定用户名，构造至少一个被 `keygenme` 接受的序列号，并实现可复现的 keygen。

## 运行

```sh
keygenme <name> <serial>
```

合法返回 `0` 并输出 `Access granted`；非法返回 `1`。


## 提示

1. 程序包含一个完整vm运行时和字节码，其中字节码是由C语言编译而成
2. 我测试使用DeepSeek V4.1 Flash大约需要15分钟(输入:12.06M|输出:99.6k|缓存率:97.7%)

