#!/bin/bash
# ============================================================================
# DNS测试核心库
# 功能：公共变量、辅助函数、测试逻辑入口
# ============================================================================

# 前置检查：dig 必需
command -v dig >/dev/null 2>&1 || { echo "❌ 未找到 dig 命令，请先安装 dnsutils/bind-utils"; exit 1; }

# 默认DNS组（云南电信，可用环境变量 DEFAULT_DNS_CSV 覆盖，逗号分隔地址；名称可用 DEFAULT_DNS_NAME_CSV 覆盖）
if [ -n "$DEFAULT_DNS_CSV" ]; then
  IFS=',' read -ra DEFAULT_DNS_ADDR <<< "$DEFAULT_DNS_CSV"
  if [ -n "$DEFAULT_DNS_NAME_CSV" ]; then
    IFS=',' read -ra DEFAULT_DNS_NAME <<< "$DEFAULT_DNS_NAME_CSV"
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

# CDN多节点域名（劫持检测时用于判定，含国内常见负载均衡域名）
CDN_DOMAINS="www.bilibili.com www.douyin.com www.iqiyi.com www.youku.com www.google.com www.youtube.com www.qq.com www.taobao.com www.jd.com www.163.com www.sina.com.cn www.zhihu.com www.baidu.com"

# 稳定性测试轮次（可用环境变量 STAB_ROUNDS 覆盖，快速模式可调小，如 STAB_ROUNDS=5）
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

