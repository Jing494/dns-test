# 📦 示例脚本说明（examples/）

> 通用示例脚本，演示 DNS 查询的各种玩法。
> **所有脚本均支持命令行传自定义 DNS 参数**（v4/v6 均可），不传用默认值。
> 更新：2026-08-09  
> 📍 目录可自由放置（脚本相对定位），示例路径 `/workspace/dns-test` 为当前环境默认，路径不同请替换。

---

## 🚀 快速运行

```bash
cd dns-test   # 或你 clone 的目录

# 示例1: 基础DNS查询（默认云南电信DNS）
perl examples/01_dns_query.pl

# 示例2: 多DNS对比（默认云南电信+114+阿里混合）
perl examples/02_multi_dns_compare.pl

# 示例3: DNS64检测（默认Google/Cloudflare DNS64 + 云南电信对照）
perl examples/03_dns64_check.pl

# 示例4: 反向DNS解析（默认云南电信DNS）
perl examples/04_reverse_dns.pl
```

---

## 🎯 自定义参数用法（重点）

| 脚本 | 参数 | 示例 | 默认值 |
|------|------|------|--------|
| `01_dns_query.pl` | `[DNS地址]` | `perl examples/01_dns_query.pl 8.8.8.8` | `222.172.200.68`（云南电信v4） |
| `02_multi_dns_compare.pl` | `[DNS1] [DNS2] ...` | `perl examples/02_multi_dns_compare.pl 8.8.8.8 114.114.114.114` | 云南电信×2 + 114 + 阿里 + 云南v6 |
| `03_dns64_check.pl` | `[DNS1] [DNS2] ...` | `perl examples/03_dns64_check.pl 2001:4860:4860::6464` | Google/Cloudflare DNS64 + 云南电信对照 |
| `04_reverse_dns.pl` | `[DNS地址]` | `perl examples/04_reverse_dns.pl 114.114.114.114` | `222.172.200.68`（云南电信v4） |

> 💡 **v4/v6 任意混传**：传 `8.8.8.8`、`240e:52:4800::8888`、混合都可以，脚本自动识别双栈。

### 环境变量（不想改命令时的另一种自定义）

| 环境变量 | 作用 | 示例 |
|---------|------|------|
| `DNS_SERVER` | 覆盖 01/04 默认 DNS | `DNS_SERVER="8.8.8.8" perl examples/01_dns_query.pl` |
| `DNS_LIST` | 覆盖 02/03 默认 DNS 列表（逗号分隔） | `DNS_LIST="223.5.5.5,114.114.114.114" perl examples/02_multi_dns_compare.pl` |

> 优先级：命令行参数 > 环境变量 > 脚本默认值

---

## 📖 脚本详情

### 01_dns_query.pl — 基础DNS查询
- **功能**: 查询单个域名的 A 记录和 AAAA 记录
- **默认域名**: www.baidu.com / www.qq.com / www.taobao.com
- **用法**: `perl examples/01_dns_query.pl [DNS地址]`
- **输出**: 每个域名的 A 记录 + AAAA 记录（IPv6 地址）

### 02_multi_dns_compare.pl — 多DNS对比
- **功能**: 同时查询多个 DNS 服务器，对比解析结果 + 一致性检查
- **默认域名**: epdg.epc.mnc011.mcc460.pub.3gppnetwork.org
- **用法**: `perl examples/02_multi_dns_compare.pl [DNS1] [DNS2] ...`
- **输出**: 各 DNS 解析结果 + ✅/⚠️ 一致性报告

### 03_dns64_check.pl — DNS64检测
- **功能**: 检测 DNS 是否支持 DNS64（合成 AAAA 记录，前缀 64:ff9b::）
- **默认域名**: v4.ipv6test.app / www.baidu.com / www.qq.com
- **用法**: `perl examples/03_dns64_check.pl [DNS1] [DNS2] ...`
- **输出**: 合成地址检测 + 嵌入 IPv4 提取（如 `64:ff9b:0:0:0:0:12f4:3c7c → 18.244.60.124`）

### 04_reverse_dns.pl — 反向DNS解析（PTR）
- **功能**: IP 地址 → 域名（支持 IPv4 in-addr.arpa 和 IPv6 ip6.arpa）
- **默认查询IP**: 8.8.8.8 / 114.114.114.114 / 223.5.5.5 / 119.29.29.29 / Google&阿里 IPv6
- **用法**: `perl examples/04_reverse_dns.pl [DNS地址]`
- **输出**: PTR 记录（如 `8.8.8.8 → dns.google`）

---

## ⚙️ 自定义默认配置（想改默认值时）

每个脚本顶部有配置区，修改即可（不改也行，直接传参更简单）：

```perl
# 默认DNS服务器（01/04）——命令行参数 > 环境变量DNS_SERVER > 默认值
my $DNS_SERVER = $ARGV[0] || $ENV{DNS_SERVER} || "222.172.200.68";

# 默认DNS列表（02/03）
@DNS_SERVERS = ( { name => "云南电信DNS", address => "222.172.200.68" }, ... );

# 默认测试域名/IP（01/02/03/04）
my @DOMAINS = ("www.baidu.com", ...);
```

---

## ⚡ 效率说明

- 每个域名查询超时 **2~3 秒**（01 为 2 秒，02/03/04 为 3 秒），无响应自动跳过
- 单次运行通常 **1~5 秒** 完成（取决于 DNS 响应速度）
- 测试均使用 UDP 53 标准 DNS 查询，无攻击性

---

## 📝 注意事项

1. **v4/v6 双栈**：DNS 地址自动识别，IPv4/IPv6 混传均可
2. **`uninitialized value` 警告**：已通过 `IPPROTO_UDP` 硬编码修复，正常环境不再出现
3. **沙箱限制**：沙箱中 UDP 出站（非 53）受限，DNS 查询（53 端口）不受影响
4. **想测运营商/批量场景**：用 `bash dns-preset.sh`（预设快捷）或 `bash full.sh/lite.sh`（完整测试）
5. **完整方法论**：见 [docs/TEST_METHOD.md](../docs/TEST_METHOD.md)，AI 操作见 [docs/AI_GUIDE.md](../docs/AI_GUIDE.md)
