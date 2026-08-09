# 示例脚本说明

> 所有脚本均经过测试，可直接运行

---

## 快速运行

```bash
# 示例1: 基础DNS查询
perl /workspace/scripts/examples/example_dns_query.pl

# 示例2: 多DNS对比
perl /workspace/scripts/examples/example_multi_dns.pl

# 示例3: DNS64检测
perl /workspace/scripts/examples/example_dns64_check.pl

# 示例4: 反向DNS解析
perl /workspace/scripts/examples/example_reverse_dns.pl
```

---

## Shell 脚本：云南电信 DNS 地毯式测试

```bash
# 精简版（9 维度 66 项，约 3-5 分钟）
bash /workspace/scripts/dns_test/yunnan_telecom_dns_benchmark_lite.sh

# 完整版（15 维度 79 项，约 8-10 分钟）
bash /workspace/scripts/dns_test/yunnan_telecom_dns_benchmark_full.sh
```

**使用方式**：先询问用户选择版本

```
请选择测试版本：
1. 精简版（9 项基础测试，约 3-5 分钟）
2. 完整版（15 项全面测试，约 8-10 分钟）
```

功能对比：
- 精简版: A/AAAA记录、3GPP域名、记录类型、稳定性、异常测试、连通性、一致性、运营商域名
- 完整版: 精简版 + DNSSEC、ECS、PTR、TTL分析、劫持检测、递归查询

---

## 脚本详情

### example_dns_query.pl
- **功能**: 查询单个域名的A记录和AAAA记录
- **配置**: 修改 `$DNS_SERVER` 和 `@DOMAINS`
- **输出**: 每个域名的A记录和AAAA记录列表

### example_multi_dns.pl
- **功能**: 同时查询多个DNS服务器，对比解析结果
- **配置**: 修改 `@DNS_SERVERS` 和 `@DOMAINS`
- **输出**: 各DNS解析结果 + 一致性检查报告

### example_dns64_check.pl
- **功能**: 检测DNS服务器是否支持DNS64（合成AAAA记录）
- **配置**: 修改 `@DNS_SERVERS` 和 `@DOMAINS`
- **输出**: DNS64合成记录检测 + 嵌入IPv4提取

### example_reverse_dns.pl
- **功能**: 反向DNS解析（IP地址 → 域名）
- **配置**: 修改 `$DNS_SERVER` 和 `@IPS`
- **输出**: IP地址对应的PTR记录（如有）

---

## 自定义配置

每个脚本顶部都有配置区域，可以修改：

```perl
# DNS服务器地址
my $DNS_SERVER = "222.172.200.68";

# 要测试的域名列表
my @DOMAINS = ("www.baidu.com", "www.qq.com");
```

---

## 注意事项

1. **忽略 "uninitialized value" 警告** — 这是沙箱环境的正常现象
2. **超时设置默认为5秒** — 可在 `setsockopt` 中调整
3. **IPv4/IPv6 DNS地址** — 自动识别双栈，无需额外配置
4. **Shell脚本** — 需要 bash 环境，测试需约 5-10 分钟
