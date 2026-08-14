# DNS/网络测试工具集 — Code Wiki

> 本文档是项目的结构化代码 Wiki，涵盖整体架构、模块职责、关键类与函数、依赖关系及运行方式。
> 对应仓库：`dns-test`（MIT，当前版本 `v1.7.1 / v2026.08.11`）
> 适用对象：开发者 / 二次维护者 / AI 助手

> 🤖 **给 AI 的指引**：本工具集最重要的使用方是 AI 助手。需要**理解或修改本仓库代码**时，请先读本文档（代码结构与实现），再配合 [docs/AI_GUIDE.md](docs/AI_GUIDE.md)（操作流程）使用——两者分工互补：**AI_GUIDE 教你"怎么操作测试"**（初始化/流程/排障），**本文档教你"代码长什么样、想改哪里看哪里"**（架构/模块/函数/依赖）。修改代码后务必运行 `bash smoke_test.sh` + `bash verify.sh` 做回归验证，并同步更新 [docs/CHANGELOG.md](docs/CHANGELOG.md) 记录变更轮次。

---

## 目录

- [一、项目概览](#一项目概览)
- [二、整体架构](#二整体架构)
- [三、目录结构](#三目录结构)
- [四、主要模块职责](#四主要模块职责)
- [五、关键类与函数说明](#五关键类与函数说明)
- [六、依赖关系](#六依赖关系)
- [七、插件机制详解](#七插件机制详解)
- [八、测试与 CI](#八测试与-ci)
- [九、项目运行方式](#九项目运行方式)
- [十、已知限制与设计取舍](#十已知限制与设计取舍)

---

## 一、项目概览

### 1.1 简介

`dns-test` 是一套以默认运营商 DNS 为基线（示例为运营商DNS，可用环境变量覆盖），阿里/腾讯公共 DNS 为对照的 **DNS 基准测试与网络诊断工具集**。覆盖 DNS 基础评分、运营商 VoWiFi/ePDG 部署检测、路由器 DNS 转发验证、DoH/DoT 支持检测、DNS64、反向解析等专业场景，并支持多 DNS 横向对比与历史趋势洞察。

### 1.2 技术栈

| 维度 | 选型 | 说明 |
|------|------|------|
| Shell | **Bash 3.2+** | 全脚本按 macOS 默认 bash 3.2 兼容编写（无关联数组 / `mapfile` / `${var^^}` 等 4+ 语法） |
| 脚本语言 | **Perl 5.10+** | 专项测试与 DNS 报文处理（仅依赖核心 `Socket` 模块） |
| DNS 工具 | **dig**（必需，DoT 需 bind 9.18+） | A/AAAA/MX/NS/TXT/CNAME/SOA/DNSSEC/ECS/PTR 等 |
| 可选依赖 | curl（DoH 实测）、shellcheck（静态检查）、ping/ping6（连通性） | 缺失自动降级，不阻塞主功能 |
| CI | GitHub Actions | ubuntu + macOS 双平台矩阵 |

### 1.3 版本规则（双轨制）

- `vYYYY.MM.N`：日期式，N=当月发布序号（补丁级修复仅递增 N）
- `vX.Y`：语义版本（X=主版本，重大重构才升；Y=次版本，功能更新）
- 当前：`v1.7.1 = v2026.08.11`

---

## 二、整体架构

### 2.1 分层架构

项目采用 **入口层 → 核心库 → 专项工具 / 示例** 的分层结构，核心库被各入口脚本 `source` 复用：

```
┌─────────────────────────────────────────────────────────────┐
│                        入口层 (Entry)                        │
│  dns-test.sh  dns-preset.sh  full.sh  lite.sh               │
│  compare.sh   trends.sh       verify.sh smoke_test.sh       │
│  install.sh   release.sh                                    │
└───────────────┬──────────────────────────┬──────────────────┘
                │ source                    │ 调用 / 注册
                ▼                           ▼
┌───────────────────────────┐   ┌─────────────────────────────┐
│        核心库 (lib/)       │   │      专项工具 (tools/)      │
│  core.sh    公共变量/逻辑  │   │  manifest.sh  插件注册表    │
│  compat.sh  平台兼容层     │   │  vowifi/  ePDG/路由器        │
│  plugins.sh 插件加载器     │◄──┤  network/ 端口/DoH-DoT       │
│  DNSUtil.pm DNS纯函数     │   └─────────────────────────────┘
└───────────┬───────────────┘   ┌─────────────────────────────┐
            │ use DNSUtil         │      示例 (examples/)       │
            └────────────────────►│  01~04 Perl 示例脚本        │
                                  └─────────────────────────────┘
```

### 2.2 核心设计原则

1. **路径无关**：所有脚本用 `BASH_SOURCE` 相对定位，拉到任意目录都能运行。
2. **缺失才装**：`install.sh` 检测包管理器，依赖齐全则跳过 sudo；可选依赖缺失自动降级。
3. **防超时**：DNS 不可达自动预检跳过；多 DNS 用索引参数一次测一个；A 记录 8 并发并行。
4. **插件化**：专项菜单由注册表 `tools/manifest.sh` 驱动，新增专项零改主脚本。
5. **纯函数可测**：DNS 报文处理抽取为 `DNSUtil.pm` 纯函数（无网络 IO），接入单元测试。
6. **双平台兼容**：Linux/macOS/WSL，`compat.sh` 补齐 macOS 缺失的 `timeout`。

### 2.3 数据流

- **基础测试**：入口脚本 → `core.sh` 的 `run_common_tests`（mode=full/lite 控制差异） → 并行 `dig` → 解析 → 汇总评分
- **对比测试**：`compare.sh` → 延迟探测 + 批量调用 `lite.sh`/`full.sh` → 文本表格 + JSON + HTML
- **趋势洞察**：`trends.sh` → 扫描 `results/compare-*.json` → 线性回归 → CSV + SVG 折线图
- **专项测试**：`dns-test.sh` → `plugins.sh` → `manifest.sh` → 执行 `tools/` 下 perl/bash 脚本

---

## 三、目录结构

> 📍 **权威单一来源**：README / SANDBOX 的目录结构已精简并指向本节；**新增/移动脚本或文件时只需更新本节**，README/SANDBOX 无需改动（避免三份拷贝漂移）。

```
dns-test/
├── README.md / README.en.md      # 中/英文说明
├── dns-test.sh                   # 统一交互入口（选 DNS 组/测试类型/专项）
├── dns-preset.sh                 # 预设快捷测试（默认/阿里/腾讯）
├── full.sh / lite.sh             # 基础测试入口（完整版 16 项 / 精简版 10 项）
├── compare.sh                    # 多 DNS 对比（并行+延迟中位数+HTML/JSON）
├── trends.sh                     # DNS 趋势洞察（聚合 compare 历史）
├── verify.sh                     # 一键全面验证（语法+单测+冒烟+对比+趋势）
├── smoke_test.sh                 # 自动化冒烟测试（24 项）
├── install.sh                    # 依赖自动安装
├── release.sh                    # 打包发布
├── lib/                          # 公共库
│   ├── core.sh                   # 核心库（变量/函数/测试逻辑/评分）
│   ├── compat.sh                 # 平台兼容层（timeout 兼容）
│   ├── plugins.sh                # 插件加载器
│   └── DNSUtil.pm                # DNS 纯函数模块（可单测）
├── tests/                        # 单元测试
│   ├── 01_dnsutil.t              # DNSUtil 18 用例（perl）
│   ├── 02_plugins.sh             # 插件系统 9 用例（bash）
│   ├── 03_dig_target.sh          # dig_target 4 用例（IPv6加方括号）
│   ├── 04_core_functions.sh      # core 纯函数 18 用例（地址校验/响应判断/CDN/入口参数解析）
│   └── 05_run_common_tests.sh    # lite 计分口径 9 用例（稳定性降轮/CONFIG_DOMAINS安全解析/dig @server回归，mock dig/ping 离线）
├── tools/                        # 专项测试工具
│   ├── manifest.sh               # 插件注册表
│   ├── vowifi/                   # VoWiFi 专项（ePDG/路由器）
│   └── network/                  # 端口/DoH-DoT
├── examples/                     # 通用示例脚本（4 个 Perl）
├── docs/                         # 技术文档
│   ├── AI_GUIDE.md / TEST_METHOD.md / SANDBOX_GUIDE.md
│   ├── FAQ.md / CHANGELOG.md
│   └── CODE_WIKI.md              # 本文档
├── .github/workflows/smoke.yml   # CI（ubuntu + macOS 矩阵）
├── CONTRIBUTING.md / LICENSE
├── results/                      # 测试结果（可选，不入库）
└── trends/                       # 趋势产物（可选，不入库）
```

---

## 四、主要模块职责

### 4.1 入口层脚本

| 脚本 | 职责 | 关键特性 |
|------|------|---------|
| [dns-test.sh](file:///workspace/dns-test.sh) | 统一交互入口，引导选 DNS 组/测试类型/专项 | 交互双模式（有/无终端）；非交互自动降级 lite+单 DNS |
| [dns-preset.sh](file:///workspace/dns-preset.sh) | 预设快捷测试（default/ali/tencent/all） | 支持 `PRESET_DNS_CSV` 自定义；索引参数避免超时 |
| [full.sh](file:///workspace/full.sh) | 完整版基础测试（16 项，77~78 评分点） | `SAVE_LOG=1` 存日志；`trap` 清理临时目录 |
| [lite.sh](file:///workspace/lite.sh) | 精简版基础测试（10 项，53~54 评分点） | 同上，输出更短 |
| [compare.sh](file:///workspace/compare.sh) | 多 DNS 横向对比 | 延迟中位数 + 批量并发 + JSON/HTML 报告 |
| [trends.sh](file:///workspace/trends.sh) | 聚合 compare 历史 JSON 出趋势 | 线性回归 + SVG 折线图 + CSV + `--cron` 定时采集 |
| [verify.sh](file:///workspace/verify.sh) | 一键全面自检 | 7 步：语法/shellcheck/单测/冒烟/compare/trends/专项 |
| [smoke_test.sh](file:///workspace/smoke_test.sh) | 自动化冒烟（24 项） | CI 与改动后回归必跑 |
| [install.sh](file:///workspace/install.sh) | 依赖检测与安装 | 自动识别 apt/yum/dnf/brew/apk/pacman/zypper |
| [release.sh](file:///workspace/release.sh) | 打包 tar.gz + 上传指引 | 排除 .git/results 内容 |

### 4.2 核心库 (lib/)

| 文件 | 职责 |
|------|------|
| [lib/core.sh](file:///workspace/lib/core.sh) | 公共变量（DNS 组/域名列表/超时参数）+ 辅助函数 + `run_common_tests` 统一测试逻辑（mode 区分 full/lite）+ `par_run` 并行引擎 + 综合评分 |
| [lib/compat.sh](file:///workspace/lib/compat.sh) | 平台兼容层：macOS 无 `timeout` 命令时提供后台运行+到期 kill 的兼容实现 |
| [lib/plugins.sh](file:///workspace/lib/plugins.sh) | 插件加载器：`plugin_list` 打印菜单、`plugin_run` 按编号执行，参数策略三态 |
| [lib/DNSUtil.pm](file:///workspace/lib/DNSUtil.pm) | DNS 纯函数库：sockaddr 构建/IPv6 转换/报文构建与解析/PTR/反向名，无网络 IO 可单测 |

### 4.3 专项工具 (tools/)

#### VoWiFi 专项 (tools/vowifi/)

| 脚本 | 职责 |
|------|------|
| [tools/vowifi/01_resolve_vowifi.pl](file:///workspace/tools/vowifi/01_resolve_vowifi.pl) | 测试所有 3GPP 标准 ePDG 域名（mnc000~015）的 A/AAAA 解析 |
| [tools/vowifi/02_vowifi_verify.pl](file:///workspace/tools/vowifi/02_vowifi_verify.pl) | 多 DNS 交叉验证 VoWiFi 解析结果一致性（含 `check_ips` 历史对比） |
| [tools/vowifi/03_test_router_dns.pl](file:///workspace/tools/vowifi/03_test_router_dns.pl) | 路由器 DNS 转发测试（对比省级 DNS 基准，`--` 或 `PROVINCE_DNS` 自定义基准） |
| [tools/vowifi/carrier_epdg.pl](file:///workspace/tools/vowifi/carrier_epdg.pl) | 运营商 ePDG 部署检测（电信/移动/联通/广电，按 MNC 域名映射） |

#### 网络专项 (tools/network/)

| 脚本 | 职责 |
|------|------|
| [tools/network/01_port_test.pl](file:///workspace/tools/network/01_port_test.pl) | 端口连通性测试（UDP 空包探测 / TCP 非阻塞 connect） |
| [tools/network/doh_dot_check.sh](file:///workspace/tools/network/doh_dot_check.sh) | DoH/DoT 支持检测（DoT=`dig +tls` 实测；DoH=有 curl 实测/无则端口级） |

### 4.4 示例脚本 (examples/)

| 脚本 | 职责 |
|------|------|
| [examples/01_dns_query.pl](file:///workspace/examples/01_dns_query.pl) | 基础 DNS 查询（A/AAAA） |
| [examples/02_multi_dns_compare.pl](file:///workspace/examples/02_multi_dns_compare.pl) | 多 DNS 对比 + 一致性检查 |
| [examples/03_dns64_check.pl](file:///workspace/examples/03_dns64_check.pl) | DNS64 支持检测（识别 `64:ff9b::` 合成地址并提取嵌入 IPv4） |
| [examples/04_reverse_dns.pl](file:///workspace/examples/04_reverse_dns.pl) | 反向 DNS 解析（v4 in-addr.arpa / v6 ip6.arpa） |

所有示例均支持 `--help`/`-h` 打印用法，命令行参数 > 环境变量 > 默认值。

---

## 五、关键类与函数说明

### 5.1 lib/DNSUtil.pm（Perl 纯函数模块）

模块通过 `use Exporter 'import'` 导出，`@EXPORT` 包含 9 个函数。所有函数无网络 IO，仅依赖 `Socket` 核心模块。

| 函数 | 签名 | 说明 |
|------|------|------|
| `dns_sockaddr` | `($addr, $port) → ($sockaddr, $family, $err)` | 自动识别 IPv4/IPv6，返回 sockaddr + 协议族 + 错误信息；非法地址 `$err` 非空 |
| `inet_pton_ipv6` | `($addr) → $16字节二进制 or undef` | IPv6 字符串转 16 字节二进制（支持 `::` 压缩）；非 hex / 段数错误返回 undef |
| `build_dns_query` | `($domain, $type=1) → $报文` | 构建 DNS 查询报文（header + qname 标签编码 + qtype/class）；`$type` 默认 1=A，28=AAAA |
| `parse_dns_response` | `($response, $expected_type=1) → @ips` | 解析响应中的 A/AAAA 记录；非响应/NXDOMAIN/短包返回空列表 |
| `check_ips` | `($domain, $current_ips, $prev_ref) → $状态文字` | IP 一致性对比；无变化返回 `[✓ 与之前一致]`，有新增返回 `[⚠️ 新增IP: ...]` |
| `build_ptr_query` | `($reverse) → $报文` | 构建 PTR 反向查询报文（Type=12） |
| `parse_ptr_response_simple` | `($response) → @names` | 解析 PTR 响应中的目标域名（支持 rdata 压缩指针解引用） |
| `build_reverse_name` | `($ip) → $反向域名 or undef` | 构造反向域名：IPv4→`in-addr.arpa`，IPv6→`ip6.arpa` |
| `expand_ipv6` | `($addr) → $32位hex or undef` | 展开 IPv6 为 32 个 hex 字符 |

**调用约定**（各 perl 脚本统一头部）：

```perl
use FindBin;
use lib "$FindBin::Bin/../../lib";   # tools/ 下两级；examples/ 下一级
use DNSUtil;
```

### 5.2 lib/core.sh（核心库）

#### 公共变量

| 变量 | 类型 | 说明 |
|------|------|------|
| `DEFAULT_DNS_ADDR` / `DEFAULT_DNS_NAME` | 数组 | 默认 DNS 组（4 个，v6+v4，示例为运营商DNS）；可由 `DEFAULT_DNS_CSV` / `DEFAULT_DNS_NAME_CSV` 覆盖 |
| `ALI_DNS_ADDR` / `ALI_DNS_NAME` | 数组 | 阿里云公共 DNS（4 个） |
| `TENCENT_DNS_ADDR` / `TENCENT_DNS_NAME` | 数组 | 腾讯 DNSPod（3 个） |
| `DOMAINS_MAIN` / `DOMAINS_GLOBAL` | 数组 | 国内 15 个 / 国际 10 个测试域名 |
| `DOMAINS_3GPP` / `DOMAINS_CNAME` / `DOMAINS_CARRIER` / `DOMAINS_DNSSEC` / `DOMAINS_TTL` | 数组 | 各测试维度域名 |
| `TEST_IPS` | 数组 | PTR 反向解析测试 IP |
| `STAB_ROUNDS` | 整数 | 稳定性轮次（默认 20，`STAB_ROUNDS` 环境变量覆盖，非法回退 20） |
| `ECS_SUBNET` | 字符串 | ECS 测试 subnet（默认运营商 IPv6 前缀，示例为运营商DNS） |
| `PING_OPTS` | 字符串 | ping 超时参数（Linux/macOS 单位不同，自动区分） |

#### 关键函数

| 函数 | 说明 |
|------|------|
| `print_env_info` | 环境自检：输出 OS/dig/perl/ping/IPv6 可用性摘要（结果可回溯） |
| `valid_dns_addr` | DNS 地址格式校验（IPv4/IPv6），防命令注入/误传 |
| `dns_health_check` | DNS 可达性预检（双域名探测，任一成功即可达），不可达返回 1 快速跳过 |
| `par_run` | 并行 dig 引擎：将 `PARR_CMDS[]` 数组中的命令 `PARR_MAX` 并发（默认 8，环境变量可调）执行，结果存 `$PARR_TMPDIR/N.out`；临时目录自动注册进 `TMPDIR_LIST` 由入口脚本 trap 统一清理 |
| `is_valid_response` | 判断 dig 响应是否有效（过滤通信错误/无服务器/OPT 杂项） |
| `is_cdn_domain` | 判断域名是否为 CDN（结果对比时排除负载均衡差异） |
| `print_header` / `print_separator` | 输出格式化头部/分隔线 |
| `run_common_tests` | 统一测试逻辑，`mode` 参数（full/lite）控制差异点：A 记录延迟计算（仅 full）、记录类型数量（lite 仅 MX/NS/TXT，full 加 CNAME/SOA）、稳定性指标（full 输出 min/max/avg，lite 仅成功率）、综合评分高级项（DNSSEC/ECS/PTR/TTL/结果对比/递归） |
| `run_full_test` | 薄包装：`run_common_tests <addr> <name> full`（完整版 16 项） |
| `run_lite_test` | 薄包装：`run_common_tests <addr> <name> lite`（精简版 10 项，输出更短） |

### 5.3 lib/plugins.sh（插件加载器）

| 函数 | 说明 |
|------|------|
| `_plugins_load` | 幂等加载注册表 `tools/manifest.sh`（可由 `PLUGIN_MANIFEST` 覆盖路径） |
| `_plugin_split` | 拆分注册表行（`|` 分隔）到全局变量 `P_ID`/`P_SCRIPT`/`P_NAME`/`P_EXEC`/`P_PROMPT`/`P_FWD` |
| `plugin_list` | 打印所有菜单项 `"编号. 名称"` 供菜单展示 |
| `plugin_run` | 按编号执行插件：校验目录/脚本存在 → 执行器白名单（perl/bash）→ 参数策略三态 → 透传退出码 |

**参数策略三态**（防 DNS 被误当插件参数）：

1. 引导输入非空 → 独占参数（用户明确给了目标）
2. 引导为空 + `P_FWD=1` → 透传当前 DNS 组（如 DoH"回车用当前组"）
3. 引导为空 + `P_FWD=0` → 无参数执行（如 carrier_epdg/端口测试）

### 5.4 lib/compat.sh（平台兼容层）

| 函数 | 说明 |
|------|------|
| `timeout` | macOS 无 `timeout` 命令时的兼容实现：后台运行 + sleep 到期 kill，并通过 `export -f` 导出供子进程使用 |

---

## 六、依赖关系

### 6.1 外部依赖

| 依赖 | 必需性 | 用途 | 缺失降级 |
|------|--------|------|---------|
| `dig`（dnsutils/bind-utils/bind） | ✅ 必需 | DNS 记录查询 | 缺失直接退出（`core.sh` 前置检查） |
| `perl` | ✅ 必需（专项测试） | 专项脚本与 DNSUtil | 缺失退出 |
| `bash` 3.2+ | ✅ 必需 | 所有 shell 脚本 | — |
| `ping` / `ping6` | 可选 | 连通性测试 [7]/[7b] | 无权限时该项跳过 |
| `curl` | 可选 | DoH 实测 | 无 curl 时 DoH 降级为 443 端口级探测 |
| `shellcheck` | 可选 | `verify.sh` 静态检查 | 未装则该项提示跳过（CI 已兜底）；`--strict` 强制要求 |

**DoT 检测特殊要求**：需 bind 9.18+ 的 dig 才支持 `dig +tls`，旧版降级为端口级。`install.sh` 会自动检测。

### 6.2 内部模块依赖

```
dns-test.sh ─┬─► lib/core.sh ─► lib/compat.sh
             └─► lib/plugins.sh ─► tools/manifest.sh

full.sh / lite.sh ─► lib/core.sh ─► lib/compat.sh
compare.sh / trends.sh ─► lib/core.sh
verify.sh ─► lib/compat.sh（仅 timeout 兼容）

tools/vowifi/*.pl ─┐
examples/*.pl ─────┴─► lib/DNSUtil.pm（Perl Socket）

tools/network/doh_dot_check.sh ─► lib/compat.sh（相对定位 ../../lib/）
```

### 6.3 关键环境变量（全量清单 · 单一来源）

> 本节为全量环境变量**单一来源**，README/其它文档只作指针；新增/修改环境变量时只需同步本节。
> 来源：lib/core.sh / compare.sh / trends.sh / tools/vowifi/*.pl / lib/plugins.sh。

| 环境变量 | 作用 | 默认值 |
|---------|------|--------|
| `DEFAULT_DNS_CSV` | 覆盖基础测试默认 DNS 组（逗号分隔） | 默认 4 个（示例为运营商DNS） |
| `DEFAULT_DNS_NAME_CSV` | 覆盖默认 DNS 组显示名 | 自动补齐 |
| `STAB_ROUNDS` | 稳定性测试轮次（**未显式设置时 lite 自动减半为 10**，full 保持 20） | 20 |
| `ECS_SUBNET` | ECS 测试 subnet | `240e:52:4800::/48` |
| `CONFIG_DOMAINS` | 域名列表外置配置文件（**不 source**，仅解析 `DOMAINS_MAIN/GLOBAL=("a" "b")` 双引号数组，注入特征行忽略） | — |
| `PROVINCE_DNS` | 路由器/ePDG 测试的省级基准 | 默认省级DNS（示例为运营商DNS） |
| `PRESET_DNS_CSV` | `dns-preset.sh` 自定义预设组 | — |
| `DNS_SERVER` / `DNS_LIST` | examples 默认 DNS | 默认（示例为运营商DNS） |
| `COMPARE_MAX_CONCURRENCY` | compare 并行数 | 3 |
| `SAVE_LOG` | 保存日志到 results/ | 关闭 |
| `DNS_PAUSE` | full/lite 多 DNS 测试间隔秒数（请求间隔，设 0 可关掉提速） | 3 |
| `PARR_MAX` | par_run 并行并发上限（正整数，调小可降低负载） | 8 |
| `TRENDS_DIR` / `COMPARE_RESULTS_DIR` | 趋势产物/数据源目录 | `trends/` / `results/` |
| `PLUGIN_MANIFEST` | 插件注册表路径覆盖 | `tools/manifest.sh` |

---

## 七、插件机制详解

### 7.1 注册表（tools/manifest.sh）

专项菜单由 [tools/manifest.sh](file:///workspace/tools/manifest.sh) 驱动。`PLUGIN_ITEMS` 数组每行格式：

```
插件id | 脚本文件名 | 菜单显示名 | 执行器(perl/bash) | 引导提示(可空) | 透传DNS(1/0, 默认1)
```

文件底部需补 `PLUGIN_DIR_<id>="目录"` 映射。当前注册了 10 个插件（vowifi 4 + network 2 + examples 4）。

### 7.2 新增专项（两步）

1. 把脚本放进 `tools/<目录>/`（或 `examples/`）
2. 在 `tools/manifest.sh` 的 `PLUGIN_ITEMS` 加一行 + 文件底部补 `PLUGIN_DIR_<id>="目录"` 映射

完成后 `dns-test.sh` 选"专项测试"时自动出现，主脚本零改动。

### 7.3 执行流程

```
dns-test.sh 选"专项测试"
  → source lib/plugins.sh（幂等加载 manifest.sh）
  → plugin_list 打印菜单 + 追加 compare/trends/verify 三项
  → 用户选编号
  → plugin_run <编号> [DNS列表...]
      → _plugin_split 拆字段
      → 校验 PLUGIN_DIR_<id> 映射存在
      → 拼绝对路径 项目根/目录/脚本（不 cd，保相对路径）
      → 校验脚本文件存在
      → 引导提示非空 → read -t 30 询问
      → 校验执行器白名单（perl/bash）
      → 参数策略三态选择
      → 执行器 脚本 参数
      → 透传退出码
```

---

## 八、测试与 CI

### 8.1 单元测试

| 测试文件 | 覆盖 | 运行命令 |
|---------|------|---------|
| [tests/01_dnsutil.t](file:///workspace/tests/01_dnsutil.t) | DNSUtil 18 用例（dns_sockaddr/inet_pton_ipv6/build_dns_query/parse_dns_response/check_ips/PTR 系列 + 畸形包防崩） | `perl -Ilib tests/01_dnsutil.t` |
| [tests/02_plugins.sh](file:///workspace/tests/02_plugins.sh) | 插件系统 9 用例（注册表加载/字段拆分/输出格式/无效编号拦截/未知执行器拦截/脚本缺失检测） | `bash tests/02_plugins.sh` |
| [tests/03_dig_target.sh](file:///workspace/tests/03_dig_target.sh) | dig_target 4 用例（IPv4 原样/IPv6 加方括号/特殊 IPv6/空输入） | `bash tests/03_dig_target.sh` |
| [tests/04_core_functions.sh](file:///workspace/tests/04_core_functions.sh) | core 纯函数 18 用例（valid_dns_addr 合法/非法+超范围/IPv6 畸形结构、is_valid_response 错误/纯 OPT、is_cdn_domain、parse_dns_args 入口参数） | `bash tests/04_core_functions.sh` |
| [tests/05_run_common_tests.sh](file:///workspace/tests/05_run_common_tests.sh) | lite 计分口径 9 用例（稳定性降轮 20→10、AAAA 空响应计分、综合评分 45/53、CONFIG_DOMAINS 注入不执行/非法 token 忽略、dig @server 前缀回归；mock dig/ping 离线） | `bash tests/05_run_common_tests.sh` |

`02/03/04/05_*.sh` 采用零依赖轻量断言（不引入 bats），与 perl 单测互补。

### 8.2 冒烟测试（smoke_test.sh）

24 项自动化验证，覆盖：全量语法、lite/full 功能、不可达预检、注入拦截、入口非交互、预设、环境变量自定义、carrier_epdg、路由器转发、反向解析、DoH/DoT、SAVE_LOG、VoWiFi 解析/交叉验证、端口测试、示例 01/02、trends 聚合/产物、compare 多 DNS、单测、verify --help、插件注册表。

网络敏感项（路由器/省级 DNS）会做可达性预检，不可达自动跳过不算失败。

### 8.3 一键验证（verify.sh）

7 步全量自检（约 5 分钟）：

1. 语法检查（.sh + .pl）
2. shellcheck（可选依赖，`--strict` 强制）
3. 单元测试（18+9+4+18+9 用例）
4. 冒烟测试（24 项）
5. compare 快测（2 DNS）
6. trends 聚合（无数据/超时跳过）
7. 专项抽查（示例 02 / DoH）

### 8.4 CI（.github/workflows/smoke.yml）

双平台矩阵（ubuntu-latest + macos-latest），分两层：

- **strict 层**（失败即红，无网络）：语法/shellcheck/注入拦截/不可达预检/trends 本地聚合/单测/插件检查
- **smoke 层**（`continue-on-error`，含网络）：完整冒烟；fork 的 PR 跳过网络冒烟；产物始终上传

`concurrency` 配置同分支/PR 只保留最新运行。

---

## 九、项目运行方式

### 9.1 安装与验证

```bash
git clone https://github.com/Jing494/dns-test.git && cd dns-test
bash install.sh            # 缺失才装 dig/perl/curl（--all 连 shellcheck）
bash smoke_test.sh         # 24 项自动化验证环境
bash verify.sh             # 一键全量深度自检（约 5 分钟）
```

### 9.2 基础测试

```bash
bash dns-test.sh                              # 交互引导（选 DNS 组/版本/专项）
bash dns-test.sh 8.8.8.8                      # 测自定义 DNS
bash lite.sh 223.5.5.5 0                      # 精简版单 DNS（索引参数避免超时）
bash full.sh 8.8.8.8 114.114.114.114 0        # 完整版只测第 1 个（防超时铁律）
bash dns-preset.sh ali lite 0                 # 预设：阿里精简版第 1 个
```

### 9.3 多 DNS 对比与趋势

```bash
bash compare.sh 223.5.5.5 119.29.29.29 --html # 对比 + 生成 results/report.html
bash compare.sh 223.5.5.5 119.29.29.29 --full # 完整版对比（77~78 项/DNS）
bash trends.sh --html --csv                   # 趋势洞察（需先积累 compare 数据）
bash trends.sh --cron 223.5.5.5 119.29.29.29  # 先采集再聚合（配 crontab）
```

### 9.4 专项测试

```bash
perl tools/vowifi/carrier_epdg.pl all         # 运营商 ePDG 部署检测
perl tools/vowifi/03_test_router_dns.pl 192.168.1.1        # 路由器转发测试
perl tools/vowifi/03_test_router_dns.pl 192.168.1.1 -- 223.5.5.5  # 自定义省级基准
perl tools/network/01_port_test.pl 223.5.5.5 53 udp        # 端口连通性
bash tools/network/doh_dot_check.sh 223.5.5.5              # DoH/DoT 检测
perl examples/04_reverse_dns.pl 222.172.200.68             # 反向解析
```

### 9.5 退出码约定

| 退出码 | 含义 |
|--------|------|
| 0 | 测试完成（至少 1 个 DNS 测过，评分多少是数据不是错误） |
| 1 | 脚本错误（参数非法、命令缺失等） |
| 2 | 所有 DNS 均不可达，测试未执行 |

### 9.6 防超时铁律

1. **full 版多 DNS 必须加索引参数**，一次测一个（`bash full.sh A B 0`）
2. 非交互/工具调用：入口脚本自动降级 lite + 单 DNS
3. 加速：`STAB_ROUNDS=5 bash lite.sh 8.8.8.8`（稳定性 20→5 轮）
4. DNS 不可达时自动预检跳过（秒级），不白等

---

## 十、已知限制与设计取舍

### 10.1 已知限制

- **DoH 检测**：无 curl 环境降级为端口级探测（非真实 DoH 验证）
- **DoT 检测**：需 bind 9.18+ 的 dig（`+tls` 支持），旧版无法实测
- **Windows**：不支持原生运行，推荐 WSL（Git Bash 仅部分功能）
- **IPv6 相关**（[7b] 连通性 / v6 DNS）：依赖本机 IPv6 网络，无 IPv6 时自动跳过
- **运营商 ePDG**：公共 DNS 查不到运营商内部记录属正常（需省级 DNS）；仅反映解析/部署
- **网络波动**：加速器/代理环境会导致延迟偏高、国际域名解析不稳

### 10.2 设计取舍

| 决策 | 理由 |
|------|------|
| 不引入 bats | 现有 perl 单测 + smoke/verify 集成已够，bash 纯函数用零依赖轻量断言补充 |
| 不引入 jq | compare JSON 自产自销且格式固定，echo 拼接足够 |
| `par_run` 用临时文件方案 | PARR_MAX 并发（默认 8）+ 临时文件，核心库重构需谨慎 |
| compare 用平行数组而非关联数组 | 兼容 bash 3.2（macOS 默认） |
| DNSUtil 抽取为纯函数模块 | 可单元测试，9 个 perl 脚本共用，消除重复 |
| 运营商 IP 用 RFC 5737 占位 | 隐私保护，不暴露真实运营商内部 IP |

### 10.3 Roadmap

- ✅ 单元测试（已完成）
- ✅ `par_run` 通用化（PARR_MAX 环境变量可调并发数 + 临时目录统一 TMPDIR_LIST 清理）
- 🔜 `trends svg_chart` 模板化（HTML/SVG 内联字符串改 heredoc/独立模板）
- 🔜 JSON 序列化增强（结构复杂化时引入 jq）

---

## 附录：文档导航

| 文档 | 用途 |
|------|------|
| [README.md](file:///workspace/README.md) | 项目总说明（中文） |
| [README.en.md](file:///workspace/README.en.md) | 英文精简简介 |
| [docs/AI_GUIDE.md](file:///workspace/docs/AI_GUIDE.md) | AI 助手操作手册（12 章） |
| [docs/TEST_METHOD.md](file:///workspace/docs/TEST_METHOD.md) | 测试方法论 / 评分标准 / 实测结果 |
| [docs/CODE_WIKI.md](file:///workspace/docs/CODE_WIKI.md) | 本文档（架构/模块/函数/CI/插件） |
| [docs/SANDBOX_GUIDE.md](file:///workspace/docs/SANDBOX_GUIDE.md) | 沙箱环境使用指南 |
| [docs/FAQ.md](file:///workspace/docs/FAQ.md) | 常见问题 |
| [docs/CHANGELOG.md](file:///workspace/docs/CHANGELOG.md) | 完整变更记录 |
| [examples/README.md](file:///workspace/examples/README.md) | 示例脚本说明 |
| [CONTRIBUTING.md](file:///workspace/CONTRIBUTING.md) | 贡献指南 |
