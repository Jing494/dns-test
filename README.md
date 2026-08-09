# 🌐 DNS/网络测试工具集

## 📌 简介
本工具集是统一管理的DNS/网络测试工具合集，包含完整的DNS基准测试、专项功能测试、通用示例脚本和技术文档，支持自定义DNS参数传入，覆盖VoWiFi、DNS64、反向解析等专业测试场景。

特性：
- 统一入口智能引导，支持基础测试/专项测试分类选择
- 所有脚本支持自定义DNS参数，v4/v6混合都支持
- 内置超时优化，逐个DNS运行避免卡顿
- 完整的技术文档，快速上手无门槛
- 所有内容统一管理，结构清晰

---

## 📂 目录结构
```
dns-test/
├── README.md                   # 总说明文档（你当前看的这个）
├── dns-test.sh                 # 统一入口脚本（推荐使用）
├── dns-preset.sh               # DNS预设快捷测试（云南电信/阿里/腾讯一键测）
├── full.sh/lite.sh             # DNS基础测试入口
├── lib/core.sh                 # 公共核心库（变量/函数/测试逻辑）
├── docs/                       # 详细技术文档
│   ├── TEST_METHOD.md          # DNS测试方法论/评分标准
│   └── SANDBOX_GUIDE.md        # 沙箱环境使用指南
├── examples/                   # 通用示例脚本
│   ├── README.md               # 示例说明
│   ├── 01_dns_query.pl         # 基础DNS查询
│   ├── 02_multi_dns_compare.pl # 多DNS对比测试
│   ├── 03_dns64_check.pl       # DNS64支持检测
│   └── 04_reverse_dns.pl       # 反向DNS解析
├── tools/                      # 专项测试工具
│   ├── vowifi/                 # VoWiFi专项测试
│   │   ├── 01_resolve_vowifi.pl    # VoWiFi全域名解析
│   │   ├── 02_vowifi_verify.pl     # VoWiFi多DNS交叉验证
│   │   └── 03_test_router_dns.pl   # 路由器DNS转发测试
│   └── network/                # 通用网络测试
│       └── 01_port_test.pl         # 端口连通性测试
└── results/                    # 测试结果存储目录（可选）
```

---

## 🚀 快速使用

### 1. 使用统一入口（推荐）
直接运行入口脚本，按引导选择即可：
```bash
# 测试默认云南电信DNS
bash dns-test.sh

# 测试自定义DNS
bash dns-test.sh 8.8.8.8

# 测试多个自定义DNS
bash dns-test.sh 8.8.8.8 114.114.114.114 222.172.200.68
```
运行后会引导选择：
- 如果选基础测试：直接选择完整版/精简版
- 如果选专项测试：摆出VoWiFi/端口测试/反向解析等专业测试选项
- **交互模式下不传参数时，会先让你选择DNS组（1云南电信 / 2阿里 / 3腾讯 / 4全部）**

### 1.5 预设快捷测试
```bash
bash dns-preset.sh                 # 云南电信 lite
bash dns-preset.sh ali             # 阿里云 lite
bash dns-preset.sh tencent full 0  # 腾讯完整版第1个DNS
bash dns-preset.sh all lite        # 全部预设（11个DNS）
```

### 2. 直接运行指定脚本
```bash
# 基础测试（不传参数默认云南电信DNS，传参数用自定义DNS）
bash full.sh            # 完整版基础测试
bash full.sh 8.8.8.8    # 用自定义DNS跑完整版
bash full.sh 8.8.8.8 114.114.114.114 0  # 测试多个DNS中的第1个（避免超时）
bash full.sh 8.8.8.8 114.114.114.114 1  # 测试多个DNS中的第2个
bash lite.sh            # 精简版基础测试

# 专项测试
perl tools/vowifi/01_resolve_vowifi.pl 8.8.8.8              # VoWiFi解析
perl tools/vowifi/02_vowifi_verify.pl 8.8.8.8 114.114.114.114 # VoWiFi交叉验证
perl tools/vowifi/03_test_router_dns.pl 192.168.1.1        # 路由器DNS测试
perl tools/network/01_port_test.pl 192.0.2.1 4500 udp # 端口测试

# 通用示例
perl examples/01_dns_query.pl 8.8.8.8                      # 基础查询
perl examples/02_multi_dns_compare.pl 8.8.8.8 114.114.114.114 # 多DNS对比
perl examples/03_dns64_check.pl 2001:4860:4860::6464        # DNS64检测
perl examples/04_reverse_dns.pl 8.8.8.8                     # 反向解析
```

