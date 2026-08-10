# 🌐 DNS/网络测试工具集

> 🌐 **English**：[README.en.md](./README.en.md) ｜ **中文**：本文档

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Release: v2026.08](https://img.shields.io/badge/Release-v2026.08-blue.svg)
![Platform: Linux/macOS/WSL](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20WSL-green.svg)
![Bash 4+](https://img.shields.io/badge/Bash-4%2B-blue.svg)
![Perl 5.10+](https://img.shields.io/badge/Perl-5.10%2B-blue.svg)

> 📍 **目录可自由放置**：脚本全部相对定位（`BASH_SOURCE`），拉取/复制到任意目录都能运行。文档示例中的 `dns-test/` 路径请按你的实际目录替换。

> 🔒 **隐私说明**：本仓库涉及运营商基础设施 IP 的内容统一使用 **RFC 5737 文档保留地址（192.0.2.x）** 占位，**非真实地址**；示例仅使用公共 DNS 与私网地址，不含任何运营商内部信息。

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
├── README.en.md                # English overview（精简英文简介）
├── dns-test.sh                 # 统一入口脚本（推荐使用）
├── dns-preset.sh               # DNS预设快捷测试（云南电信/阿里/腾讯一键测）
├── smoke_test.sh               # 自动化冒烟测试（一键验证核心功能）
├── full.sh/lite.sh             # DNS基础测试入口
├── lib/core.sh                 # 公共核心库（变量/函数/测试逻辑）
├── docs/                       # 详细技术文档
│   ├── AI_GUIDE.md             # AI助手操作手册（先问DNS/版本/专项，交互工具双模式）
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
│   │   ├── 03_test_router_dns.pl   # 路由器DNS转发测试
│   │   └── carrier_epdg.pl         # 运营商ePDG部署检测（电信/移动/联通/广电）
│   └── network/                # 通用网络测试
│       ├── 01_port_test.pl         # 端口连通性测试
│       └── doh_dot_check.sh        # DoH/DoT 支持检测
└── results/                    # 测试结果存储目录（可选）
└── LICENSE                     # MIT 开源许可证
```

---

## 🚀 快速使用

### 0. 获取与安装

**获取代码**（三种方式）：
```bash
# 方式1: git clone（推荐，含完整提交历史）
git clone https://github.com/Jing494/dns-test.git
cd dns-test

# 方式2: Releases 下载（免 git，直接拿成品包）
#   前往 https://github.com/Jing494/dns-test/releases
#   下载 dns-test-v2026.08.tar.gz 后解压即可

# 方式3: 下载 ZIP（GitHub 页面 → Code → Download ZIP 后解压）
```

**依赖安装**（按你的系统执行）：
| 系统 | 命令 | 需要什么 |
|------|------|---------|
| Ubuntu/Debian/WSL | `sudo apt install dnsutils curl` | dig + curl（curl 可选，用于 DoH 实测） |
| CentOS/RHEL/Fedora | `sudo yum install bind-utils curl` | 同上 |
| macOS | `brew install bind curl` | 同上 |

> dig 必需（来自 dnsutils/bind-utils；**DoT 检测需 bind 9.18+** 才支持 `dig +tls`）；perl 一般系统自带（专项测试需要）；curl 可选（无 curl 时 DoH 检测降级为端口级）。

**快速验证（5 分钟确认可用）**：
```bash
bash smoke_test.sh         # 自动化 14 项验证，全绿 = 环境 OK
bash lite.sh 223.5.5.5 0   # 测一个 DNS 看看输出
```

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
perl tools/network/01_port_test.pl 223.5.5.5 53 udp # 端口测试

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

### 运行环境选择指引（沙箱 vs 真机）

脚本运行时会**自动检测环境**并标注（`🌐 环境: Linux/macOS | dig✅... | IPv6:可用/不可用`），结果可回溯。

| 测试类型 | 沙箱（AI 调用） | 真机（用户自测） |
|---------|----------------|-----------------|
| DNS 解析/对比/评分（lite/full） | ✅ 完整 | ✅ 完整 |
| 运营商 ePDG 检测 | ✅ 完整（用省级DNS） | ✅ 完整（用自己省DNS） |
| IPv6 连通性 [7b] | ⚠️ 看网络（无IPv6自动跳过） | ✅ 完整（家宽一般支持） |
| 路由器转发检测 | ⚠️ 非本网，结果仅供参考 | ✅ 推荐（测自己路由器） |
| 端口连通性 | ⚠️ UDP受限，多显示不可达 | ✅ 完整 |

> 提示：结果头部有环境标注，AI 或用户对照上表即可判断哪些结果可信、哪些受环境限制。

### 效率提示
- 测试前会自动做**DNS可达性预检**，不可达的DNS快速跳过（省90%时间）
- A记录批量测试为**8并发并行**查询，单DNS耗时大幅降低
- 稳定性轮次可用环境变量调小：`STAB_ROUNDS=5 bash lite.sh 8.8.8.8`


## 📋 测试维度说明

### 基础测试（lite/full）
#### 精简版（10项，约9秒/DNS）
1. A记录批量测试（25个国内+国际域名）
2. AAAA记录批量测试（8个域名）
3. 3GPP/VoWiFi域名测试（电信/移动/联通代表域名，信息项不计分）
4. 其他记录类型测试（MX/NS/TXT）
5. 稳定性压力测试（20次连续查询）
6. 异常/边界测试（NXDOMAIN）
7. 实际连通性测试（Ping IPv4）
7b. IPv6实际连通性测试（ping6，无IPv6环境自动跳过）
8. IPv4/IPv6解析一致性
9. 运营商域名解析测试（4个三大运营商域名）

#### 完整版（16项，约10秒/DNS）
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
| 运营商ePDG部署检测 | 检测电信/移动/联通/广电的ePDG域名解析，判断各省份VoWiFi部署 | 云南电信DNS（可选家宽路由器） |
| DoH/DoT支持检测 | 判断DNS是否提供加密解析（有curl实测/无则端口级） | 223.5.5.5 等 |
| 通用示例 | 基础查询、多DNS对比、DNS64检测、反向解析 | 云南电信DNS |

---

## 📖 文档说明
- 英文简介见：[README.en.md](./README.en.md)（English overview）
- 详细的测试方法论和评分标准见：[docs/TEST_METHOD.md](./docs/TEST_METHOD.md)
- **AI助手操作手册（先问DNS/版本/专项，交互提问工具两种模式（命名因agent而异：ask_user等），**日志截断处理见第八章**）见：[docs/AI_GUIDE.md](./docs/AI_GUIDE.md)**
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

**Windows 用户**（不支持原生，请用以下方式）：
```bash
# 方式1: WSL（推荐，体验与Linux一致）
wsl --install                    # 首次安装WSL
wsl -d Ubuntu -- apt install dnsutils curl perl   # 装依赖
wsl -d Ubuntu -- bash smoke_test.sh               # 验证

# 方式2: Git Bash / MSYS2（部分功能可用，需自行装 dig/perl）
#   注意: DoH/DoT检测的 /dev/tcp 在Git Bash下不可靠
```
> 不建议尝试原生 cmd/PowerShell 运行——脚本依赖 bash 特性（BASH_SOURCE、/dev/tcp 等）与 GNU 工具（dig/sed/awk）。

### Q: 可以测试多少个DNS？
支持任意数量的DNS。单个DNS可完整跑完；多个DNS建议用索引参数逐个测（`bash full.sh A B 0`、`bash full.sh A B 1`），避免单次调用超时。

---

## 🔄 更新记录
- 2026-08-09（第四十五轮）：perl前置检查（core.sh 统一检查dig+perl）；smoke_test补full完整版测试（14项）；分支完整性/文件齐全/命令引用全复核通过
- 2026-08-09（第四十四轮）：安全加固——.gitignore补*.log/*报告*/*.tmp；SAVE_LOG日志与测试报告确认不随git上传；敏感IP残留清零（仅私网示例）
- 2026-08-09（第四十三轮）：安全加固——移除示例中的运营商基础设施IP（端口测试默认目标换公共DNS/私网、专项4引导示例、README/TEST_METHOD/AI_GUIDE/SANDBOX/examples文档示例全部清理）；仅保留02检测对比数据
- 2026-08-09（第四十二轮）：专项4端口测试/专项7 DoH-DoT 加交互引导（可自定义目标/DNS，回车用默认）；非交互与直接传参完全兼容（read仅交互模式）
- 2026-08-09（第四十一轮）：专项3路由器测试交互引导（入口进入可输入路由器IP+省级DNS，不锁省级）；专项菜单↔脚本对应复核全通过
- 2026-08-09（第四十轮）：DoH/DoT加入专项菜单第7项（入口可测）；README专项表补行；smoke补环境依赖报告(13项)
- 2026-08-09（第三十九轮）：DoH/DoT环境自适应——DoT v4/v6均dig+tls实测；DoH有curl则curl --doh-url实测(阿里200✅)无则端口级；沙箱装curl；md更新DoH描述；smoke补环境依赖报告(13项)
- 2026-08-09（第三十八轮）：DoH/DoT方法边界诚实化——DoT实测可区分支持与否、DoH仅端口级标注；md补SAVE_LOG详细说明(触发/位置/格式)
- 2026-08-09（第三十七轮）：DoH/DoT检测IPv6分支升级为实际dig +tls验证（不再假阳性）；smoke_test补SAVE_LOG项
- 2026-08-09（第三十六轮）：DoH/DoT检测修复——IPv6目标不再假阳性（/dev/tcp不可靠，改dig+tls验证）、支持多DNS逗号分隔、smoke补DoH/DoT项
- 2026-08-09（第三十五轮）：md全面同步——README/SANDBOX目录结构补smoke_test/doh_dot_check/carrier_epdg，AI_GUIDE命令映射、TEST_METHOD效率机制更新
- 2026-08-09（第三十四轮）：工程化——新增smoke_test.sh自动化冒烟(10项)；评分加关键指标行🔑；SAVE_LOG日志自动保存；退出码约定(0完成/1错误/2全不可达)；AI_GUIDE报告模板；域名列表CONFIG_DOMAINS外置；DoH/DoT检测脚本
- 2026-08-09（第三十三轮）：安全——DNS地址格式校验防命令注入（full/lite/preset入口拦截）；DEFAULT_DNS_NAME数量自动补齐；README补WSL支持
- 2026-08-09（第三十二轮）：端口测试补IPv6目标支持（dns_sockaddr双栈），全工具v4/v6齐
- 2026-08-09（第三十一轮）：carrier_epdg支持PROVINCE_DNS环境变量覆盖默认DNS
- 2026-08-09（第三十轮）：03路由器测试支持--分隔符直传省级基准；无参数打印用法提示
- 2026-08-09（第二十九轮）：路由器测试支持 -- 分隔符命令行直传省级基准（`perl 03.pl 192.168.1.1 -- 223.5.5.5`），优先级 -- > PROVINCE_DNS > 默认云南电信；无参数时打印用法提示；5份文档加路径可放置说明
- 2026-08-09（第二十八轮）：环境感知——print_env_info环境自检标注（full/lite/dns-test/dns-preset头部）、专项1/2/5加>4 DNS超时保护、专项3忽略DNS_LIST、README环境指引与AI_GUIDE环境行解读
- 2026-08-09（第二十七轮）：路径健壮性验证——脚本复制到任意目录可运行（BASH_SOURCE相对定位实测通过）；5份md加"目录可自由放置"说明（AI_GUIDE加执行前确认实际路径指引）
- 2026-08-09（第二十六轮）：核心代码终审全绿；索引越界提示（full/lite）
- 2026-08-09（第二十五轮）：专项1/2/5加>4 DNS超时保护；专项3修复DNS_LIST误当路由器IP
- 2026-08-09（第二十四轮）：过时描述清理——9项→10项、15项→16项、旧域名引用
- 2026-08-09（第二十三轮）：print_env_info环境自检标注上线（full/lite/dns-test/dns-preset头部）；AI_GUIDE/TEST_METHOD补环境说明
- 2026-08-09（第二十二轮）：完整性检查——print_env_info全入口覆盖、文档补环境行解读
- 2026-08-09（第二十一轮）：环境感知——README运行环境选择指引（沙箱vs真机对照表）
- 2026-08-09（第二十轮）：ePDG多DNS交叉实测（电信mnc011经省级DNS+路由器稳定解析）；01脚本过滤127.0.0.1黑洞（统计8/16→真实1/16）
- 2026-08-09（第十九轮）：MCC/MNC编码tavily核实——电信11/03/05、移动00/02/07、联通01/06/09、广电15；carrier_epdg电信组修正（删误加的mnc000）
- 2026-08-09（第十八轮）：7个不规范ePDG域名清理（chinatelecom.cn/chn/mcc460.mnc顺序反等）；md复查
- 2026-08-09（第十七轮）：ePDG多DNS可用性实测（云南电信/路由器/公共DNS交叉）
- 2026-08-09（第十六轮）：新增carrier_epdg.pl运营商ePDG部署检测（电信/移动/联通/广电，交互+传参，省级DNS/路由器，免责声明）；删除vowifi.189.cn
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
