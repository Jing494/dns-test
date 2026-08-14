# 沙箱环境使用指南

> **适用对象**: AI助手 / 开发者  
> **最后更新**: 2026-08-14  
> 📍 目录可自由放置（脚本相对定位），本文示例路径 `/workspace/dns-test` 为当前环境默认，路径不同请替换。  

---

## 一、环境能力概览

| 能力 | 状态 | 说明 |
|------|------|------|
| Perl Socket (UDP) | ✅ 可用 | 可发送自定义UDP数据包 |
| DNS查询 (UDP 53) | ✅ 可用 | 支持自定义DNS查询脚本 |
| dig / host 命令 | ✅ 可用 | 标准DNS查询工具 |
| ping / ping6 | ✅ 可用 | ICMP连通性测试 |
| TCP出站连接 | ❌ 受限 | 仅HTTP(80)可能成功，其他端口被过滤 |
| UDP出站(非53) | ❌ 受限 | 仅UDP 53(DNS)可用 |
| nc / netcat | ❌ 不可用 | 无法测试任意端口 |
| IP定位API | ❌ 被block | 无法自动查询IP归属地 |
| fetch网页 | ⚠️ 不稳定 | 部分网站可访问，部分被robots.txt阻止 |

---

## 二、可以做的事

### 1. DNS解析测试 ✅
- A记录 / AAAA记录 / PTR记录查询（v4/v6 双栈）
- 多DNS服务器对比测试
- DNS64合成记录检测
- 反向DNS解析（含 IPv6 ip6.arpa）

### 2. 基础连通性测试 ✅
- ICMP ping测试
- DNS服务器可达性验证

### 3. 批量域名解析 ✅
- 同时测试多个域名
- 统计解析成功率和劫持情况

---

## 三、不能做的事

### 1. 端口连通性测试 ❌（沙箱限制，真机可用）
```bash
# 以下命令在沙箱无法工作：
nc -zvu 1.2.3.4 4500    # nc不存在
# 端口测试脚本的UDP发包在沙箱会被静默丢弃（send失败）
```

### 2. 完整TCP连接 ❌
- 除HTTP(80)外，TCP连接到其他端口会被沙箱过滤

### 3. IP自动定位 ❌
- ip-api.com, ipinfo.io 等API被robots.txt阻止
- 只能通过搜索引擎间接获取

### 4. 完整网页抓取 ❌
- 部分网站无法访问
- MCP fetch工具不稳定

---

## 四、Perl DNS脚本注意事项（2026-08-09 更新）

> 工具集已统一修复以下问题，新脚本请遵循：

### 正确的socket创建方式
```perl
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);

# UDP socket（用 IPPROTO_UDP 硬编码，不要用 getprotobyname）
socket($sock, $family, SOCK_DGRAM, IPPROTO_UDP) or die;

# TCP socket
socket($sock, AF_INET, SOCK_STREAM, IPPROTO_TCP) or die;
```

> ⚠️ **不要用 `getprotobyname('udp')`**：沙箱中返回 undef，会触发 "uninitialized value in socket" 警告（旧版脚本遗留问题，已全部修复为硬编码常量）。

### 正确的地址转换（v4/v6 自动识别）
```perl
# 自动识别IPv4/IPv6，返回 (sockaddr, family, error)
sub dns_sockaddr {
    my ($addr, $port) = @_;
    if ($addr =~ /^\d{1,3}(?:\.\d{1,3}){3}$/) {
        my $ip = inet_aton($addr);
        return (undef, undef, "IPv4地址格式无效: $addr") unless defined $ip;
        return (pack_sockaddr_in($port, $ip), AF_INET, undef);
    }
    my $ip = inet_pton_ipv6($addr);
    return (undef, undef, "IPv6地址格式无效: $addr") unless defined $ip;
    return (pack("S n N a16 N", AF_INET6, $port, 0, $ip, 0), AF_INET6, undef);
}
```

> ⚠️ `sockaddr_in($port, $addr)` 在**列表上下文**会返回两个值，必须用 `pack_sockaddr_in`（标量上下文）或显式 `scalar()`。

