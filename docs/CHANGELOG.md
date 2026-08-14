# 📜 变更记录（Changelog）

> 完整轮次变更历史（从第 46 轮起有 git 提交可追溯；更早轮次为仓库建立前的开发记录）。

## 版本对应速查（双轨制：日期式 vYYYY.MM.N ↔ 语义式 vX.Y）

| 日期式版本 | 语义式版本 |
|-----------|-----------|
| v2026.08.11 | v1.7.1（当前） |
| v2026.08.10 | v1.7.0 |
| v2026.08.9  | v1.7.0 |
| v2026.08.8  | v1.6.2 |
| v2026.08.7  | v1.6.1 |
| v2026.08.6  | v1.6 |
| v2026.08.5  | v1.5.3 |
| v2026.08.3  | v1.5.1 |
| v2026.08.2  | v1.5 |

> 注：① `v2026.08.9` 与 `v2026.08.10` 历史上均标记为 `v1.7.0`（版本管理疏漏，未影响代码与下载名），当前实际版本 **v1.7.1 = v2026.08.11**；② 早期 `v2026.08.8/.9` 等日期式版本号未加前导零，为历史遗留，与 git tag / 下载文件名保持一致，未改动。

- 2026-08-14（第八十二轮）：**审阅收尾两项小改（在 v1.7.1 = v2026.08.11 基础上，不升版本）**
  - ① **缩进统一**：`tools/network/doh_dot_check.sh` DoT 块缩进 2→4 格，与 DoH 块对齐（纯颜值，shellcheck 本就通过）
  - ② **dig @ 目标统一抽变量**：`lib/core.sh` `run_common_tests` 函数级新增 `local t=$(dig_target "$addr")` 只算一次，替换全部 21 处 `dig @$(dig_target "$addr")` 为 `"@$t"`（含 PARR_CMDS 数组字面量、稳定性/NXDOMAIN/连通性/IPv6/flags 等直接调用），A 记录循环内重复的 `local t=` 一并删除；结果对比基准 `ref_dns` 单独抽 `local ref_t`；消除 SC2046 隐患点、减少重复计算
  - ③ 回归：语法 + 单测(18+9+4+15+9) 全绿，shellcheck 0 告警
- 2026-08-14（第八十一轮）：**修复 dig @server 回归 bug（审阅复核新发现，在 v1.7.1 = v2026.08.11 基础上，不升版本）**
  - ① **关键修复**：`lib/core.sh` `dns_health_check`（2 处）与 A 记录批量循环（1 处）在"局部变量 `local t=$(dig_target)`"重构时**漏写 `@` 前缀**，实测 `dig "8.8.8.8" www.alidns.com` 会走**本地默认解析器**而非目标 DNS（正确 `dig @8.8.8.8` 形式才命中目标）。后果：预检恒"可达"（不可达 DNS 不再被跳过）、A 记录/延迟全部测成本地解析器结果。已改为 `dig "@$t"` 恢复正确行为
  - ② **回归防护**：`tests/05_run_common_tests.sh` 新增第 9 用例——mock dig 记录完整参数并断言每次调用均以 `@` 开头（已用负向用例验证：单行漏 `@` 立即失败 exit=1）；mock dig 增加"无 @server 即报错退出"断言，覆盖 dns_health_check OR 语义盲区
  - ③ **用例计数同步**：05 单测 8→9 用例（verify.sh / CI smoke.yml / CODE_WIKI / AI_GUIDE / README / SANDBOX_GUIDE / CHANGELOG 全量），并顺带修正 README/SANDBOX_GUIDE 目录树 core 用例数 13→15 的历史漏网
  - ④ 回归：语法 + 单测(18+9+4+15+9) 全绿
