# 🌐 DNS/网络测试工具集

> 🌐 **English**：[README.en.md](./README.en.md) ｜ **中文**：本文档

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Release: v1.7.1](https://img.shields.io/badge/Release-v1.7.1-blue.svg)
![Version: v2026.08.11](https://img.shields.io/badge/Version-v2026.08.11-blue.svg)
![Platform: Linux/macOS/WSL](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20WSL-green.svg)
![Bash 3.2+](https://img.shields.io/badge/Bash-3.2%2B-blue.svg)
![Perl 5.10+](https://img.shields.io/badge/Perl-5.10%2B-blue.svg)
[![CI](https://github.com/Jing494/dns-test/actions/workflows/smoke.yml/badge.svg)](https://github.com/Jing494/dns-test/actions)

> 📍 **目录可自由放置**：脚本全部相对定位（`BASH_SOURCE`），拉取/复制到任意目录都能运行。文档示例中的 `dns-test/` 路径请按你的实际目录替换。

> 🏷️ **版本号规则（双轨制）**：`vYYYY.MM.N` 日期式（N=当月发布序号）↔ 语义 `vX.Y`（X=主版本，重大重构才升；Y=次版本，功能更新）。补丁级修复仅递增日期式 N。

> 🔧 **最新版本**：**v1.7.1 = v2026.08.11**（在 v2026.08.11 基础上完成审阅优化：CONFIG_DOMAINS 不再 source 执行防注入、par_run 增加 dig 命令白名单、IPv6 检测改 loopback 防海外误判、lite 稳定性轮次自动减半为 10 提速、JSON 序列化优先 python3、新增计分口径单测 05）。完整版本历程（每轮）见 [docs/CHANGELOG.md](./docs/CHANGELOG.md)。

> 🔒 **隐私说明**：本仓库涉及运营商基础设施 IP 的内容统一使用 **RFC 5737 文档保留地址（192.0.2.x）** 占位，**非真实地址**；**默认 DNS 列表为公开可测试的运营商公网 DNS**，示例仅使用公共 DNS 与私网地址，不含任何运营商内部信息。

---

## ⚡ TL;DR（30 秒上手）

```bash
git clone https://github.com/Jing494/dns-test.git && cd dns-test
bash install.sh        # 缺失才装 dig/perl/curl（已齐全则跳过 sudo）
bash smoke_test.sh     # 24 项自动化验证环境
bash dns-test.sh       # 交互引导测试（或 bash lite.sh 223.5.5.5 0 快速测）
```

**快速全量自检**（真机推荐）：`bash verify.sh`——语法+shellcheck+单测+冒烟+compare+trends+专项 一键跑完，输出汇总报告（约 5 分钟）。shellcheck 为**可选依赖**：未装则该项提示跳过（不阻塞，CI 已兜底）；开发者可 `bash verify.sh --strict` 强制要求（未装算失败）。

**典型输出**（`bash lite.sh 223.5.5.5 0` 结尾）：

```
📊 综合评分: 98% (52/53 项通过)
⏱️  稳定性: 95%
```

→ 多 DNS 横向对比用 `bash compare.sh DNS1 DNS2 --html`，历史趋势用 `bash trends.sh --html`（结果存 results/、趋势存 trends/）。

## 📚 文档导航

| 文档 | 用途 |
|------|------|
| 🌐 [README.en.md](./README.en.md) | English overview |
| 🧠 [docs/AI_GUIDE.md](./docs/AI_GUIDE.md) | AI 助手操作手册（先问DNS/版本/专项，交互双模式） |
| 🧪 [docs/TEST_METHOD.md](./docs/TEST_METHOD.md) | 测试方法论 / 评分标准 / 测试维度明细 |
| 🧩 [docs/CODE_WIKI.md](./docs/CODE_WIKI.md) | 开发者代码 Wiki（架构/模块/函数/依赖/CI） |
| ❓ [docs/FAQ.md](./docs/FAQ.md) | 常见问题（含 Windows/WSL 引导） |
| 📜 [docs/CHANGELOG.md](./docs/CHANGELOG.md) | 完整变更记录（每轮） |
| 🏖️ [docs/SANDBOX_GUIDE.md](./docs/SANDBOX_GUIDE.md) | 沙箱环境使用指南 |
| 📦 [examples/README.md](./examples/README.md) | 通用示例脚本说明 |

---

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

> 完整目录树（含每文件一句话说明）见 [docs/CODE_WIKI.md](./docs/CODE_WIKI.md#三目录结构)。以下为概览：

```
dns-test/
├── dns-test.sh / dns-preset.sh     # 用户入口（交互引导 / 预设快捷测试）
├── full.sh / lite.sh               # 基础测试（完整版 16 项 / 精简版 10 项）
├── compare.sh / trends.sh          # 多DNS对比 / 历史趋势洞察
├── verify.sh / smoke_test.sh       # 自检工具（一键验证 / 冒烟测试）
├── install.sh / release.sh         # 安装 / 打包发布
├── lib/                            # 公共库（core.sh / compat.sh / plugins.sh / DNSUtil.pm）
├── tests/                          # 单元测试（perl 18 + bash 9 + 4 + 15 + 9 用例）
├── docs/                           # 技术文档（AI_GUIDE / TEST_METHOD / CODE_WIKI / FAQ / CHANGELOG / SANDBOX_GUIDE）
├── tools/                          # 专项测试（vowifi/ / network/）
├── examples/                       # 通用示例脚本（4 个 Perl）
├── .github/workflows/              # CI（ubuntu + macOS 双平台矩阵）
└── results/ / trends/              # 测试结果 / 趋势产物（可选，不入库）
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
#   下载 dns-test-v2026.08.11.tar.gz 后解压即可

# 方式3: 下载 ZIP（GitHub 页面 → Code → Download ZIP 后解压）
```

**自动安装依赖**（可选，替代手动命令）：
```bash
bash install.sh          # 自动检测 apt/yum/dnf/brew，缺失才装必需依赖 dig + perl + curl（已齐则跳过sudo）
bash install.sh --all    # 连可选依赖 shellcheck 一起装（verify.sh 静态检查用）
```

**依赖安装**（按你的系统执行）：
| 系统 | 命令 | 需要什么 |
|------|------|---------|
| Ubuntu/Debian/WSL | `sudo apt install dnsutils curl` | dig + curl（curl 可选，用于 DoH 实测） |
| CentOS/RHEL/Fedora | `sudo yum install bind-utils curl` | 同上 |
| macOS | `brew install bind curl` | 同上 |

> dig 必需（来自 dnsutils/bind-utils；**DoT 检测需 bind 9.18+** 才支持 `dig +tls`）；perl 一般系统自带（专项测试需要）；curl 可选（无 curl 时 DoH 检测降级为端口级）。

> 🧰 **可选依赖 shellcheck**（shell 静态检查，仅 `verify.sh` 使用）：不装不影响主功能——verify 会提示跳过该项，代码质量已由 CI 兜底（GitHub Actions 每轮自动检查）。想装：`bash install.sh --all`，或按系统 `sudo apt-get install -y shellcheck` / `brew install shellcheck` / `sudo pacman -S shellcheck` / `sudo zypper install -y ShellCheck`。

**快速验证（5 分钟确认可用）**：
```bash
bash smoke_test.sh         # 自动化 24 项验证，全绿 = 环境 OK
bash lite.sh 223.5.5.5 0   # 测一个 DNS 看看输出
```

### 1. 使用统一入口（推荐）
直接运行入口脚本，按引导选择即可：
```bash
# 测试默认DNS
bash dns-test.sh

# 测试自定义DNS
bash dns-test.sh 8.8.8.8

# 测试多个自定义DNS
bash dns-test.sh 8.8.8.8 114.114.114.114 222.172.200.68
```
运行后会引导选择：
- 如果选基础测试：直接选择完整版/精简版
- 如果选专项测试：摆出VoWiFi/端口测试/反向解析等专业测试选项
- **交互模式下不传参数时，会先让你选择DNS组（1默认 / 2阿里 / 3腾讯 / 4全部）**

### 1.5 预设快捷测试
```bash
bash dns-preset.sh                 # 默认 lite
bash dns-preset.sh ali             # 阿里云 lite
bash dns-preset.sh tencent full 0  # 腾讯完整版第1个DNS
bash dns-preset.sh all lite        # 全部预设（11个DNS）
```

### 2. 直接运行指定脚本
```bash
# 基础测试（不传参数默认DNS组，传参数用自定义DNS）
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

# 多DNS对比（根目录compare.sh，推荐：并行+延迟中位数+推荐结论）
bash compare.sh 223.5.5.5 119.29.29.29                     # 纯文本对比
bash compare.sh 223.5.5.5 119.29.29.29 --html               # 生成 results/report.html（响应式）
bash compare.sh 223.5.5.5 119.29.29.29 --full               # 用完整版测试对比（77~78项/DNS）
bash compare.sh 223.5.5.5 --no-save                         # 不保存JSON结果
#   环境变量: COMPARE_MAX_CONCURRENCY=3  lite并行数（设1串行最稳）
#   输出: results/compare-<时间戳>.json 结构化结果（历史趋势积累用）

# DNS趋势洞察（基于compare历史JSON聚合，需先积累至少2次compare数据）
bash trends.sh                              # 全部DNS趋势总览（文本）
bash trends.sh --html --csv                 # 生成 trends/report.html（SVG折线图）+ trends.csv
bash trends.sh --detail --limit 5           # 每个DNS列最近5条明细
bash trends.sh --since 2026-08-01           # 只看该日期后的数据
bash trends.sh --cron 223.5.5.5 119.29.29.29 # 先采集(跑compare)再聚合——crontab自动积累用
#   定时采集示例（每天凌晨2:30自动测并更新趋势）:
#   crontab -e 加一行:  30 2 * * * cd /path/to/dns-test && bash trends.sh --cron 223.5.5.5 119.29.29.29 >> trends/cron.log 2>&1
#   环境变量: TRENDS_DIR(默认trends/)  COMPARE_RESULTS_DIR(默认results/)
```

### 默认DNS列表
| 地址 | 名称 |
|------|------|
| 240e:52:4800::8888 | 默认IPv6-DNS-1 |
| 240e:52:4000::8888 | 默认IPv6-DNS-2 |
| 222.172.200.68 | 默认IPv4-DNS-1 |
| 61.166.150.123 | 默认IPv4-DNS-2 |
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

**基础测试（lite/full）测试项明细与评分标准**详见 [docs/TEST_METHOD.md](./docs/TEST_METHOD.md) 第四章（精简版 10 项/完整版 16 项，评分项 54/78 点）。

### 专项测试
| 测试类型 | 功能说明 | 默认测试目标 |
|---------|---------|-------------|
| VoWiFi域名全解析 | 测试所有3GPP标准VoWiFi域名的A/AAAA记录解析 | 默认/CNNIC公共DNS |
| VoWiFi交叉验证 | 对比多个DNS的VoWiFi解析结果，检查一致性 | 6个主流公共DNS |
| 路由器DNS转发测试 | 验证路由器DNS是否将请求转发到省级DNS（默认示例为运营商DNS） | 192.168.1.1/192.168.2.1 |
| 端口连通性测试 | 测试ePDG/VoWiFi相关端口的TCP/UDP连通性 | ePDG服务器4500/500端口 |
| 运营商ePDG部署检测 | 检测电信/移动/联通/广电的ePDG域名解析，判断各省份VoWiFi部署 | 默认DNS（可选家宽路由器） |
| DoH/DoT支持检测 | 判断DNS是否提供加密解析（有curl实测/无则端口级） | 223.5.5.5 等 |
| 通用示例 | 基础查询、多DNS对比、DNS64检测、反向解析 | 默认DNS |

### 🧩 插件机制（专项菜单动态驱动）
专项菜单由 `tools/manifest.sh` 注册表驱动：`dns-test.sh` 选"专项测试"时，自动列出注册表中的全部插件（新专项**自动出现**，主脚本零改动）。**新增一个专项只需两步**：
1. 把脚本放进 `tools/<目录>/`（或 `examples/`）
2. 在 `tools/manifest.sh` 的 `PLUGIN_ITEMS` 加一行：`插件id|脚本文件名|菜单显示名|执行器(perl/bash)|引导提示(可空)|透传DNS(1/0, 默认1)`
   （同时在文件底部补 `PLUGIN_DIR_<id>="目录"` 映射）

字段说明：第5字段`引导提示`非空时，执行前会 `read -t 30` 询问一次；**参数策略三态**——引导输入非空→独占作为脚本参数；空引导+第6字段`透传DNS=1`→透传当前 DNS 组（如 DoH"回车用当前组"）；空引导+`透传DNS=0`→无参数执行（如 carrier_epdg/路由器/端口测试，用脚本默认）。执行器白名单仅 `perl`/`bash`。执行时从项目根调用 `目录/脚本`（不 cd，脚本内部相对路径不受影响）。详见 `lib/plugins.sh` 头注释。

---

## 📋 已知限制（诚实说明）

已知限制（DoH/DoT 检测降级、Windows、IPv6、运营商 ePDG、网络波动等）见 **[docs/FAQ.md](./docs/FAQ.md#已知限制诚实说明)**。

---

## ❓ 常见问题

常见问题（运行超时 / 扣分项影响 / 路由器转发验证 / 系统支持 / DNS数量限制）见 **[docs/FAQ.md](./docs/FAQ.md)**。

---
## 🗺️ Roadmap（未来计划）

按优先级排序：

- **单元测试（✅ 已完成）**：`lib/DNSUtil.pm` 提取 DNS 纯函数（9 个：sockaddr/域名编码/响应解析/PTR/反向名/IPv6 展开等）+ `tests/01_dnsutil.t` 18 用例（perl）+ `tests/02_plugins.sh` 9 用例（bash 轻量断言：插件注册表/参数策略/拦截）+ `tests/03_dig_target.sh` 4 用例（IPv6 加方括号）+ `tests/04_core_functions.sh` 18 用例（地址校验/响应判断/CDN 判定/入口参数解析）+ `tests/05_run_common_tests.sh` 9 用例（lite 计分口径/稳定性降轮/CONFIG_DOMAINS 安全解析/dig @server 前缀回归），9 个 perl 脚本全量迁移 DNSUtil，已接入 verify + CI strict；运行 `perl -Ilib tests/01_dnsutil.t` / `bash tests/02_plugins.sh` / `bash tests/03_dig_target.sh` / `bash tests/04_core_functions.sh` / `bash tests/05_run_common_tests.sh`
  - bats 评估结论（2026-08-13）：**不引入**——现有 perl 单测 + smoke/verify 集成已够，bash 纯函数用零依赖轻量断言（tests/02_plugins.sh）补充，避免增加依赖
- **par_run 通用化（✅ 已完成）**：PARR_MAX 环境变量可调并发数（默认 8），临时目录自动注册 TMPDIR_LIST 统一清理
- **trends svg_chart 模板化**：HTML/SVG 内联字符串改 heredoc/独立模板文件（当前功能正常，纯可读性优化）
- **JSON 序列化增强**：compare 结果结构复杂化时引入 jq（当前 JSON 自产自销且格式固定，echo 拼接足够，避免增加依赖）

---

## 🔄 更新记录

完整变更历史（每轮）见 **[docs/CHANGELOG.md](./docs/CHANGELOG.md)**。