### 避免的陷阱
1. **不要使用 `inet_pton`** — 该函数在沙箱Perl中不可用，用 `inet_aton`（v4）/ 自实现 `inet_pton_ipv6`（v6）代替
2. **不要使用 `IO::Socket::INET6`** — 模块不存在
3. **不要使用 `Time::HiRes`** — 模块不存在
4. **不要使用 `Socket6`** — 模块不存在
5. **UDP recv 必须设置 SO_RCVTIMEO** — 否则无响应时永久阻塞（已全部修复）

---

## 五、工具集结构（dns-test/）

> 完整目录树（含每文件一句话说明）见 [CODE_WIKI.md](./CODE_WIKI.md#三目录结构)（权威单一来源）。以下为概览：

```
dns-test/
├── dns-test.sh / dns-preset.sh     # 用户入口（交互引导 / 预设快捷测试）
├── full.sh / lite.sh               # 基础测试（完整版 16 项 / 精简版 10 项）
├── compare.sh / trends.sh          # 多DNS对比 / 历史趋势洞察
├── verify.sh / smoke_test.sh       # 自检工具（一键验证 / 冒烟测试）
├── install.sh / release.sh         # 安装 / 打包发布
├── lib/                            # 公共库（core.sh / compat.sh / plugins.sh / DNSUtil.pm）
├── tests/                          # 单元测试（perl 18 + bash 9 + 4 + 13 + 8 用例）
├── docs/                           # 技术文档
├── tools/                          # 专项测试（vowifi/ / network/）
├── examples/                       # 通用示例脚本（4 个 Perl）
├── .github/workflows/              # CI（ubuntu + macOS 双平台矩阵）
└── results/ / trends/              # 测试结果 / 趋势产物（可选，不入库）
```

---

## 六、快速开始

### 统一入口
```bash
# 交互引导（推荐）
bash dns-test.sh

# 非交互（自动精简版+单DNS，防超时）
bash dns-test.sh 8.8.8.8 </dev/null
```

### 云南电信 DNS 测试（默认目标）
```bash
# 精简版（默认测云南电信4个DNS；注意多DNS会串行跑，建议加索引参数）
bash lite.sh 222.172.200.68 0

# 完整版（单DNS，避免超时）
bash full.sh 222.172.200.68 0
```

### 专项测试
```bash
# VoWiFi 全域名解析
perl tools/vowifi/01_resolve_vowifi.pl 222.172.200.68

# 路由器DNS转发测试（对比云南电信省级DNS）
perl tools/vowifi/03_test_router_dns.pl 192.168.1.1

# 示例：反向解析（v4/v6均可）
perl examples/04_reverse_dns.pl
```

### 使用dig快速验证
```bash
# A记录查询
dig @222.172.200.68 www.baidu.com A

# AAAA记录查询
dig @240e:52:4800::8888 www.baidu.com AAAA

# 反向解析
dig @222.172.200.68 -x 223.5.5.5

# 查看DNS64合成
dig @2001:4860:4860::6464 www.example.com AAAA
```

### 最新实测结果（2026-08-09）
- 云南电信 4 个 DNS：lite **100%**（53/53），可用性 4/4
- 223.5.5.5 完整版：**96%**（74/77，劫持检测修复后）
- 114.114.114.114 完整版：94%（73/77）

详细的测试方法论和评判标准请参考: [TEST_METHOD.md](./TEST_METHOD.md)

---

## 七、常见问题

**Q: 为什么TCP连接失败？**  
A: 沙箱环境限制了非DNS端口的出站连接，这是安全策略。端口测试请在真机运行。

**Q: 为什么端口测试的UDP发送失败？**  
A: 沙箱 UDP 出站（非53）被静默丢弃，属正常限制；真机无此问题。

**Q: 如何查询IP归属地？**  
A: 无法直接查询，需要通过搜索引擎间接获取。

**Q: 为什么有些网页fetch失败？**  
A: 部分网站有robots.txt限制，或MCP工具不稳定。

---

## 八、安全提示

- 沙箱环境是隔离的，可以自由测试
- 不要尝试突破网络限制
- DNS查询是安全的，不会泄露敏感信息
- 测试脚本仅发送标准DNS查询，无攻击性