- 2026-08-14（第八十轮）：**审阅模型建议优化（在 v1.7.1 = v2026.08.11 基础上，不升版本）**
  - ① **安全加固**：`CONFIG_DOMAINS` 不再 `source` 执行，改为逐行解析 `DOMAINS_MAIN/GLOBAL` 双引号数组并校验纯域名 token（命令注入行忽略不执行）；`par_run` 增加 dig 命令白名单（任一非 dig 命令整体拒绝）
  - ② **macOS/海外兼容**：IPv6 可用性检测改用本地 loopback `::1`（仅验协议栈，海外/无 IPv6 路由网络不再误报"不可用"）；`dns_health_check` 双域名并行探测（不可达 DNS 等待 4s→2s）
  - ③ **性能优化**：lite 未显式设置 `STAB_ROUNDS` 时稳定性轮次自动减半（20→10，实测单 DNS 从约 20s 降至 10s 内）；compare JSON 序列化优先 python3（`json.dumps`，特殊字符安全，无 python3 回退 sed 转义）
  - ④ **测试**：新增 `tests/05_run_common_tests.sh` 离线回归 lite 计分口径 + CONFIG_DOMAINS 安全解析（8 用例，mock dig/ping，不发起真实网络请求），verify.sh/CI 同步纳入
  - ⑤ **修复**：hijack_rate 基准全不可达时显示 N/A（避免"对比一致 100%"误导）；compare lite 计分点 63→53 同步（稳定性降轮后的总分口径），README 评分示例同步
  - ⑥ **文档同步**：CODE_WIKI 环境变量表标注"全量清单·单一来源"，TEST_METHOD 更新 CONFIG_DOMAINS 安全说明（不 source）；回归：语法 + 单测(18+9+4+13+8) + 冒烟 25 项全绿，双分支（main/develop）同步，发行包 `dns-test-v2026.08.11.tar.gz` 重打包
  - ⑦ **审阅复核补漏（同日）**：评分口径文档补同步（TEST_METHOD L70 精简版 64→54、L78 稳定性 20→10、L122/126-129 实测 63→53、L131 78/64→78/54；README L233 评分项 64/78→54/78）；full.sh/lite.sh `--help` 默认 DNS 文案对齐实际默认 4 个云南电信 DNS；新增 `.editorconfig`（LF+UTF-8，与 .gitattributes 配套）；05 单测两条预期 ⚠️ 噪音静音（2>/dev/null）
- 2026-08-14（第七十九轮）：**文档重构——目录结构单一来源**
  - ① README/SANDBOX 目录树精简为关键目录概览并指向 CODE_WIKI 三、目录结构（修复 README 目录树漏 tests/03/04 的漂移）；CODE_WIKI 三、目录结构标注为权威单一来源（新增/移动文件只需改本节）
  - ② README 已知限制移入 FAQ（用户视角，README 留指针；CODE_WIKI 10.1 保留开发者视角）
  - ③ README 版本历程精简为最新版本并指向 CHANGELOG
  - ④ AI_GUIDE 开头补"找文件/目录→CODE_WIKI"指引、第十一章"README FAQ"引用修正为 docs/FAQ.md
  - ⑤ CONTRIBUTING 文档同步指引改为 CODE_WIKI 目录结构
- 2026-08-14（第七十八轮）：**发布 v1.7.1 = v2026.08.11**（补丁：core 纯函数单测 + IPv4 地址范围校验）
  - ① lib/core.sh `valid_dns_addr` IPv4 正则从仅校验位数改为**每段 0-255 范围校验**（拒绝 `999.999.999.999` 等超范围地址误判为合法，防注入/误传）
  - ② 新增 `tests/04_core_functions.sh`：core 纯函数 13 用例（valid_dns_addr 合法 IPv4/IPv6/非法+注入+超范围/非法 hex；is_valid_response 空响应/通信错误/无服务器/有效 A 记录/纯 OPT（真实 dig 输出格式）/OPT 与 IN 并存；is_cdn_domain CDN/非 CDN/空输入）
  - ③ verify.sh 步骤3 + CI strict 第6步扩为 perl18+bash9+dig_target4+core函数13 用例
  - ④ 文档同步：CODE_WIKI 单元测试表与目录树补 tests/03/04、SANDBOX_GUIDE/AI_GUIDE/README Roadmap 同步测试文件，版本号升 **v1.7.1 = v2026.08.11**
  - ⑤ 回归：语法 + 单测 04（13/13）+ shellcheck 0 告警
