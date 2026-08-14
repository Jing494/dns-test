#!/bin/bash
# shellcheck disable=SC2155,SC2034,SC1090,SC2046
# 豁免说明：
#   SC2155 (local x=$(cmd))：项目统一风格，47处机械替换风险高收益低
#   SC2034 (未使用变量)：ALI/TENCENT_DNS_* 为全局配置，供其他脚本 source 后使用（跨文件）
#   SC1090 (动态source)：source "$CONFIG_DOMAINS" 为合法动态加载
#   SC2046 (命令替换未引号)：dig @$(dig_target "$addr") 的 dig_target 输出为IP/地址，绝不含空白，分词无实际风险
# ============================================================================
# DNS测试核心库
# 功能：公共变量、辅助函数、测试逻辑入口
# ============================================================================

# 临时目录清理清单（各测试函数 mktemp 后追加，EXIT/INT/TERM 统一清理防泄漏）
TMPDIR_LIST=()

# 前置检查：dig + perl 必需（perl 用于专项测试）
command -v dig >/dev/null 2>&1 || { echo "❌ 未找到 dig 命令，请先安装 dnsutils/bind-utils"; exit 1; }
command -v perl >/dev/null 2>&1 || { echo "❌ 未找到 perl 命令，请先安装 perl（专项测试需要）"; exit 1; }

# 平台兼容层（timeout 兼容函数等，macOS 无 timeout 命令）
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compat.sh"

# 版本号单一来源（PROJECT_VERSION 日期式 / PROJECT_RELEASE 语义式）
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/version.sh"