### 默认DNS列表
| 地址 | 名称 |
|------|------|
| 240e:52:4800::8888 | 云南电信IPv6-DNS-1 |
| 240e:52:4000::8888 | 云南电信IPv6-DNS-2 |
| 222.172.200.68 | 云南电信IPv4-DNS-1 |
| 61.166.150.123 | 云南电信IPv4-DNS-2 |
| 223.5.5.5 / 223.6.6.6 | 阿里云公共DNS (v4) |
| 2400:3200::1 / 2400:3200:baba::1 | 阿里云公共DNS (v6) |
| 119.29.29.29 | 腾讯DNSPod (v4) |
| 2402:4e00:: / 2402:4e00:1:: | 腾讯DNSPod (v6) |

> 阿里/腾讯预设已内置（`lib/core.sh`），入口交互可选，或用 `dns-preset.sh` 一键调用。

### 效率提示
- 测试前会自动做**DNS可达性预检**，不可达的DNS快速跳过（省90%时间）
- A记录批量测试为**8并发并行**查询，单DNS耗时大幅降低
- 稳定性轮次可用环境变量调小：`STAB_ROUNDS=5 bash lite.sh 8.8.8.8`

---

## 📋 测试维度说明

### 基础测试（lite/full）
#### 精简版（9项，约3-5分钟）
1. A记录批量测试（25个国内+国际域名）
2. AAAA记录批量测试（8个域名）
3. 3GPP/VoWiFi域名测试（2个核心域名，信息项不计分）
4. 其他记录类型测试（MX/NS/TXT）
5. 稳定性压力测试（20次连续查询）
6. 异常/边界测试（NXDOMAIN）
7. 实际连通性测试（Ping）
8. IPv4/IPv6解析一致性
9. 运营商域名解析测试（4个三大运营商域名）

#### 完整版（15项，约8-10分钟）
在精简版基础上增加：
10. DNSSEC安全扩展测试
11. EDNS Client Subnet (ECS)测试
12. 反向DNS解析(PTR)测试
13. TTL值分析
14. DNS劫持检测（与阿里DNS对比）
15. 递归/迭代查询类型测试

### 专项测试
| 测试类型 | 功能说明 | 默认测试目标 |
|---------|---------|-------------|
| VoWiFi域名全解析 | 测试所有3GPP标准VoWiFi域名的A/AAAA记录解析 | 云南电信/CNNIC公共DNS |
| VoWiFi交叉验证 | 对比多个DNS的VoWiFi解析结果，检查一致性 | 6个主流公共DNS |
| 路由器DNS转发测试 | 验证路由器DNS是否将请求转发到省级DNS（云南电信） | 192.168.1.1/192.168.2.1 |
| 端口连通性测试 | 测试ePDG/VoWiFi相关端口的TCP/UDP连通性 | ePDG服务器4500/500端口 |
| 通用示例 | 基础查询、多DNS对比、DNS64检测、反向解析 | 云南电信DNS |

---

## 📖 文档说明
- 详细的测试方法论和评分标准见：[docs/TEST_METHOD.md](./docs/TEST_METHOD.md)
- **AI助手操作手册（先问DNS/版本/专项，ask工具两种模式，**日志截断处理见第八章**）见：[docs/AI_GUIDE.md](./docs/AI_GUIDE.md)**
- 沙箱环境使用说明、限制见：[docs/SANDBOX_GUIDE.md](./docs/SANDBOX_GUIDE.md)
- 通用示例脚本使用说明见：[examples/README.md](./examples/README.md)

---

## ❓ 常见问题

### Q: 运行超时怎么办？
完整版测试单DNS约2-4分钟，多DNS完整跑完会超过大多数调用超时限制。解决方案：
- **推荐**：命令末尾加索引参数，只测第N个DNS：`bash full.sh 8.8.8.8 114.114.114.114 0`
- 或运行入口脚本，选择基础测试后选"指定测试某一个DNS"
- 非交互模式（无终端）自动降级为精简版+仅第1个DNS，不会超时

### Q: 测试结果中的扣分项影响使用吗？
- PTR解析扣分：国内IP大多无反向解析，属于正常现象，不影响使用
- 劫持检测扣分：CDN域名解析不同是负载均衡正常现象
- DNSSEC扣分：不是所有域名都部署了DNSSEC，轻微影响
- VoWiFi域名返回127.0.0.1：表示该运营商未部署ePDG，属于正常现象