- 2026-08-14（第七十七轮）：**发布 v1.7.0 = v2026.08.10**（补丁：审阅建议优化——run_full/lite 去重 / 解析走 +short 输出与评分解耦 / 清理 perl 残留死代码 / 版本号单一来源）
  - ① lib/version.sh 新增（版本号单一来源，各脚本统一 source 引用，改版本只需改一处）
  - ② lib/core.sh：run_full_test/run_lite_test 合并为 run_common_tests（mode 参数控制 full/lite 差异：A 记录延迟计算、记录类型数量、稳定性指标、综合评分高级项），原接口保留为薄包装；A 记录/AAAA/其他记录/稳定性/异常/连通性等测试输出与评分解耦——评分只看是否有效响应，+short 用于非延迟场景（其他记录类型），A 记录保留完整输出以获取 Query time
  - ③ 清理 7 个 perl 脚本（examples/01~04、tools/vowifi/02~03、tools/network/01）中的未实现占位符注释
  - ④ 文档同步：CODE_WIKI 函数表/数据流/模块职责更新为 run_common_tests，README 版本与版本历程更新，全分支版本号统一 source
  - ⑤ 回归：语法 + 单测 03_dig_target（4/4）+ mock 验证 full/lite 行为等价（A 记录延迟/记录类型数/稳定性指标/评分项数全部正确分流）
- 2026-08-13（第七十六轮）：**发布 v1.7.0 = v2026.08.9**（中等更新：临时目录统一清理 + par_run 并发可调）
  - ① core.sh：par_run 自动把 `PARR_TMPDIR` 注册进 `TMPDIR_LIST`，删除散布 15 处 `rm -rf "$PARR_TMPDIR"` 与 A 记录 `a_tmpdir` 的重复手动 rm（统一由入口脚本 trap 清理，INT/TERM 中断时中间态目录不再泄漏）；mktemp 加 `dns-test.XXXXXX` 前缀便于 /tmp 审计；并行并发上限 8 抽成 `PARR_MAX` 环境变量（默认 8，可调小降负载）
  - ② compare.sh：trap 前置到 source 后统一清理 `TMPDIR_LIST`（原 trap 仅清 TMPD，中断时 PARR_TMPDIR 泄漏），TMPD mktemp 加前缀并入清单
  - ③ 版本号升 **v1.7.0 = v2026.08.9**（README 徽章/版本历程/下载名、CODE_WIKI 同步）；文档再同步：CODE_WIKI 函数表/环境变量表补 `PARR_MAX`、Roadmap 与 README Roadmap 将 `par_run` 通用化标 ✅（并发数可调已落地）；回归：语法 + 单测03 + 冒烟
- 2026-08-13（第七十五轮）：**发布 v1.6.2 = v2026.08.8**（审阅建议优化 + compare IPv6 一致性）
  - ① core.sh 新增 `dig_target`（IPv6 地址自动加方括号消除 `dig @addr` 解析歧义，全部调用点统一）；第 8 项「一致性」改为**按实际解析结果计数**（不再恒计成功）；[14]「劫持检测」→「结果对比（与阿里 DNS 对比，仅作疑似劫持提示）」口径统一；trap 收敛到入口脚本（TMPDIR_LIST 统一清理临时目录）
  - ② 新增 tests/03_dig_target.sh 单测（4 用例），verify.sh + CI strict 第6步扩为 perl18+bash9+dig_target4
  - ③ compare.sh 延迟探测统一走 `dig_target`（用户传 IPv6 DNS 不再歧义）
  - ④ 文档同步：TEST_METHOD 补评分口径、AI_GUIDE/CODE_WIKI/FAQ 口径统一、README/CODE_WIKI 版本号升 v1.6.2=v2026.08.8；全分支（develop/main/tool_list-test/trae-agent）CI 双平台全绿
- 2026-08-13（第七十四轮）：**发布 v1.6.1 = v2026.08.7**（补丁：插件系统 bash 单测）
  - tests/02_plugins.sh 纯 bash 轻量断言 9 用例（注册表/参数策略三态/拦截/脚本存在，零依赖，bats 评估结论=不引入）
  - verify.sh 步骤3 + CI strict 第6步扩为 perl18+bash9 用例（双平台 run#55/56 全绿）
  - README Roadmap 单元测试标 ✅（9 脚本早已全量迁移 DNSUtil，修复过时描述）；目录树/AI_GUIDE/PR 模板同步；PR #11 合并