# 默认DNS组（云南电信，可用环境变量 DEFAULT_DNS_CSV 覆盖，逗号分隔地址；名称可用 DEFAULT_DNS_NAME_CSV 覆盖）
if [ -n "$DEFAULT_DNS_CSV" ]; then
  IFS=',' read -ra DEFAULT_DNS_ADDR <<< "$DEFAULT_DNS_CSV"
  if [ -n "$DEFAULT_DNS_NAME_CSV" ]; then
    IFS=',' read -ra DEFAULT_DNS_NAME <<< "$DEFAULT_DNS_NAME_CSV"
    # 名称数量不足时自动补齐（防显示为空）
    while [ ${#DEFAULT_DNS_NAME[@]} -lt ${#DEFAULT_DNS_ADDR[@]} ]; do
      _ni=${#DEFAULT_DNS_NAME[@]}
      DEFAULT_DNS_NAME+=("自定义DNS(${DEFAULT_DNS_ADDR[$_ni]})")
    done
  else
    DEFAULT_DNS_NAME=()
    for _a in "${DEFAULT_DNS_ADDR[@]}"; do DEFAULT_DNS_NAME+=("自定义DNS(${_a})"); done
  fi
else
  DEFAULT_DNS_ADDR=(
    "240e:52:4800::8888"
    "240e:52:4000::8888"
    "222.172.200.68"
    "61.166.150.123"
  )
  DEFAULT_DNS_NAME=(
    "云南电信IPv6-DNS-1"
    "云南电信IPv6-DNS-2"
    "云南电信IPv4-DNS-1"
    "云南电信IPv4-DNS-2"
  )
fi

# 阿里云公共DNS（官方地址）
ALI_DNS_ADDR=(
  "223.5.5.5"
  "223.6.6.6"
  "2400:3200::1"
  "2400:3200:baba::1"
)
ALI_DNS_NAME=(
  "阿里DNS-v4-1"
  "阿里DNS-v4-2"
  "阿里DNS-v6-1"
  "阿里DNS-v6-2"
)

# 腾讯DNSPod公共DNS（官方地址）
TENCENT_DNS_ADDR=(
  "119.29.29.29"
  "2402:4e00::"
  "2402:4e00:1::"
)
TENCENT_DNS_NAME=(
  "腾讯DNSPod-v4"
  "腾讯DNSPod-v6-1"
  "腾讯DNSPod-v6-2"
)

# 国内主流网站
DOMAINS_MAIN=(
  "www.baidu.com" "www.qq.com" "www.bilibili.com" "www.zhihu.com"
  "www.taobao.com" "www.jd.com" "www.163.com" "www.sina.com.cn"
  "www.csdn.net" "www.github.com" "www.weibo.com" "www.douyin.com"
  "www.iqiyi.com" "www.youku.com" "www.mgtv.com"
)

# 国际主流网站
DOMAINS_GLOBAL=(
  "www.google.com" "www.youtube.com" "www.twitter.com"
  "www.facebook.com" "www.wikipedia.org" "www.amazon.com"
  "www.apple.com" "www.microsoft.com" "www.stackoverflow.com"
  "www.reddit.com"
)

# 3GPP/VoWiFi域名（信息项：电信mnc011实测部署；移动mnc000/联通mnc001代表，全量检测见carrier_epdg.pl）
DOMAINS_3GPP=(
  "epdg.epc.mnc011.mcc460.pub.3gppnetwork.org"
  "epdg.epc.mnc000.mcc460.pub.3gppnetwork.org"
  "epdg.epc.mnc001.mcc460.pub.3gppnetwork.org"
)

# CNAME测试域名
DOMAINS_CNAME=(
  "www.baidu.com" "www.qq.com" "www.bilibili.com"
  "www.zhihu.com" "www.taobao.com"
)

# 运营商域名
DOMAINS_CARRIER=(
  "www.10086.cn" "www.chinaunicom.com.cn"
  "www.189.cn" "www.10000.cn"
)

# DNSSEC测试域名
DOMAINS_DNSSEC=(
  "www.bankofamerica.com"
  "www.cloudflare.com"
  "www.icann.org"
)

# PTR反向解析测试IP
TEST_IPS=(
  "183.2.172.177" "121.14.77.201" "8.8.8.8"
)

# TTL分析测试域名
DOMAINS_TTL=(
  "www.baidu.com" "www.qq.com" "www.bilibili.com"
  "www.github.com" "www.google.com"
)

# 域名列表外置覆盖（可用 CONFIG_DOMAINS 环境变量指定配置文件，格式同本文件：DOMAINS_MAIN=("a.com" "b.com")）
# 安全加固（审阅#6）：不 source——仅逐行提取 DOMAINS_MAIN/GLOBAL 的双引号数组字面量手动解析，
# 外部文件无法触发命令执行；仅信任你自己生成的配置文件，来源不明的文件一律不要用（详见 README 警告）
if [ -n "$CONFIG_DOMAINS" ] && [ -f "$CONFIG_DOMAINS" ]; then
  while IFS= read -r _cfg_line; do
    case "$_cfg_line" in
      DOMAINS_MAIN=\(*|DOMAINS_GLOBAL=\(*)
        _cfg_name="${_cfg_line%%=*}"
        _cfg_body="${_cfg_line#*=}"
        _cfg_clean=(); _cfg_ok=1
        # 仅提取双引号包裹的 token，逐个校验为纯域名，任一非法则整行忽略
        while IFS= read -r _cfg_tok; do
          [ -n "$_cfg_tok" ] || continue
          _cfg_d="${_cfg_tok#\"}"; _cfg_d="${_cfg_d%\"}"
          if [[ "$_cfg_d" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            _cfg_clean+=("$_cfg_d")
          else
            _cfg_ok=0; break
          fi
        done <<< "$(printf '%s\n' "$_cfg_body" | grep -oE '"[^"]*"')"
        if [ "$_cfg_ok" -eq 1 ] && [ ${#_cfg_clean[@]} -gt 0 ]; then
          [ "$_cfg_name" = "DOMAINS_MAIN" ]   && DOMAINS_MAIN=( "${_cfg_clean[@]}" )
          [ "$_cfg_name" = "DOMAINS_GLOBAL" ] && DOMAINS_GLOBAL=( "${_cfg_clean[@]}" )
        else
          echo "⚠️ CONFIG_DOMAINS ${_cfg_name} 行内容非法，已忽略（仅支持 DOMAINS_MAIN/GLOBAL=(\"a\" \"b\") 双引号域名）" >&2
        fi
        ;;
      \#*|'') ;;
      *) echo "⚠️ CONFIG_DOMAINS 存在不支持的行，已忽略: $_cfg_line" >&2 ;;
    esac
  done < "$CONFIG_DOMAINS"
  unset _cfg_line _cfg_name _cfg_body _cfg_clean _cfg_ok _cfg_tok _cfg_d
fi

# CDN多节点域名（结果对比时用于判定，含国内常见负载均衡域名）
CDN_DOMAINS="www.bilibili.com www.douyin.com www.iqiyi.com www.youku.com www.google.com www.youtube.com www.qq.com www.taobao.com www.jd.com www.163.com www.sina.com.cn www.zhihu.com www.baidu.com"

# 稳定性测试轮次（可用环境变量 STAB_ROUNDS 覆盖，快速模式可调小，如 STAB_ROUNDS=5）
# 记录用户是否显式设置：未设置时 lite 默认减半（20→10）缩短耗时，full 保持 20（审阅#8）
STAB_ROUNDS_USER=0; [ -n "${STAB_ROUNDS+x}" ] && STAB_ROUNDS_USER=1
STAB_ROUNDS="${STAB_ROUNDS:-20}"
# 校验必须为正整数，非法值回退默认20（防除零）
[[ "$STAB_ROUNDS" =~ ^[1-9][0-9]*$ ]] || STAB_ROUNDS=20

# ECS测试使用的subnet（默认云南电信IPv6前缀，测其他DNS时可设环境变量 ECS_SUBNET 覆盖）
ECS_SUBNET="${ECS_SUBNET:-240e:52:4800::/48}"

# ping超时参数（Linux -W 单位=秒，macOS -W 单位=毫秒，需区分）
if [ "$(uname)" = "Darwin" ]; then
  PING_OPTS="-c 2 -W 2000"
else
  PING_OPTS="-c 2 -W 2"
fi

# 环境自检：输出当前运行环境摘要（供入口脚本标注，让结果可回溯）
print_env_info() {
  local os="Linux"
  [ "$(uname)" = "Darwin" ] && os="macOS"
  local deps=""
  command -v dig >/dev/null 2>&1 && deps="dig✅" || deps="dig❌"
  command -v perl >/dev/null 2>&1 && deps="${deps} perl✅" || deps="${deps} perl❌"
  command -v ping >/dev/null 2>&1 && deps="${deps} ping✅" || deps="${deps} ping❌"
  # IPv6 可用性快测（平台区分 -W 单位；用 loopback ::1 只验协议栈是否可用，
  # 不依赖外网 IPv6 可达性——海外/无 IPv6 路由网络不再误报"不可用"）
  local v6="不可用"
  local v6opts="-c 1 -W 1"
  [ "$(uname)" = "Darwin" ] && v6opts="-c 1 -W 1000"
  if command -v ping6 >/dev/null 2>&1; then
    ping6 $v6opts ::1 >/dev/null 2>&1 && v6="可用"
  elif command -v ping >/dev/null 2>&1; then
    ping -6 $v6opts ::1 >/dev/null 2>&1 && v6="可用"
  fi
  echo "  🌐 环境: ${os} | ${deps} | IPv6:${v6} | 端口测试需真机(UDP受限环境不可用)"
}

# DNS地址格式校验（IPv4/IPv6），非法返回1（防命令注入/误传）
valid_dns_addr() {
  local addr="$1"
  # IPv4 格式（每段 0-255，防 999.999.999.999 等超范围误判）
  if [[ "$addr" =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; then
    return 0
  fi
  # IPv6 格式（含冒号、仅hex和冒号）
  if [[ "$addr" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$addr" == *":"* ]]; then
    return 0
  fi
  return 1
}

# DNS可达性预检函数：不可达返回1（快速跳过，避免59~90次查询白等）
# 双域名并行探测：任一成功即可达（避免 baidu.com 在海外网络解析慢导致误判，且不可达 DNS 最多等 2s 而非 4s）
dns_health_check() {
  local addr="$1" p1 p2
  dig @$(dig_target "$addr") www.alidns.com A +short +time=2 +tries=1 >/dev/null 2>&1 & p1=$!
  dig @$(dig_target "$addr") www.baidu.com A +short +time=2 +tries=1 >/dev/null 2>&1 & p2=$!
  if wait "$p1" 2>/dev/null || wait "$p2" 2>/dev/null; then
    return 0
  fi
  return 1
}

# 并行dig辅助：将 PARR_CMDS 数组中的dig命令并行执行（PARR_MAX 并发，默认8），结果存 $PARR_TMPDIR/N.out
# 使用方式：
#   PARR_CMDS=(); PARR_CMDS+=("dig @1.1.1.1 www.a.com A +time=3 +tries=1 2>/dev/null"); ...
#   par_run
#   for ((i=0; i<PARR_COUNT; i++)); do result=$(cat "$PARR_TMPDIR/$i.out"); ...; done
#   临时目录由 par_run 自动注册进 TMPDIR_LIST，脚本退出/中断时由入口脚本 trap 统一清理
PARR_CMDS=()
PARR_TMPDIR=""
PARR_COUNT=0
# 并行并发上限（环境变量 PARR_MAX 可覆盖，调小可降低负载）
PARR_MAX="${PARR_MAX:-8}"
[[ "$PARR_MAX" =~ ^[1-9][0-9]*$ ]] || PARR_MAX=8
par_run() {
  PARR_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/dns-test.XXXXXX")
  TMPDIR_LIST+=("$PARR_TMPDIR")
  local i=0 cmd
  # 安全兜底（审阅#7）：par_run 只允许执行 dig 命令——bash 3.2（macOS）不支持数组套数组，
  # 以"命令白名单 + 地址/域名前置校验"把 eval 注入面收窄到零；任一非法命令立即整体拒绝
  for cmd in "${PARR_CMDS[@]}"; do
    case "$cmd" in
      dig\ *) ;;
      *) echo "par_run: 仅允许 dig 命令，已拒绝: $cmd" >&2; PARR_COUNT=0; return 1 ;;
    esac
  done
  for cmd in "${PARR_CMDS[@]}"; do
    (eval "$cmd" > "${PARR_TMPDIR}/${i}.out") &
    i=$((i + 1))
    [ $((i % PARR_MAX)) -eq 0 ] && wait
  done
  wait
  PARR_COUNT=$i
}

# 将DNS地址格式化为 dig @target 的地址形式：IPv6 需加方括号避免解析歧义，IPv4 原样返回
dig_target() {
  local a="$1"
  case "$a" in
    *:*) printf '%s' "[$a]" ;;
    *)   printf '%s' "$a" ;;
  esac
}

# ============================================================================
# 辅助函数
# ============================================================================

is_valid_response() {
  local result="$1"
  [ -z "$result" ] && return 1
  [[ "$result" == *"communications error"* ]] && return 1
  [[ "$result" == *"no servers could be reached"* ]] && return 1
  [[ "$result" == *"OPT"* ]] && [[ "$result" != *"IN"* ]] && return 1
  return 0
}

is_cdn_domain() {
  local domain="$1"
  for cdn in $CDN_DOMAINS; do
    [ "$domain" = "$cdn" ] && return 0
  done
  return 1
}

# 打印分隔线
print_separator() {
  echo "======================================================================"
}

# 打印带标题的头部
print_header() {
  local title="$1"
  echo "╔════════════════════════════════════════════════════════════════════════════╗"
  printf "║%-76s║\n" "  $title"
  echo "╚════════════════════════════════════════════════════════════════════════════╝"
  echo "测试时间: $(date '+%Y-%m-%d %H:%M:%S')"
}

# 执行单个DNS的测试（full/lite 共用逻辑，mode 控制差异点，消除 run_full_test/run_lite_test 重复代码）
# mode=full: 完整版（A记录延迟计算、CNAME/SOA记录、稳定性min/max/avg指标、DNSSEC/ECS/PTR/TTL/结果对比/递归）
# mode=lite: 精简版（仅基础项：A/AAAA/3GPP/MX·NS·TXT/稳定性/异常/连通性/IPv6/一致性/运营商）
# 供 full.sh/lite.sh 调用；run_full_test/run_lite_test 为薄包装（见文末）
run_common_tests() {
  local addr="$1"
  local name="$2"
  local mode="${3:-full}"
  local full=0
  [ "$mode" = "full" ] && full=1

  # 可达性预检：不可达直接跳过，避免大量查询白等
  if ! dns_health_check "$addr"; then
    echo ""
    echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    printf "┃  📡 %s [%s]\n" "$name" "$addr"
    printf "┃  ⚠️  DNS不可达（预检失败），已跳过该DNS\n"
    echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
    return 1
  fi
  echo ""
  echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
  printf "┃  📡 %s [%s]\n" "$name" "$addr"
  echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
  local total_all=0; local success_all=0

  # ===== 1. A记录批量测试（并行8并发；full计算平均延迟，lite不计算） =====
  echo ""
  echo "  ━━━ [1] A记录批量测试 (${#DOMAINS_MAIN[@]} 国内 + ${#DOMAINS_GLOBAL[@]} 国际) ━━━"
  local a_success=0; local a_total=0; local a_time_sum=0
  local a_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/dns-test.XXXXXX")
  TMPDIR_LIST+=("$a_tmpdir")
  local a_i=0
  local a_domains=("${DOMAINS_MAIN[@]}" "${DOMAINS_GLOBAL[@]}")
  for d in "${a_domains[@]}"; do
    (dig @$(dig_target "$addr") ${d} A +time=3 +tries=1 2>/dev/null > "${a_tmpdir}/${a_i}.out") &
    a_i=$((a_i + 1))
    [ $((a_i % 8)) -eq 0 ] && wait
  done
  wait
  a_total=${#a_domains[@]}
  for ((i=0; i<a_i; i++)); do
    local out=$(cat "${a_tmpdir}/${i}.out")
    # 解析：只取 ANSWER SECTION 的 A 记录 IP（输出与评分解耦——评分只看是否有效响应）
    local result=$(echo "$out" | sed -n '/ANSWER SECTION/,/^$/p' | awk '$3=="IN" && $4=="A"{print $NF}' | head -1)
    is_valid_response "$result" && a_success=$((a_success + 1))
    # 延迟仅 full 计算（需完整输出中的 Query time，+short 会抑制计时，故此处不用 +short）
    if [ "$full" -eq 1 ]; then
      local qtime=$(echo "$out" | sed -n 's/.*Query time: \([0-9]*\).*/\1/p' | head -1)
      a_time_sum=$((a_time_sum + ${qtime:-0}))
    fi
  done
  local a_rate=$((a_total ? a_success * 100 / a_total : 0))
  if [ "$full" -eq 1 ]; then
    local a_avg=$((a_total ? a_time_sum / a_total : 0))
    printf "  📊 A记录: %d/%d (%d%%) | 平均延迟: %dms\n" "$a_success" "$a_total" "$a_rate" "$a_avg"
  else
    printf "  📊 A记录: %d/%d (%d%%)\n" "$a_success" "$a_total" "$a_rate"
  fi
  total_all=$((total_all + a_total)); success_all=$((success_all + a_success))

  # ===== 2. AAAA记录测试 =====
  echo ""
  echo "  ━━━ [2] AAAA记录批量测试（并行） ━━━"
  local aaaa_success=0; local aaaa_total=0
  local aaaa_domains=("${DOMAINS_MAIN[@]:0:8}")
  PARR_CMDS=()
  for d in "${aaaa_domains[@]}"; do
    PARR_CMDS+=("dig @$(dig_target "$addr") ${d} AAAA +short +time=3 +tries=1 2>/dev/null")
  done
  par_run
  aaaa_total=${#aaaa_domains[@]}
  for ((i=0; i<PARR_COUNT; i++)); do
    local result=$(cat "${PARR_TMPDIR}/${i}.out")
    is_valid_response "$result" && aaaa_success=$((aaaa_success + 1))
  done
  local aaaa_rate=$((aaaa_total ? aaaa_success * 100 / aaaa_total : 0))
  printf "  📊 AAAA记录: 有记录 %d/%d (%d%%)\n" "$aaaa_success" "$aaaa_total" "$aaaa_rate"
  total_all=$((total_all + aaaa_total)); success_all=$((success_all + aaaa_success))

  # ===== 3. 3GPP/VoWiFi域名测试（参考信息项，不计入综合评分） =====
  echo ""
  echo "  ━━━ [3] 3GPP/VoWiFi域名测试（信息项） ━━━"
  PARR_CMDS=()
  for d in "${DOMAINS_3GPP[@]}"; do
    PARR_CMDS+=("dig @$(dig_target "$addr") ${d} A +short +time=3 +tries=1 2>/dev/null")
  done
  par_run
  for ((i=0; i<${#DOMAINS_3GPP[@]}; i++)); do
    local result=$(cat "${PARR_TMPDIR}/${i}.out")
    local d="${DOMAINS_3GPP[$i]}"
    if [ -n "$result" ]; then
      if ! echo "$result" | grep -vq "127\.0\.0\.1"; then
        printf "     ⚠️  %s → 127.0.0.1（运营商未部署ePDG，正常）\n" "$d"
      else
        printf "     ✅ %s → %s\n" "$d" "$(echo "$result" | tr '\n' ' ')"
      fi
    else
      printf "     ⚠️  %s → 无记录（公共DNS查不到，正常）\n" "$d"
    fi
  done
  echo "     📝 注: VoWiFi为信息项，不影响综合评分"

  # ===== 4. 其他记录类型测试（并行；lite仅MX/NS/TXT，full加CNAME/SOA） =====
  echo ""
  echo "  ━━━ [4] 其他记录类型测试（并行） ━━━"
  PARR_CMDS=()
  PARR_CMDS+=("dig @$(dig_target "$addr") qq.com MX +short +time=3 +tries=1 2>/dev/null")
  PARR_CMDS+=("dig @$(dig_target "$addr") baidu.com NS +short +time=3 +tries=1 2>/dev/null")
  PARR_CMDS+=("dig @$(dig_target "$addr") google.com TXT +short +time=3 +tries=1 2>/dev/null")
  local cname_total=0
  if [ "$full" -eq 1 ]; then
    for d in "${DOMAINS_CNAME[@]}"; do
      PARR_CMDS+=("dig @$(dig_target "$addr") ${d} CNAME +short +time=3 +tries=1 2>/dev/null")
    done
    PARR_CMDS+=("dig @$(dig_target "$addr") baidu.com SOA +short +time=3 +tries=1 2>/dev/null")
    cname_total=${#DOMAINS_CNAME[@]}
  fi
  par_run
  # 索引: 0=MX 1=NS 2=TXT 3..(3+CN-1)=CNAME (3+CN)=SOA
  local mx_result=$(cat "${PARR_TMPDIR}/0.out")
  if is_valid_response "$mx_result"; then
    printf "     ✅ MX (qq.com): %s\n" "$(echo "$mx_result" | head -1)"
    total_all=$((total_all+1)); success_all=$((success_all+1))
  else
    printf "     ❌ MX (qq.com): 失败\n"; total_all=$((total_all+1));
  fi

  local ns_result=$(cat "${PARR_TMPDIR}/1.out")
  if is_valid_response "$ns_result"; then
    printf "     ✅ NS (baidu.com): %s\n" "$(echo "$ns_result" | head -1)"
    total_all=$((total_all+1)); success_all=$((success_all+1))
  else
    printf "     ❌ NS (baidu.com): 失败\n"; total_all=$((total_all+1));
  fi

  local txt_result=$(cat "${PARR_TMPDIR}/2.out")
  if is_valid_response "$txt_result"; then
    echo "     ✅ TXT (google.com): ✓"; total_all=$((total_all+1)); success_all=$((success_all+1))
  else
    echo "     ❌ TXT (google.com): 失败"; total_all=$((total_all+1));
  fi

  if [ "$full" -eq 1 ]; then
    local cname_found=0
    for ((i=0; i<cname_total; i++)); do
      local cname_result=$(cat "${PARR_TMPDIR}/$((i+3)).out")
      is_valid_response "$cname_result" && cname_found=$((cname_found + 1))
    done
    if [ $cname_found -gt 0 ]; then
      printf "     ✅ CNAME: %d/%d 个域名存在\n" "$cname_found" "$cname_total"
      total_all=$((total_all+1)); success_all=$((success_all+1))
    else
      echo "     ❌ CNAME: 未找到"; total_all=$((total_all+1));
    fi

    local soa_result=$(cat "${PARR_TMPDIR}/$((cname_total+3)).out")
    if is_valid_response "$soa_result"; then
      echo "     ✅ SOA (baidu.com): ✓"; total_all=$((total_all+1)); success_all=$((success_all+1))
    else
      echo "     ❌ SOA (baidu.com): 失败"; total_all=$((total_all+1));
    fi
  fi

  # ===== 5. 稳定性压力测试（min/max/avg 与原始数据仅 full 输出，lite 只看成功率） =====
  # lite 未显式设置 STAB_ROUNDS 时默认减半（20→10），缩短 lite 耗时（审阅#8）
  local stab_rounds=$STAB_ROUNDS
  if [ "$full" -eq 0 ] && [ "$STAB_ROUNDS_USER" -eq 0 ]; then
    stab_rounds=$((STAB_ROUNDS / 2))
  fi
  echo ""
  echo "  ━━━ [5] 稳定性压力测试 (${stab_rounds} 次连续查询) ━━━"
  local stab_success=0; local stab_total=$stab_rounds; local stab_times=()
  echo -n "     进度: "
  for i in $(seq 1 $stab_rounds); do
    local qtime=$(dig @$(dig_target "$addr") www.baidu.com A +time=3 +tries=1 2>/dev/null | sed -n 's/.*Query time: \([0-9]*\).*/\1/p' | head -1)
    if [ -n "$qtime" ]; then
      stab_success=$((stab_success + 1)); stab_times+=("$qtime")
    fi
    [ $((i % 5)) -eq 0 ] && printf "."
  done
  echo ""
  local stab_rate=$((stab_total ? stab_success * 100 / stab_total : 0))
  printf "  📊 稳定性: %d/%d (%d%%)\n" "$stab_success" "$stab_total" "$stab_rate"
  local avg_t=0
  if [ "$full" -eq 1 ] && [ ${#stab_times[@]} -gt 0 ]; then
    local min_t=${stab_times[0]}; local max_t=${stab_times[0]}; local sum=0
    for t in "${stab_times[@]}"; do
      [ "$t" -lt "$min_t" ] && min_t=$t; [ "$t" -gt "$max_t" ] && max_t=$t; sum=$((sum + t))
    done
    avg_t=$((sum / ${#stab_times[@]}))
    printf "  ⏱️  延迟: 最小%dms | 最大%dms | 平均%dms\n" "$min_t" "$max_t" "$avg_t"
    echo "  📈 数据: ${stab_times[*]}"
  elif [ "$full" -eq 1 ]; then
    echo "  ❌ 稳定性测试: 全部失败"
  fi
  total_all=$((total_all + stab_total)); success_all=$((success_all + stab_success))

  # ===== 6. 异常/边界测试 =====
  echo ""
  echo "  ━━━ [6] 异常/边界测试 ━━━"
  local nx_result=$(dig @$(dig_target "$addr") this-domain-does-not-exist-12345.com A +time=3 +tries=1 2>/dev/null | sed -n 's/.*status: \([A-Za-z]*\).*/\1/p' | head -1)
  if [ "$nx_result" = "NXDOMAIN" ]; then
    echo "     ✅ NXDOMAIN 正确返回"; total_all=$((total_all+1)); success_all=$((success_all+1))
  else
    printf "     ⚠️ 不存在域名: %s\n" "$nx_result"; total_all=$((total_all+1));
  fi

  # ===== 7. 实际连通性测试 =====
  echo ""
  echo "  ━━━ [7] 实际连通性测试 ━━━"
  local test_ip=$(dig @$(dig_target "$addr") www.baidu.com A +short +time=3 +tries=1 2>/dev/null | tail -1)
  if [ -n "$test_ip" ] && [[ "$test_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    local ping_avg=$(ping ${PING_OPTS} ${test_ip} 2>&1 | sed -n 's/.*min\/avg.*= \([0-9.]*\)\/\([0-9.]*\)\/.*/\2/p' | head -1)
    if [ -n "$ping_avg" ]; then
      printf "     ✅ Ping %s: 平均 %sms\n" "$test_ip" "$ping_avg"
      total_all=$((total_all+1)); success_all=$((success_all+1))
    else
      printf "     ⚠️ Ping %s: 不通\n" "$test_ip"; total_all=$((total_all+1));
    fi
  else
    echo "     ⚠️ 无法获取有效IP"; total_all=$((total_all+1));
  fi

  # ===== 7b. IPv6实际连通性测试（ping6，无IPv6环境自动跳过不计分） =====
  echo ""
  echo "  ━━━ [7b] IPv6实际连通性测试（ping6） ━━━"
  local v6_ip=$(dig @$(dig_target "$addr") www.baidu.com AAAA +short +time=3 +tries=1 2>/dev/null | grep -E ":" | head -1)
  if [ -z "$v6_ip" ]; then
    echo "     ⚠️  DNS无法解析IPv6地址（该DNS可能无IPv6记录）"
  else
    # ping6 命令平台适配（Linux: ping6，macOS: ping -6）
    local ping6_cmd="ping6"
    command -v ping6 >/dev/null 2>&1 || ping6_cmd="ping -6"
    if [ "$(uname)" = "Darwin" ]; then
      ping6_cmd="${ping6_cmd} -c 2 -W 2000"
    else
      ping6_cmd="${ping6_cmd} -c 2 -W 2"
    fi
    local v6_rtt=$(${ping6_cmd} ${v6_ip} 2>&1 | sed -n 's/.*min\/avg.*= \([0-9.]*\)\/\([0-9.]*\)\/.*/\2/p' | head -1)
    if [ -n "$v6_rtt" ]; then
      printf "     ✅ IPv6 %s: 平均 %sms\n" "$v6_ip" "$v6_rtt"
      total_all=$((total_all+1)); success_all=$((success_all+1))
    else
      echo "     ⚠️  IPv6 ${v6_ip}: 不通或本机无IPv6网络（环境限制，不计分）"
    fi
  fi

  # ===== 8. IPv4/IPv6解析一致性（并行） =====
  echo ""
  echo "  ━━━ [8] IPv4/IPv6解析一致性 ━━━"
  local consistent=0; local check_total=0
  local check_domains=(www.baidu.com www.qq.com www.bilibili.com)
  PARR_CMDS=()
  for d in "${check_domains[@]}"; do
    PARR_CMDS+=("dig @$(dig_target "$addr") ${d} A +short +time=3 +tries=1 2>/dev/null")
  done
  par_run
  check_total=${#check_domains[@]}
  for ((i=0; i<check_total; i++)); do
    local has_a=$(cat "${PARR_TMPDIR}/${i}.out" | grep -v OPT | head -1)
    [ -n "$has_a" ] && consistent=$((consistent + 1))
  done
  printf "     📊 A记录覆盖率: %d/%d\n" "$consistent" "$check_total"
  total_all=$((total_all+1)); [ $consistent -gt 0 ] && success_all=$((success_all + 1))

  # ===== 9. 运营商域名解析测试 =====
  echo ""
  echo "  ━━━ [9] 运营商域名解析测试（并行） ━━━"
  local carrier_success=0; local carrier_total=0
  PARR_CMDS=()
  for d in "${DOMAINS_CARRIER[@]}"; do
    PARR_CMDS+=("dig @$(dig_target "$addr") ${d} A +short +time=3 +tries=1 2>/dev/null")
  done
  par_run
  carrier_total=${#DOMAINS_CARRIER[@]}
  for ((i=0; i<PARR_COUNT; i++)); do
    local result=$(cat "${PARR_TMPDIR}/${i}.out")
    if is_valid_response "$result"; then
      carrier_success=$((carrier_success + 1))
      printf "     ✅ %s → %s\n" "${DOMAINS_CARRIER[$i]}" "$(echo "$result" | tail -1)"
    else
      printf "     ❌ %s → 失败\n" "${DOMAINS_CARRIER[$i]}"
    fi
  done
  local carrier_rate=$((carrier_total ? carrier_success * 100 / carrier_total : 0))
  printf "  📊 运营商域名: %d/%d (%d%%)\n" "$carrier_success" "$carrier_total" "$carrier_rate"
  total_all=$((total_all + carrier_total)); success_all=$((success_all + carrier_success))

  # ===== 10~15. 高级项（DNSSEC/ECS/PTR/TTL/结果对比/递归）仅 full 模式执行 =====
  # （lite 模式到 [9] 即进入综合评分，缩短耗时；此 if 块内的代码保持原缩进）
  if [ "$full" -eq 1 ]; then
  # ===== 10. DNSSEC安全扩展测试（并行） =====
  echo ""
  echo "  ━━━ [10] DNSSEC安全扩展测试（并行） ━━━"
  PARR_CMDS=()
  for d in "${DOMAINS_DNSSEC[@]}"; do
    for t in DNSKEY DS RRSIG; do
      PARR_CMDS+=("dig @$(dig_target "$addr") ${d} ${t} +short +time=3 +tries=1 2>/dev/null")
    done
  done
  par_run
  local dnssec_found=0; local dnssec_total=${#DOMAINS_DNSSEC[@]}
  for ((i=0; i<dnssec_total; i++)); do
    local dnskey=$(cat "${PARR_TMPDIR}/$((i*3)).out")
    local ds=$(cat "${PARR_TMPDIR}/$((i*3+1)).out")
    local rrsig=$(cat "${PARR_TMPDIR}/$((i*3+2)).out")
    if is_valid_response "$dnskey" || is_valid_response "$ds" || is_valid_response "$rrsig"; then
      dnssec_found=$((dnssec_found + 1))
      printf "     ✅ %s: DNSSEC记录存在\n" "${DOMAINS_DNSSEC[$i]}"
    else
      printf "     ⚠️ %s: 无DNSSEC记录\n" "${DOMAINS_DNSSEC[$i]}"
    fi
  done
  local dnssec_rate=$((dnssec_total ? dnssec_found * 100 / dnssec_total : 0))
  printf "  📊 DNSSEC: %d/%d (%d%%)\n" "$dnssec_found" "$dnssec_total" "$dnssec_rate"
  total_all=$((total_all + dnssec_total)); success_all=$((success_all + dnssec_found))

  # ===== 11. EDNS Client Subnet (ECS)测试（并行） =====
  echo ""
  echo "  ━━━ [11] EDNS Client Subnet (ECS)测试 ━━━"
  PARR_CMDS=(
    "dig @$(dig_target "$addr") www.baidu.com A +subnet=${ECS_SUBNET} +short +time=3 +tries=1 2>/dev/null"
    "dig @$(dig_target "$addr") www.baidu.com A +short +time=3 +tries=1 2>/dev/null"
  )
  par_run
  local ecs_result=$(cat "${PARR_TMPDIR}/0.out")
  local ecs_no_subnet=$(cat "${PARR_TMPDIR}/1.out" | tail -1)
  if is_valid_response "$ecs_result"; then
    echo "     ✅ ECS 查询响应正常"
    # 两边都取最后一行（IP）再比较，避免多行 vs 单行误判恒"不同"
    local ecs_one=$(echo "$ecs_result" | tail -1)
    [ "$ecs_one" != "$ecs_no_subnet" ] && echo "     📝 ECS 返回不同结果" || echo "     📝 ECS 返回相同结果"
    total_all=$((total_all+1)); success_all=$((success_all+1))
  else
    echo "     ❌ ECS 查询失败"; total_all=$((total_all+1));
  fi

  # ===== 12. 反向DNS解析(PTR)测试（并行） =====
  echo ""
  echo "  ━━━ [12] 反向DNS解析(PTR)测试（并行） ━━━"
  PARR_CMDS=()
  for ip in "${TEST_IPS[@]}"; do
    PARR_CMDS+=("dig @$(dig_target "$addr") -x ${ip} +short +time=3 +tries=1 2>/dev/null")
  done
  par_run
  local ptr_success=0; local ptr_total=${#TEST_IPS[@]}
  for ((i=0; i<ptr_total; i++)); do
    local ptr_result=$(cat "${PARR_TMPDIR}/${i}.out")
    if is_valid_response "$ptr_result"; then
      ptr_success=$((ptr_success + 1))
      printf "     ✅ %s → %s\n" "${TEST_IPS[$i]}" "$ptr_result"
    else
      printf "     ⚠️ %s → 无PTR记录\n" "${TEST_IPS[$i]}"
    fi
  done
  local ptr_rate=$((ptr_total ? ptr_success * 100 / ptr_total : 0))
  printf "  📊 PTR解析: %d/%d (%d%%)\n" "$ptr_success" "$ptr_total" "$ptr_rate"
  total_all=$((total_all + ptr_total)); success_all=$((success_all + ptr_success))

  # ===== 13. TTL值分析（并行） =====
  echo ""
  echo "  ━━━ [13] TTL值分析 ━━━"
  PARR_CMDS=()
  for d in "${DOMAINS_TTL[@]}"; do
    PARR_CMDS+=("dig @$(dig_target "$addr") ${d} A +time=3 +tries=1 2>/dev/null")
  done
  par_run
  local ttl_values=()
  local ttl_total=${#DOMAINS_TTL[@]}
  for ((i=0; i<ttl_total; i++)); do
    local out=$(cat "${PARR_TMPDIR}/${i}.out")
    local ttl=$(echo "$out" | sed -n '/ANSWER SECTION/{n;p;}' | sed -n 's/.*[[:space:]]\([0-9][0-9]*\)[[:space:]]\+IN[[:space:]].*/\1/p' | head -1)
    [ -n "$ttl" ] && [ "$ttl" -gt 0 ] 2>/dev/null && ttl_values+=("$ttl")
  done
  if [ ${#ttl_values[@]} -gt 0 ]; then
    local ttl_min=${ttl_values[0]}; local ttl_max=${ttl_values[0]}; local ttl_sum=0
    for t in "${ttl_values[@]}"; do
      [ "$t" -lt "$ttl_min" ] && ttl_min=$t; [ "$t" -gt "$ttl_max" ] && ttl_max=$t; ttl_sum=$((ttl_sum + t))
    done
    local ttl_avg=$((ttl_sum / ${#ttl_values[@]}))
    printf "     📊 TTL范围: %ds ~ %ds | 平均: %ds\n" "$ttl_min" "$ttl_max" "$ttl_avg"
    total_all=$((total_all+1)); success_all=$((success_all+1))
  else
    echo "     ⚠️ 无法获取TTL值"; total_all=$((total_all+1));
  fi

  # ===== 14. 解析结果对比（与阿里DNS，结果不同仅作疑似劫持提示，基准不可达时降级IPv4，并行） =====
  echo ""
  echo "  ━━━ [14] 解析结果对比（与阿里DNS，疑似劫持提示） ━━━"
  # 对比基准：优先阿里IPv6，不可达则降级阿里IPv4（探测用alidns.com，全球稳定）
  local ref_dns="2400:3200::1"
  dig @$(dig_target "$ref_dns") www.alidns.com A +short +time=2 +tries=1 >/dev/null 2>&1 || ref_dns="223.5.5.5"
  echo "     对比基准: ${ref_dns}"
  local hijack_domains=(www.baidu.com www.qq.com www.bilibili.com)
  PARR_CMDS=()
  for d in "${hijack_domains[@]}"; do
    PARR_CMDS+=("dig @$(dig_target "$addr") ${d} A +short +time=3 +tries=1 2>/dev/null")
    PARR_CMDS+=("dig @$(dig_target "$ref_dns") ${d} A +short +time=3 +tries=1 2>/dev/null")
  done
  par_run
  local hijack_safe=0; local hijack_total=${#hijack_domains[@]}; local hijack_unknown=0
  for ((i=0; i<hijack_total; i++)); do
    local d="${hijack_domains[$i]}"
    local local_result=$(cat "${PARR_TMPDIR}/$((i*2)).out" | tail -1)
    local ref_result=$(cat "${PARR_TMPDIR}/$((i*2+1)).out" | tail -1)
    if [ -z "$local_result" ]; then
      printf "     ⚠️ %s: 本地解析失败\n" "$d"
    elif [ -z "$ref_result" ]; then
      hijack_unknown=$((hijack_unknown + 1))
      printf "     ⚠️ %s: 基准不可达，无法对比（不计入判定）\n" "$d"
    elif [ "$local_result" = "$ref_result" ]; then
      hijack_safe=$((hijack_safe + 1))
      printf "     ✅ %s: 结果一致 (%s)\n" "$d" "$local_result"
    elif is_cdn_domain "$d"; then
      hijack_safe=$((hijack_safe + 1))
      printf "     ✅ %s: 结果不同但为CDN/负载均衡域名（正常）\n" "$d"
    else
      printf "     ⚠️ %s: 本地=%s, 基准=%s（结果不同，可能为负载均衡或异常）\n" "$d" "$local_result" "$ref_result"
    fi
  done
  local hijack_judged=$((hijack_total - hijack_unknown))
  # 无可判定项（基准全不可达）时显示 N/A，避免"对比一致 100%"误导（审阅#10）
  local hijack_rate="N/A"
  [ $hijack_judged -gt 0 ] && hijack_rate="$((hijack_safe * 100 / hijack_judged))%"
  printf "  📊 对比一致: %d/%d (%s) 判定%d/%d\n" "$hijack_safe" "$hijack_judged" "$hijack_rate" "$hijack_judged" "$hijack_total"
  total_all=$((total_all + hijack_judged)); success_all=$((success_all + hijack_safe))

  # ===== 15. 递归/迭代查询类型测试 =====
  echo ""
  echo "  ━━━ [15] 递归/迭代查询类型测试 ━━━"
  local flags=$(dig @$(dig_target "$addr") www.baidu.com A +time=3 +tries=1 2>/dev/null | grep "flags:")
  if [[ "$flags" == *"ra"* ]]; then
    echo "     ✅ 支持递归查询 (ra标志置位)"; total_all=$((total_all+1)); success_all=$((success_all+1))
  else
    echo "     ⚠️ 不支持递归查询"; total_all=$((total_all+1));
  fi
  fi  # 结束高级项（仅 full 模式）

  # ===== 综合评分（lite 仅基础项口径，full 含延迟/对比一致） =====
  echo ""
  echo "  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
  local overall=$((total_all ? success_all * 100 / total_all : 0))
  printf "  ┃ 📊 综合评分: %d%% (%d/%d 项通过)\n" "$overall" "$success_all" "$total_all"
  if [ "$full" -eq 1 ]; then
    printf "  ┃ ⏱️  平均延迟: %dms | 稳定性: %d%%\n" "$avg_t" "$stab_rate"
    printf "  ┃ 🔑 关键指标: A记录%d%% 稳定性%d%% 对比一致%d/%d\n" "$a_rate" "$stab_rate" "$hijack_safe" "$hijack_judged"
  else
    printf "  ┃ ⏱️  稳定性: %d%%\n" "$stab_rate"
    printf "  ┃ 🔑 关键指标: A记录%d%% 稳定性%d%%\n" "$a_rate" "$stab_rate"
  fi
  echo "  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
}

# ============================================================================
# 薄包装：run_full_test / run_lite_test 复用 run_common_tests（mode 控制差异点）
# 消除原 run_full_test（约300行）与 run_lite_test（约230行）的重复代码
# ============================================================================
# 完整版测试（供 full.sh 调用；含延迟计算、CNAME/SOA、稳定性min/max/avg、高级项）
run_full_test() {
  run_common_tests "$1" "$2" "full"
}

# 精简版测试（供 lite.sh 调用；仅基础项，缩短耗时）
run_lite_test() {
  run_common_tests "$1" "$2" "lite"
}