### Q: 如何验证路由器DNS是否转发到省级DNS？
运行路由器DNS转发测试（`perl tools/vowifi/03_test_router_dns.pl 192.168.1.1`），脚本会先取云南电信省级DNS的解析结果作为基准，再对比路由器DNS的解析结果——完全一致则说明路由器将DNS请求转发到了省级DNS；不一致则可能是自建DNS或转发了其他DNS。

### Q: 支持哪些操作系统？
支持所有安装了`dig`、`ping`工具的Linux/macOS系统，Perl脚本需要Perl 5.10+环境。

### Q: 可以测试多少个DNS？
支持任意数量的DNS。单个DNS可完整跑完；多个DNS建议用索引参数逐个测（`bash full.sh A B 0`、`bash full.sh A B 1`），避免单次调用超时。

---

## 🔄 更新记录
- 2026-08-09（第十五轮）：自定义性增强——DEFAULT_DNS_CSV覆盖默认DNS组、PROVINCE_DNS覆盖路由器对比基准、PRESET_DNS_CSV自定义预设、examples支持DNS_SERVER/DNS_LIST环境变量；修复03自定义基准全空时数组解引用报错
- 2026-08-09（第十四轮）：新增[7b]IPv6实际连通性测试（ping6，平台适配ping6/ping -6，无IPv6环境自动跳过不计分）；实测本机IPv6到百度/QQ/B站/腾讯全部通畅（30~76ms）；lite评分项63→64，full 77→78；云南电信完整版复测96~97%稳定
- 2026-08-09（第十三轮）：AI_GUIDE新增"脚本排障与异常处理"（排查顺序/报错速查）+"环境差异与评分波动"（假失败清单/波动阈值/对比方法论）；云南电信完整版+路由器转发结果归档TEST_METHOD
- 2026-08-09（第十二轮）：AI_GUIDE新增"日志截断与结果确认"章（看结尾不看开头、三标记确认法、6种截断补救手段、真异常清单）
- 2026-08-09（第十一轮）：dig前置检查、版本号v2026.08、results/保存示例、测试结束总耗时统计
- 2026-08-09（第十轮）：可达性预检改双域名防海外误判；STAB_ROUNDS参数校验防除零；劫持基准探测域名优化（alidns.com）；README更新记录补全；SANDBOX_GUIDE目录加AI_GUIDE
- 2026-08-09（第九轮）：新增docs/AI_GUIDE.md（AI操作手册：先问DNS/版本/专项，ask/无ask双模式）；选组4+完整版自动限单DNS防超时；自定义DNS显示地址；清理未使用模块
- 2026-08-09（第八轮）：macOS ping -W平台区分（防连通性误判）；trap临时目录清理；稳定性进度提示；01 AAAA轮跳过超时域名；入口read全部加超时
- 2026-08-09（第七轮）：新增阿里/腾讯DNS预设组+dns-preset.sh一键脚本+入口交互选组；DNS可达性预检（不可达秒跳过）；A/AAAA/运营商/其他/DNSSEC/ECS/PTR/TTL/劫持全面并行化（full单DNS从2~4分钟降至约10秒）；01/02默认补IPv4；chmod 755；ECS subnet参数化
- 2026-08-09（第六轮）：劫持检测白名单扩充+基准降级IPv4（qq.com误报修复，评分94→96%）、grep -oP改sed兼容（macOS可用）、IPv6反向解析(ip6.arpa)、UDP探测提示、死代码清理、examples默认DNS回云南电信、路由器测试重构为对比云南电信省级DNS
- 2026-08-09（第五轮）：VoWiFi解析A/AAAA分开统计（修复成功率超100%）、端口测试TCP改非阻塞connect防卡死、3GPP域名改信息项不扣分、PTR解析器支持压缩指针（8.8.8.8→dns.google）、稳定性轮次支持环境变量、索引参数判定加保护
- 2026-08-09（第四轮）：修复v4/v6混合支持（6个Perl脚本补IPv4双栈），协议号硬编码消除环境警告，端口测试UDP加超时防卡死，非交互模式防超时降级，修正README目录结构
- 2026-08-09（第三轮）：整合所有DNS/网络测试工具到统一目录，添加智能引导入口，所有脚本支持自定义参数
- 2026-08-08：初始版本，完成云南电信DNS基准测试