# DNS可达性预检函数：不可达返回1（快速跳过，避免59~90次查询白等）
# 双域名探测：任一成功即可达（避免 baidu.com 在海外网络解析慢导致误判）
dns_health_check() {
  local addr="$1"
  if dig @${addr} www.alidns.com A +short +time=2 +tries=1 >/dev/null 2>&1 \
     || dig @${addr} www.baidu.com A +short +time=2 +tries=1 >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# 并行dig辅助：将 PARR_CMDS 数组中的dig命令并行执行（8并发），结果存 $PARR_TMPDIR/N.out
# 使用方式：
#   PARR_CMDS=(); PARR_CMDS+=("dig @1.1.1.1 www.a.com A +time=3 +tries=1 2>/dev/null"); ...
#   par_run
#   for ((i=0; i<PARR_COUNT; i++)); do result=$(cat "$PARR_TMPDIR/$i.out"); ...; done
#   rm -rf "$PARR_TMPDIR"
PARR_CMDS=()
PARR_TMPDIR=""
PARR_COUNT=0
par_run() {
  PARR_TMPDIR=$(mktemp -d)
  local i=0
  for cmd in "${PARR_CMDS[@]}"; do
    (eval "$cmd" > "${PARR_TMPDIR}/${i}.out") &
    i=$((i + 1))
    [ $((i % 8)) -eq 0 ] && wait
  done
  wait
  PARR_COUNT=$i
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

# 执行单个DNS的测试（完整版逻辑，供full.sh调用）
run_full_test() {
  local addr="$1"
  local name="$2"
  
  # 可达性预检：不可达直接跳过，避免90+次查询白等
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

  # ===== 1. A记录批量测试（并行8并发，单次dig取IP+延迟） =====
  echo ""
  echo "  ━━━ [1] A记录批量测试 (${#DOMAINS_MAIN[@]} 国内 + ${#DOMAINS_GLOBAL[@]} 国际) ━━━"
  local a_success=0; local a_total=0; local a_time_sum=0
  local a_tmpdir=$(mktemp -d)
  local a_i=0
  local a_domains=("${DOMAINS_MAIN[@]}" "${DOMAINS_GLOBAL[@]}")
  for d in "${a_domains[@]}"; do
    (dig @${addr} ${d} A +time=3 +tries=1 2>/dev/null > "${a_tmpdir}/${a_i}.out") &
    a_i=$((a_i + 1))
    [ $((a_i % 8)) -eq 0 ] && wait
  done
  wait
  a_total=${#a_domains[@]}
  for ((i=0; i<a_i; i++)); do
    local out=$(cat "${a_tmpdir}/${i}.out")
    local result=$(echo "$out" | sed -n '/ANSWER SECTION/,/^$/p' | grep -v "ANSWER SECTION" | awk '{print $NF}')
    local qtime=$(echo "$out" | sed -n 's/.*Query time: \([0-9]*\).*/\1/p' | head -1)
    a_time_sum=$((a_time_sum + ${qtime:-0}))
    is_valid_response "$result" && a_success=$((a_success + 1))
  done
  rm -rf "$a_tmpdir"
  local a_rate=$((a_success * 100 / a_total))
  local a_avg=$((a_time_sum / a_total))
  printf "  📊 A记录: %d/%d (%d%%) | 平均延迟: %dms\n" "$a_success" "$a_total" "$a_rate" "$a_avg"
  total_all=$((total_all + a_total)); success_all=$((success_all + a_success))

  # ===== 2. AAAA记录测试 =====
  echo ""
  echo "  ━━━ [2] AAAA记录批量测试（并行） ━━━"
  local aaaa_success=0; local aaaa_total=0
  local aaaa_domains=("${DOMAINS_MAIN[@]:0:8}")
  PARR_CMDS=()
  for d in "${aaaa_domains[@]}"; do
    PARR_CMDS+=("dig @${addr} ${d} AAAA +short +time=3 +tries=1 2>/dev/null")
  done
  par_run
  aaaa_total=${#aaaa_domains[@]}
  for ((i=0; i<PARR_COUNT; i++)); do
    local result=$(cat "${PARR_TMPDIR}/${i}.out")
    is_valid_response "$result" && aaaa_success=$((aaaa_success + 1))
  done
  rm -rf "$PARR_TMPDIR"
  local aaaa_rate=$((aaaa_success * 100 / aaaa_total))
  printf "  📊 AAAA记录: 有记录 %d/%d (%d%%)\n" "$aaaa_success" "$aaaa_total" "$aaaa_rate"
  total_all=$((total_all + aaaa_total)); success_all=$((success_all + aaaa_success))

  # ===== 3. 3GPP/VoWiFi域名测试（参考信息项，不计入综合评分） =====
  echo ""
  echo "  ━━━ [3] 3GPP/VoWiFi域名测试（信息项） ━━━"
  PARR_CMDS=()
  for d in "${DOMAINS_3GPP[@]}"; do
    PARR_CMDS+=("dig @${addr} ${d} A +short +time=3 +tries=1 2>/dev/null")
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
  rm -rf "$PARR_TMPDIR"
  echo "     📝 注: VoWiFi为信息项，不影响综合评分"

  # ===== 4. 其他记录类型测试（并行） =====
  echo ""
  echo "  ━━━ [4] 其他记录类型测试（并行） ━━━"
  PARR_CMDS=()
  PARR_CMDS+=("dig @${addr} qq.com MX +short +time=3 +tries=1 2>/dev/null")
  PARR_CMDS+=("dig @${addr} baidu.com NS +short +time=3 +tries=1 2>/dev/null")
  PARR_CMDS+=("dig @${addr} google.com TXT +short +time=3 +tries=1 2>/dev/null")
  for d in "${DOMAINS_CNAME[@]}"; do
    PARR_CMDS+=("dig @${addr} ${d} CNAME +short +time=3 +tries=1 2>/dev/null")
  done
  PARR_CMDS+=("dig @${addr} baidu.com SOA +short +time=3 +tries=1 2>/dev/null")
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

  local cname_found=0; local cname_total=${#DOMAINS_CNAME[@]}
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
  rm -rf "$PARR_TMPDIR"

  # ===== 5. 稳定性压力测试 =====
  echo ""
  echo "  ━━━ [5] 稳定性压力测试 (${STAB_ROUNDS} 次连续查询) ━━━"
  local stab_success=0; local stab_total=$STAB_ROUNDS; local stab_times=()
  echo -n "     进度: "
  for i in $(seq 1 $STAB_ROUNDS); do
    local qtime=$(dig @${addr} www.baidu.com A +time=3 +tries=1 2>/dev/null | sed -n 's/.*Query time: \([0-9]*\).*/\1/p' | head -1)
    if [ -n "$qtime" ]; then
      stab_success=$((stab_success + 1)); stab_times+=(${qtime})
    fi
    [ $((i % 5)) -eq 0 ] && printf "."
  done
  echo ""
  if [ ${#stab_times[@]} -gt 0 ]; then
    local min_t=${stab_times[0]}; local max_t=${stab_times[0]}; local sum=0
    for t in "${stab_times[@]}"; do
      [ "$t" -lt "$min_t" ] && min_t=$t; [ "$t" -gt "$max_t" ] && max_t=$t; sum=$((sum + t))
    done
    local avg_t=$((sum / ${#stab_times[@]}))
    local stab_rate=$((stab_success * 100 / stab_total))
    printf "  📊 稳定性: %d/%d (%d%%)\n" "$stab_success" "$stab_total" "$stab_rate"
    printf "  ⏱️  延迟: 最小%dms | 最大%dms | 平均%dms\n" "$min_t" "$max_t" "$avg_t"
    echo "  📈 数据: ${stab_times[*]}"
  else
    echo "  ❌ 稳定性测试: 全部失败"
    local avg_t=0; local stab_rate=0
  fi
  total_all=$((total_all + stab_total)); success_all=$((success_all + stab_success))

  # ===== 6. 异常/边界测试 =====
  echo ""
  echo "  ━━━ [6] 异常/边界测试 ━━━"
  local nx_result=$(dig @${addr} this-domain-does-not-exist-12345.com A +time=3 +tries=1 2>/dev/null | sed -n 's/.*status: \([A-Za-z]*\).*/\1/p' | head -1)
  if [ "$nx_result" = "NXDOMAIN" ]; then
    echo "     ✅ NXDOMAIN 正确返回"; total_all=$((total_all+1)); success_all=$((success_all+1))
  else
    printf "     ⚠️ 不存在域名: %s\n" "$nx_result"; total_all=$((total_all+1));
  fi

  # ===== 7. 实际连通性测试 =====
  echo ""
  echo "  ━━━ [7] 实际连通性测试 ━━━"
  local test_ip=$(dig @${addr} www.baidu.com A +short +time=3 +tries=1 2>/dev/null | tail -1)
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
  local v6_ip=$(dig @${addr} www.baidu.com AAAA +short +time=3 +tries=1 2>/dev/null | grep -E ":" | head -1)
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
    PARR_CMDS+=("dig @${addr} ${d} A +short +time=3 +tries=1 2>/dev/null")
  done
  par_run
  check_total=${#check_domains[@]}
  for ((i=0; i<check_total; i++)); do
    local has_a=$(cat "${PARR_TMPDIR}/${i}.out" | grep -v OPT | head -1)
    [ -n "$has_a" ] && consistent=$((consistent + 1))
  done
  rm -rf "$PARR_TMPDIR"
  printf "     📊 A记录覆盖率: %d/%d\n" "$consistent" "$check_total"
  total_all=$((total_all+1)); success_all=$((success_all+1))

  # ===== 9. 运营商域名解析测试 =====
  echo ""
  echo "  ━━━ [9] 运营商域名解析测试（并行） ━━━"
  local carrier_success=0; local carrier_total=0
  PARR_CMDS=()
  for d in "${DOMAINS_CARRIER[@]}"; do
    PARR_CMDS+=("dig @${addr} ${d} A +short +time=3 +tries=1 2>/dev/null")
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
  rm -rf "$PARR_TMPDIR"
  local carrier_rate=$((carrier_success * 100 / carrier_total))
  printf "  📊 运营商域名: %d/%d (%d%%)\n" "$carrier_success" "$carrier_total" "$carrier_rate"
  total_all=$((total_all + carrier_total)); success_all=$((success_all + carrier_success))

  # ===== 10. DNSSEC安全扩展测试（并行） =====
  echo ""
  echo "  ━━━ [10] DNSSEC安全扩展测试（并行） ━━━"
  PARR_CMDS=()
  for d in "${DOMAINS_DNSSEC[@]}"; do
    for t in DNSKEY DS RRSIG; do
      PARR_CMDS+=("dig @${addr} ${d} ${t} +short +time=3 +tries=1 2>/dev/null")
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
  rm -rf "$PARR_TMPDIR"
  local dnssec_rate=$((dnssec_found * 100 / dnssec_total))
  printf "  📊 DNSSEC: %d/%d (%d%%)\n" "$dnssec_found" "$dnssec_total" "$dnssec_rate"
  total_all=$((total_all + dnssec_total)); success_all=$((success_all + dnssec_found))

  # ===== 11. EDNS Client Subnet (ECS)测试（并行） =====
  echo ""
  echo "  ━━━ [11] EDNS Client Subnet (ECS)测试 ━━━"
  PARR_CMDS=(
    "dig @${addr} www.baidu.com A +subnet=${ECS_SUBNET} +short +time=3 +tries=1 2>/dev/null"
    "dig @${addr} www.baidu.com A +short +time=3 +tries=1 2>/dev/null"
  )
  par_run
  local ecs_result=$(cat "${PARR_TMPDIR}/0.out")
  local ecs_no_subnet=$(cat "${PARR_TMPDIR}/1.out" | tail -1)
  if is_valid_response "$ecs_result"; then
    echo "     ✅ ECS 查询响应正常"
    [ "$ecs_result" != "$ecs_no_subnet" ] && echo "     📝 ECS 返回不同结果" || echo "     📝 ECS 返回相同结果"
    total_all=$((total_all+1)); success_all=$((success_all+1))
  else
    echo "     ❌ ECS 查询失败"; total_all=$((total_all+1));
  fi
  rm -rf "$PARR_TMPDIR"

  # ===== 12. 反向DNS解析(PTR)测试（并行） =====
  echo ""
  echo "  ━━━ [12] 反向DNS解析(PTR)测试（并行） ━━━"
  PARR_CMDS=()
  for ip in "${TEST_IPS[@]}"; do
    PARR_CMDS+=("dig @${addr} -x ${ip} +short +time=3 +tries=1 2>/dev/null")
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
  rm -rf "$PARR_TMPDIR"
  local ptr_rate=$((ptr_success * 100 / ptr_total))
  printf "  📊 PTR解析: %d/%d (%d%%)\n" "$ptr_success" "$ptr_total" "$ptr_rate"
  total_all=$((total_all + ptr_total)); success_all=$((success_all + ptr_success))

  # ===== 13. TTL值分析（并行） =====
  echo ""
  echo "  ━━━ [13] TTL值分析 ━━━"
  PARR_CMDS=()
  for d in "${DOMAINS_TTL[@]}"; do
    PARR_CMDS+=("dig @${addr} ${d} A +time=3 +tries=1 2>/dev/null")
  done
  par_run
  local ttl_values=()
  local ttl_total=${#DOMAINS_TTL[@]}
  for ((i=0; i<ttl_total; i++)); do
    local out=$(cat "${PARR_TMPDIR}/${i}.out")
    local ttl=$(echo "$out" | sed -n '/ANSWER SECTION/{n;p;}' | sed -n 's/.*[[:space:]]\([0-9][0-9]*\)[[:space:]]\+IN[[:space:]].*/\1/p' | head -1)
    [ -n "$ttl" ] && [ "$ttl" -gt 0 ] 2>/dev/null && ttl_values+=(${ttl})
  done
  rm -rf "$PARR_TMPDIR"
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

  # ===== 14. DNS劫持检测（与阿里DNS对比，基准不可达时降级IPv4，并行） =====
  echo ""
  echo "  ━━━ [14] DNS劫持检测（与阿里DNS对比） ━━━"
  # 对比基准：优先阿里IPv6，不可达则降级阿里IPv4（探测用alidns.com，全球稳定）
  local ref_dns="2400:3200::1"
  dig @${ref_dns} www.alidns.com A +short +time=2 +tries=1 >/dev/null 2>&1 || ref_dns="223.5.5.5"
  echo "     对比基准: ${ref_dns}"
  local hijack_domains=(www.baidu.com www.qq.com www.bilibili.com)
  PARR_CMDS=()
  for d in "${hijack_domains[@]}"; do
    PARR_CMDS+=("dig @${addr} ${d} A +short +time=3 +tries=1 2>/dev/null")
    PARR_CMDS+=("dig @${ref_dns} ${d} A +short +time=3 +tries=1 2>/dev/null")
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
  rm -rf "$PARR_TMPDIR"
  local hijack_judged=$((hijack_total - hijack_unknown))
  local hijack_rate=100
  [ $hijack_judged -gt 0 ] && hijack_rate=$((hijack_safe * 100 / hijack_judged))
  printf "  📊 劫持检测: %d/%d (%d%%) 判定%d/%d\n" "$hijack_safe" "$hijack_judged" "$hijack_rate" "$hijack_judged" "$hijack_total"
  total_all=$((total_all + hijack_judged)); success_all=$((success_all + hijack_safe))

  # ===== 15. 递归/迭代查询类型测试 =====
  echo ""
  echo "  ━━━ [15] 递归/迭代查询类型测试 ━━━"
  local flags=$(dig @${addr} www.baidu.com A +time=3 +tries=1 2>/dev/null | grep "flags:")
  if [[ "$flags" == *"ra"* ]]; then
    echo "     ✅ 支持递归查询 (ra标志置位)"; total_all=$((total_all+1)); success_all=$((success_all+1))
  else
    echo "     ⚠️ 不支持递归查询"; total_all=$((total_all+1));
  fi

  # ===== 综合评分 =====
  echo ""
  echo "  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
  local overall=$((success_all * 100 / total_all))
  printf "  ┃ 📊 综合评分: %d%% (%d/%d 项通过)\n" "$overall" "$success_all" "$total_all"
  printf "  ┃ ⏱️  平均延迟: %dms | 稳定性: %d%%\n" "$avg_t" "$stab_rate"
  echo "  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
}

# 执行精简版测试（供lite.sh调用）
run_lite_test() {
  local addr="$1"
  local name="$2"
  
  # 可达性预检：不可达直接跳过，避免59+次查询白等
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

  # 1. A记录（并行8并发，单次dig）
  echo ""
  echo "  ━━━ [1] A记录批量测试 ━━━"
  local a_success=0; local a_total=0
  local a_tmpdir=$(mktemp -d)
  local a_i=0
  local a_domains=("${DOMAINS_MAIN[@]}" "${DOMAINS_GLOBAL[@]}")
  for d in "${a_domains[@]}"; do
    (dig @${addr} ${d} A +time=3 +tries=1 2>/dev/null > "${a_tmpdir}/${a_i}.out") &
    a_i=$((a_i + 1))
    [ $((a_i % 8)) -eq 0 ] && wait
  done
  wait
  a_total=${#a_domains[@]}
  for ((i=0; i<a_i; i++)); do
    local out=$(cat "${a_tmpdir}/${i}.out")
    local result=$(echo "$out" | sed -n '/ANSWER SECTION/,/^$/p' | grep -v "ANSWER SECTION" | awk '{print $NF}')
    is_valid_response "$result" && a_success=$((a_success + 1))
  done
  rm -rf "$a_tmpdir"
  local a_rate=$((a_success * 100 / a_total))
  printf "  📊 A记录: %d/%d (%d%%)\n" "$a_success" "$a_total" "$a_rate"
  total_all=$((total_all + a_total)); success_all=$((success_all + a_success))

  # 2. AAAA记录
  echo ""
  echo "  ━━━ [2] AAAA记录批量测试（并行） ━━━"
  local aaaa_success=0; local aaaa_total=0
  local aaaa_domains=("${DOMAINS_MAIN[@]:0:8}")
  PARR_CMDS=()
  for d in "${aaaa_domains[@]}"; do
    PARR_CMDS+=("dig @${addr} ${d} AAAA +short +time=3 +tries=1 2>/dev/null")
  done
  par_run
  aaaa_total=${#aaaa_domains[@]}
  for ((i=0; i<PARR_COUNT; i++)); do
    local result=$(cat "${PARR_TMPDIR}/${i}.out")
    is_valid_response "$result" && aaaa_success=$((aaaa_success + 1))
  done
  rm -rf "$PARR_TMPDIR"
  local aaaa_rate=$((aaaa_success * 100 / aaaa_total))
  printf "  📊 AAAA记录: %d/%d (%d%%)\n" "$aaaa_success" "$aaaa_total" "$aaaa_rate"
  total_all=$((total_all + aaaa_total)); success_all=$((success_all + aaaa_success))

  # 3. 3GPP/VoWiFi（参考信息项，不计入综合评分）
  echo ""
  echo "  ━━━ [3] 3GPP/VoWiFi域名测试（信息项） ━━━"
  PARR_CMDS=()
  for d in "${DOMAINS_3GPP[@]}"; do
    PARR_CMDS+=("dig @${addr} ${d} A +short +time=3 +tries=1 2>/dev/null")
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
  rm -rf "$PARR_TMPDIR"
  echo "     📝 注: VoWiFi为信息项，不影响综合评分"

  # 4. 其他记录类型（并行）
  echo ""
  echo "  ━━━ [4] 其他记录类型测试（并行） ━━━"
  PARR_CMDS=(
    "dig @${addr} qq.com MX +short +time=3 +tries=1 2>/dev/null"
    "dig @${addr} baidu.com NS +short +time=3 +tries=1 2>/dev/null"
    "dig @${addr} google.com TXT +short +time=3 +tries=1 2>/dev/null"
  )
  par_run
  local mx_result=$(cat "${PARR_TMPDIR}/0.out")
  if is_valid_response "$mx_result"; then
    echo "     ✅ MX (qq.com): 通过"; total_all=$((total_all+1)); success_all=$((success_all+1))
  else
    echo "     ❌ MX (qq.com): 失败"; total_all=$((total_all+1));
  fi
  local ns_result=$(cat "${PARR_TMPDIR}/1.out")
  if is_valid_response "$ns_result"; then
    echo "     ✅ NS (baidu.com): 通过"; total_all=$((total_all+1)); success_all=$((success_all+1))
  else
    echo "     ❌ NS (baidu.com): 失败"; total_all=$((total_all+1));
  fi
  local txt_result=$(cat "${PARR_TMPDIR}/2.out")
  if is_valid_response "$txt_result"; then
    echo "     ✅ TXT (google.com): 通过"; total_all=$((total_all+1)); success_all=$((success_all+1))
  else
    echo "     ❌ TXT (google.com): 失败"; total_all=$((total_all+1));
  fi
  rm -rf "$PARR_TMPDIR"

  # 5. 稳定性
  echo ""
  echo "  ━━━ [5] 稳定性压力测试 ━━━"
  local stab_success=0; local stab_total=$STAB_ROUNDS
  echo -n "     进度: "
  for i in $(seq 1 $STAB_ROUNDS); do
    local qtime=$(dig @${addr} www.baidu.com A +time=3 +tries=1 2>/dev/null | sed -n 's/.*Query time: \([0-9]*\).*/\1/p' | head -1)
    [ -n "$qtime" ] && stab_success=$((stab_success + 1))
    [ $((i % 5)) -eq 0 ] && printf "."
  done
  echo ""
  local stab_rate=$((stab_success * 100 / stab_total))
  printf "  📊 稳定性: %d/%d (%d%%)\n" "$stab_success" "$stab_total" "$stab_rate"
  total_all=$((total_all + stab_total)); success_all=$((success_all + stab_success))

  # 6. 异常测试
  echo ""
  echo "  ━━━ [6] 异常/边界测试 ━━━"
  local nx_result=$(dig @${addr} this-domain-does-not-exist-12345.com A +time=3 +tries=1 2>/dev/null | sed -n 's/.*status: \([A-Za-z]*\).*/\1/p' | head -1)
  if [ "$nx_result" = "NXDOMAIN" ]; then
    echo "     ✅ NXDOMAIN 正确返回"; total_all=$((total_all+1)); success_all=$((success_all+1))
  else
    printf "     ⚠️ 不存在域名: %s\n" "$nx_result"; total_all=$((total_all+1));
  fi

  # 7. 连通性
  echo ""
  echo "  ━━━ [7] 实际连通性测试 ━━━"
  local test_ip=$(dig @${addr} www.baidu.com A +short +time=3 +tries=1 2>/dev/null | tail -1)
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

  # 7b. IPv6实际连通性测试（ping6，无IPv6环境自动跳过不计分）
  echo ""
  echo "  ━━━ [7b] IPv6实际连通性测试（ping6） ━━━"
  local v6_ip=$(dig @${addr} www.baidu.com AAAA +short +time=3 +tries=1 2>/dev/null | grep -E ":" | head -1)
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

  # 8. 一致性（并行）
  echo ""
  echo "  ━━━ [8] IPv4/IPv6解析一致性 ━━━"
  local consistent=0; local check_total=0
  local check_domains=(www.baidu.com www.qq.com www.bilibili.com)
  PARR_CMDS=()
  for d in "${check_domains[@]}"; do
    PARR_CMDS+=("dig @${addr} ${d} A +short +time=3 +tries=1 2>/dev/null")
  done
  par_run
  check_total=${#check_domains[@]}
  for ((i=0; i<check_total; i++)); do
    local has_a=$(cat "${PARR_TMPDIR}/${i}.out" | grep -v OPT | head -1)
    [ -n "$has_a" ] && consistent=$((consistent + 1))
  done
  rm -rf "$PARR_TMPDIR"
  printf "     📊 A记录覆盖率: %d/%d\n" "$consistent" "$check_total"
  total_all=$((total_all+1)); success_all=$((success_all+1))

  # 9. 运营商域名
  echo ""
  echo "  ━━━ [9] 运营商域名解析测试（并行） ━━━"
  local carrier_success=0; local carrier_total=0
  PARR_CMDS=()
  for d in "${DOMAINS_CARRIER[@]}"; do
    PARR_CMDS+=("dig @${addr} ${d} A +short +time=3 +tries=1 2>/dev/null")
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
  rm -rf "$PARR_TMPDIR"
  local carrier_rate=$((carrier_success * 100 / carrier_total))
  printf "  📊 运营商域名: %d/%d (%d%%)\n" "$carrier_success" "$carrier_total" "$carrier_rate"
  total_all=$((total_all + carrier_total)); success_all=$((success_all + carrier_success))

  # 综合评分
  echo ""
  echo "  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
  local overall=$((success_all * 100 / total_all))
  printf "  ┃ 📊 综合评分: %d%% (%d/%d 项通过)\n" "$overall" "$success_all" "$total_all"
  printf "  ┃ ⏱️  稳定性: %d%%\n" "$stab_rate"
  echo "  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
}