- 2026-08-13（第七十三轮）：**发布 v1.6 = v2026.08.6**（专项菜单插件化 + CI 双平台矩阵）
  - 插件化经 PR #7/#8/#9 三连合入 main（run#42-49 CI 全绿）：lib/plugins.sh 插件加载器（plugin_list/plugin_run，perl/bash 执行器白名单，参数策略三态：引导输入独占/透传DNS/无参数执行，BASH_SOURCE 自定位项目根）+ tools/manifest.sh 注册表（10 专项，新增专项=加一行+目录映射，菜单自动出现）+ dns-test.sh 动态菜单（compare/trends/verify 降为应用工具）+ smoke 24→25 项
  - CI 增强：strict job 双平台矩阵（ubuntu+macOS，bash 3.2 语法/shellcheck/插件检查/单测，失败即红）+ strict 第 7 步插件系统确定性检查（清单/脚本存在性/拦截）+ 扫描范围含 tools/*.sh
  - 文档：README 拆分（文档导航提前至 TL;DR 后）+ 插件机制说明 + CONTRIBUTING 新增插件指引
  - macOS 兼容性实测：strict+smoke 双平台全绿（macOS smoke 25/0）
- 2026-08-13（tool_list-test 实验分支，已合入 develop/main）：**专项菜单插件化**
  - ① lib/plugins.sh 插件加载器（plugin_list/plugin_run，perl/bash 执行器白名单，引导输入独占参数防 DNS 被误当参数，无效编号/未知执行器拦截，SC1090 豁免与 core.sh 同策略）
  - ② tools/manifest.sh 插件注册表（10 个专项：vowifi4/network2/examples4，新增专项=加一行+补目录映射，菜单自动出现）
  - ③ dns-test.sh 专项菜单改注册表驱动（compare/trends/verify 降为应用工具排插件后，DNS 数量保护保留）
  - ④ smoke 24→25 项（新增"插件注册表可加载"）
  - ⑤ doh_dot_check.sh 多位置参数适配；验证：plugin_list/plugin_run(perl+bash)/引导提示/交互菜单/非交互/参数独占/白名单拦截 全通过
- 2026-08-13（第七十二轮）：**可选依赖引导体系**（v2026.08.5）
  - ① verify.sh 支持 `--strict`（shellcheck 未装时该项记失败，退出码1，适合开发者/CI 真机自检）与 `-h/--help`（打印用法，未知参数报错退出）；默认模式未装 shellcheck 时输出**分平台安装命令表**（apt/dnf/yum/brew/apk/pacman/zypper）+ 明确"可选依赖，CI 已兜底"，退出码保持0
  - ② install.sh 新增 `--all` 模式（连可选依赖 shellcheck 一起装）、`-h/--help` 与未知参数拦截、apk/pacman/zypper 手动分支提示、**可选依赖交互询问**（检测到 shellcheck 缺失且为终端时问"是否现在一并安装？y/N"，非交互自动跳过）、**dig DoT 能力检测**（`dig -h` 是否含 `+[no]tls`，不支持则提示"DoT 检测降级为端口级"）、末尾"可选依赖检测"小节
  - ③ 文档同步：README 依赖表/目录树补 shellcheck 可选说明与 --all/--strict/--help 用法（含修复下载链接 v2026.08.3→v2026.08.5 的过期引用）、README.en、AI_GUIDE、SANDBOX_GUIDE、CONTRIBUTING、FAQ 新增"verify 提示 shellcheck 未装要装吗"问答、TEST_METHOD 补 install.sh DoT 检测说明
  - ④ dns-test.sh 菜单10 标注 --strict
  - ⑤ **兼容性深挖**：修复 verify.sh 漏 source lib/compat.sh 的 macOS timeout 隐患（步骤4-7 在无 timeout 命令的 macOS 会全挂，verify 自诞生以来仅在 Linux 验证过）、verify.sh/smoke_test.sh 语法检查范围与 CI 对齐（补 lib/*.sh tools/network/*.sh）、新增 .gitattributes（LF 换行锁定，防 Windows clone 时 CRLF 破坏脚本）、FAQ/README 补完整 WSL 引导（wsl --install 全流程 + Git Bash 边界说明）、全项目 bash 3.2 兼容扫描（ping 超时秒/毫秒、ping6 适配、无 4+ 语法/GNU-only 命令残留）；版本号升级 **v1.5.3 (v2026.08.5)**；完整回归：smoke 24项 + verify 7项（普通/--strict 双模式）全过
- 2026-08-10（第七十一轮）：新增 verify.sh 一键全面验证（语法+shellcheck+单测+冒烟+compare+trends+专项，真机/沙箱通用，退出码0/1；trends 无数据/超时友好提示）；新增 GitHub issue(Bug报告模板)/PR 模板（含验证清单与兼容性检查项）；README.en 补 --full/--help；README 目录树与 TL;DR 提 verify.sh
- 2026-08-10（第七十轮）：compare.sh 支持 `--full` 模式（完整版 77~78项/DNS 对比，标题/JSON/HTML 全部模式化）；examples 01-04 脚本加 `--help`/`-h` 用法提示；文档同步（README compare 用法/AI_GUIDE 单测用例数 18/examples README）
- 2026-08-10（第六十九轮）：**DNSUtil 全量迁移**——其余 7 个 perl 脚本（02/03/carrier_epdg/port_test/examples 01-04）函数副本迁移到 lib/DNSUtil.pm（消除 ~700 行重复代码，统一维护+单测覆盖）；check_ips 改纯函数（prev 引用参数）并入 DNSUtil；**迁移过程状态机一度误删主逻辑**（sub{ 双重计数致花括号配平失效），已定位修复并全量回归；单测扩至 13 用例；smoke 加第 22 项单元测试（22→23 项）；README.en 补 FAQ/CHANGELOG 链接
- 2026-08-10（第六十八轮）：**单元测试启动**——提取 lib/DNSUtil.pm（dns_sockaddr/inet_pton_ipv6/build_dns_query/parse_dns_response 纯函数模块），01_resolve_vowifi.pl 接入（其余脚本后续迁移）；tests/01_dnsutil.t 12 用例（sockaddr v4/v6/非法、IPv6 压缩/展开/hex校验、报文编码、响应解析 A/AAAA/NXDOMAIN/压缩指针/短包）；**单测发现真实 bug**：inet_pton_ipv6 不校验 hex 合法性（perl hex() 宽容处理"gg::1"）已修；CI strict job 加单测步骤；README Roadmap 更新（单测已启动）
- 2026-08-10（第六十七轮）：工程化与文档优化——① README 顶部加 TL;DR + 典型输出片段 ② CI strict job 加 shellcheck（全项目 0 告警：core.sh 豁免 SC2155/SC2034/SC1090 并注释理由，其余 SC2164×4/SC2206/SC2207/SC2044 全修）③ CI 工程化：concurrency 取消旧run、smoke timeout-minutes、fork PR 跳过网络冒烟、artifact 上传 results/trends 产物 ④ 注入拦截断言改退出码（不依赖输出文本）⑤ install.sh 无包管理器分支增强（各平台手动安装命令表 + WSL/完整环境建议）
- 2026-08-10（第六十六轮）：补丁版 **v1.5.1 (v2026.08.3)**——代码 VERSION 统一升级（lite/full/compare/trends/release.sh），README 徽章/下载名/版本规则同步（语义版补丁位 .1）
- 2026-08-10（第六十五轮）：工程优化——① timeout 兼容函数抽离到 lib/compat.sh（core.sh/smoke_test/doh_dot_check 三处统一 source，消除重复，compat 为纯函数文件无前置检查依赖）② CI 分层：新增 strict job（语法/注入拦截/不可达预检/trends本地聚合，无网络依赖，**失败即红**，真实回归不再被掩盖），原 smoke 保持容错并 needs strict；③ README 新增 Roadmap（单测/par_run通用化/svg模板化/jq，按优先级记录待实施）
- 2026-08-10（第六十四轮）：版本号升级 **v1.5 (v2026.08.2)**——双轨制版本规则落地（日期式 vYYYY.MM.N ↔ 语义 vX.Y，README 顶部注明）；代码 VERSION 统一更新（lite/full/compare/trends/release.sh）；README 徽章/下载名同步
- 2026-08-10（第六十三轮）：文档一致性彻查——AI_GUIDE初始化章节smoke项数19→22修正；TEST_METHOD 3GPP域名数1/2→3个（与core.sh DOMAINS_3GPP对齐，mnc011/mnc000/mnc001）；边界测试矩阵全过（无参数/注入/缺值/未知参数/超长参数/混合v4-v6，退出码1均正确）
- 2026-08-10（第六十二轮）：macOS timeout命令兼容——core.sh/smoke_test/doh_dot_check 三处加兼容函数（macOS 默认无 timeout，仅 coreutils 有；函数版后台sleep+kill模拟，正常/超时/管道三场景实测通过）；doh_dot_check 去冗余 timeout 包装（dig 用自带 +time、curl 用 --max-time，仅端口级保留）；网络环境矩阵实测：DEFAULT_DNS_CSV/PRESET_DNS_CSV/STAB_ROUNDS/ECS_SUBNET/PROVINCE_DNS 环境变量回退全部生效
- 2026-08-10（第六十一轮）：macOS bash 3.2 兼容性修复——compare.sh v3 / trends.sh 全部去掉 declare -A 关联数组（改平行数组+索引映射，macOS 默认 bash 3.2 可直跑）；install.sh 重构为"缺失才装+装完强制校验"（依赖已齐零sudo直达冒烟）；smoke下一步指引补compare行；README徽章 Bash 4+→3.2+；CI注释补macOS兼容提醒
- 2026-08-10（第六十轮）：全链路丝滑衔接——lite/full完成横幅加"对比/趋势"下一步提示、compare尾部加趋势提示（出口=入口闭环）；dns-test.sh专项菜单新增 8.多DNS对比 9.趋势洞察（带DNS引导输入）；install.sh下一步指引补compare/trends；smoke补第21项compare对比（21→22项）；非交互传多DNS时提示可用compare；AI_GUIDE命令映射表补两行
- 2026-08-10（第五十九轮）：新增 trends.sh DNS趋势洞察——聚合 results/compare-*.json（按DNS分组、按时间排序），线性回归斜率为主+首尾对比为辅的趋势判定（评分↑=变好/延迟↑=变好，箭头=好坏方向）；输出文本总览表+trends.csv+trends/report.html（纯SVG折线图，无JS依赖，响应式手机可看）；--detail/--limit/--since/DNS过滤；--cron 定时采集模式（先跑compare再聚合，附crontab示例）；环境变量 TRENDS_DIR/COMPARE_RESULTS_DIR；smoke补19/20项；README/AI_GUIDE同步
- 2026-08-10（第五十八轮）：compare.sh v2 重构——延迟改3次dig中位数（去掉名不副实的"平均"）；lite批次并发（默认3，COMPARE_MAX_CONCURRENCY可调，3 DNS从45s+降至~20s）；DNS去重；不可达DNS跳过lite；结构化JSON结果 results/compare-<ts>.json（供趋势积累）；HTML报告响应式（手机可看）+综合推荐结论+延迟颜色分级（绿<100ms 黄100~300ms 红≥300ms）+汇总表；退出码0/1/2（全不可达=2）；README目录结构/用法/更新记录同步
- 2026-08-10（第五十七轮）：compare.sh 延迟改为独立dig测量（lite版不输出延迟，避免无数据硬填）
- 2026-08-10（第五十六轮）：新增 compare.sh 多DNS对比模式（任意数量DNS + --html 生成 results/report.html）
- 2026-08-10（第五十五轮）：CI双平台矩阵（ubuntu+macOS）；macOS依赖安装改平台条件（自带dig/perl/curl）；流程连贯（install→smoke/下一步指引/AI_GUIDE初始化章节）
- 2026-08-10（第五十四轮）：新增 install.sh 一键安装脚本；README加CI徽章
- 2026-08-10（第五十三轮）：smoke专项覆盖补至18项、README补已知限制；CI加固（smoke workflow限main分支、网络敏感项容错）；release.sh自动查Release ID
- 2026-08-10（第五十二轮）：新增打包脚本 release.sh（自动排除.git/results内容/日志，防遗漏新文件，打印上传指引）+ CONTRIBUTING.md 贡献指南 + CI冒烟上线 + dig版本说明
- 2026-08-10（第五十一轮）：README加徽章（License/Release/Platform/Bash/Perl/CI）；smoke网络项超时加宽；AI_GUIDE补Windows/WSL环境说明
- 2026-08-10（第五十轮）：新增Windows使用指引（WSL推荐/GitBash注意事项）；README补ECS_SUBNET环境变量说明
- 2026-08-10（第四十九轮）：新增英文README（README.en.md精简版）+ README顶部中英互跳；新增Releases下载方式；gitignore排除tar.gz
- 2026-08-10（第四十八轮）：README结构整理——新增"获取与安装"章节、删除重复环境指引章节、补回效率提示标题
- 2026-08-10（第四十七轮）：目录结构补AI_GUIDE.md/LICENSE条目，同步交互工具表述
- 2026-08-10（第四十六轮）：md总审与更新记录去重修复；占位IP隐私说明（RFC 5737示例地址统一）；AI交互工具表述通用化
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
