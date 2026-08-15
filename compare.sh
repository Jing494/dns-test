#!/bin/bash
# ============================================================================
# 多DNS对比模式（v3：并行 + 延迟中位数 + 结构化JSON + HTML报告）
# 兼容性: bash 3.2+（无关联数组依赖，macOS 默认 bash 可直接运行）
# 用法: bash compare.sh DNS1|预设组 [DNS2 ...] [--html] [--md] [--no-save] [--watch N]
#   例: bash compare.sh 223.5.5.5 119.29.29.29 222.172.200.68
#       bash compare.sh ali tencent          # 预设组名直接对比（default/ali/tencent/all，可与IP混用）
#       bash compare.sh 223.5.5.5 119.29.29.29 --html   # 生成 results/report.html
#       bash compare.sh 223.5.5.5 --no-save             # 不保存JSON结果
#       bash compare.sh 223.5.5.5 119.29.29.29 --md     # 生成 results/report.md（GitHub/PR友好）
#       bash compare.sh 223.5.5.5 119.29.29.29 --watch 30 --html  # 每30分钟采集一轮（Ctrl-C停止）
# 环境变量:
#   COMPARE_MAX_CONCURRENCY  lite测试并行数上限（默认3；设1为串行，结果最稳）
# 输出:
#   文本对比表格；--html 生成 results/report.html（响应式，手机可看）；
#   --md 生成 results/report.md；--md/--html 可同时使用
#   --watch N 定时采集：每N分钟跑一轮并落JSON（趋势数据源，Ctrl-C优雅停止）；
#   有上一轮JSON时自动输出环比（Δ评分/Δ延迟），并给出按当前系统的切换命令
#   JSON结果默认保存 results/compare-<时间戳>.json（供历史趋势积累）
# 退出码: 0=完成  1=参数错误  2=全部DNS不可达
# ============================================================================
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 1
cd "$SCRIPT_DIR" || exit 1
source lib/core.sh
# 异常退出时统一清理：全部临时目录走 TMPDIR_LIST（含 par_run 自动注册的 PARR_TMPDIR），trap 延迟求值
# 空数组/空值时避免 macOS 的 rm 收到空串参数而报错（审阅#1）
trap '[ "${#TMPDIR_LIST[@]}" -gt 0 ] && rm -rf "${TMPDIR_LIST[@]}"' EXIT INT TERM

VERSION="${PROJECT_VERSION}"
GEN_HTML=0
GEN_MD=0
SAVE_JSON=1
MODE="lite"    # lite(默认) / full
# lite默认计分点（无IPv6环境=53；IPv6可用时7b项参与计分=54，环境相关；稳定性lite降轮为10）
LITE_ITEMS="53"

# ---------- 参数解析 ----------
# --watch N（定时采集）先行剥离：其取值参数与自身不进正常解析，剩余参数存 CLEAN_ARGS 供采集轮回放
WATCH_N=""
wnext=0
CLEAN_ARGS=()
for a in "$@"; do
  if [ "$wnext" = "1" ]; then
    WATCH_N="$a"; wnext=0; continue
  fi
  case "$a" in
    --watch)   wnext=1 ;;
    --watch=*) WATCH_N="${a#--watch=}" ;;
    *)         CLEAN_ARGS+=("$a") ;;
  esac
done
# --watch 后必须跟正整数值；缺值时 wnext 残留为1，静默吞掉会跑成"单轮无提示"，必须显式报错
[ "$wnext" = "1" ] && { echo "❌ --watch 缺少分钟数值（例: --watch 30）"; exit 1; }
DNS_ARGS=()
for a in "${CLEAN_ARGS[@]}"; do
  case "$a" in
    --html)     GEN_HTML=1 ;;
    --md)       GEN_MD=1 ;;
    --full)     MODE="full" ;;
    --no-save)  SAVE_JSON=0 ;;
    --version)
      echo "dns-test ${PROJECT_VERSION} (${PROJECT_RELEASE})"
      exit 0 ;;
    --help|-h)
      echo "用法: bash compare.sh DNS1|预设组 [DNS2 ...] [--html] [--md] [--full] [--no-save] [--watch N]"
      echo "  预设组: default(默认) / ali / tencent / all —— 可与IP混用，展开后自动去重"
      echo "  例: bash compare.sh 223.5.5.5 119.29.29.29 222.172.200.68"
      echo "      bash compare.sh ali tencent               # 直接对比预设组"
      echo "      bash compare.sh 223.5.5.5 119.29.29.29 --html    # 生成 results/report.html"
      echo "      bash compare.sh 223.5.5.5 119.29.29.29 --md      # 生成 results/report.md（GitHub/PR友好）"
      echo "      bash compare.sh 223.5.5.5 119.29.29.29 --full    # 用完整版测试(77~78项/DNS)"
      echo "      bash compare.sh 223.5.5.5 119.29.29.29 --watch 30 # 每30分钟采集一轮(Ctrl-C停止,供trends)"
      echo "环境变量: COMPARE_MAX_CONCURRENCY=3  (并行数,1=串行最稳)"
      exit 0 ;;
    *) DNS_ARGS+=("$a") ;;
  esac
done

# ---------- 预设组名展开（default/ali/tencent/all → core.sh 预设地址，可与IP混用后统一校验去重） ----------
PRESET_HIT=0
EXP=()
for a in "${DNS_ARGS[@]}"; do
  case "$a" in
    default|def|yunnan|yn) EXP+=("${DEFAULT_DNS_ADDR[@]}");  PRESET_HIT=1 ;;
    ali|alibaba)           EXP+=("${ALI_DNS_ADDR[@]}");     PRESET_HIT=1 ;;
    tencent|tx|dnspod)     EXP+=("${TENCENT_DNS_ADDR[@]}"); PRESET_HIT=1 ;;
    all)                   EXP+=("${DEFAULT_DNS_ADDR[@]}" "${ALI_DNS_ADDR[@]}" "${TENCENT_DNS_ADDR[@]}"); PRESET_HIT=1 ;;
    *)                     EXP+=("$a") ;;
  esac
done
[ "$PRESET_HIT" = "1" ] && DNS_ARGS=("${EXP[@]}")

# ---------- 校验 + 去重（普通数组线性查重，兼容bash 3.2） ----------
SEEN_LIST=()
UNIQ=()
for d in "${DNS_ARGS[@]}"; do
  if ! valid_dns_addr "$d"; then
    echo "❌ 非法DNS地址: $d"; exit 1
  fi
  dup=0
  for s in "${SEEN_LIST[@]}"; do [ "$s" = "$d" ] && dup=1; done
  if [ "$dup" = "1" ]; then
    echo "  ⚠️  重复DNS跳过: $d"
  else
    SEEN_LIST+=("$d"); UNIQ+=("$d")
  fi
done
DNS_ARGS=("${UNIQ[@]}")
if [ ${#DNS_ARGS[@]} -eq 0 ]; then
  echo "用法: bash compare.sh DNS1|预设组 [DNS2 ...] [--html] [--md] [--full] [--no-save] [--watch N]"
  echo "  预设组: default(默认) / ali / tencent / all —— 可与IP混用，例: bash compare.sh ali 119.29.29.29"
  exit 1
fi

# ---------- 定时采集模式（--watch N）：每N分钟重放一轮自身，打通 trends.sh 数据源 ----------
if [ -n "$WATCH_N" ]; then
  # 分钟数必须为正整数（与 STAB_ROUNDS 校验同风格）
  if ! [[ "$WATCH_N" =~ ^[1-9][0-9]*$ ]]; then
    echo "❌ --watch 参数必须为正整数分钟数，收到: $WATCH_N"; exit 1
  fi
  # 采集的意义在于落 JSON 攒趋势；配 --no-save 属自相矛盾，从回放参数中剔除并提示
  if [ "$SAVE_JSON" = "0" ]; then
    echo "  ⚠️  --watch 需要 JSON 落盘供 trends.sh 使用，已忽略 --no-save"
    CA2=()
    for ca in "${CLEAN_ARGS[@]}"; do
      [ "$ca" != "--no-save" ] && CA2+=("$ca")
    done
    CLEAN_ARGS=("${CA2[@]}")
  fi
  WROUND=0
  trap 'echo ""; echo "🛑 已停止采集（共完成 ${WROUND} 轮，可用 bash trends.sh --html 查看趋势）"; exit 0' INT TERM
  echo "⏱️  定时采集: 每 ${WATCH_N} 分钟一轮（Ctrl-C 停止）  对比DNS: ${DNS_ARGS[*]}"
  while :; do
    WROUND=$((WROUND+1))
    echo ""
    echo "════ 第 ${WROUND} 轮采集 $(date '+%Y-%m-%d %H:%M:%S') ════"
    # 子轮重放（含 --html/--md 等原参数）；子轮自身 exit 2（全不可达）不终止采集
    bash "$0" "${CLEAN_ARGS[@]}" || true
    echo "  ⏳ ${WATCH_N} 分钟后进行下一轮（Ctrl-C 停止）"
    # sleep 后台化 + wait：Ctrl-C 能立即中断等待而不是等满整个间隔
    sleep $((WATCH_N * 60)) & wait $!
  done
fi

print_header "多DNS对比测试 (v3) — $( [ "$MODE" = "full" ] && echo "完整版 77~78项/DNS" || echo "lite精简版 ${LITE_ITEMS}项/DNS" )"
echo "  对比DNS: ${DNS_ARGS[*]}"
echo "  测试并发: ${COMPARE_MAX_CONCURRENCY:-3}（设1为串行最稳）"
T0=$(date +%s)

# ---------- 当前系统 DNS 检测（只读展示用：对比表 👤 标记；读取失败静默跳过，不影响测试） ----------
# macOS scutil --dns 优先；systemd 环境用 resolvectl dns；兜底解析 /etc/resolv.conf（WSL/普通Linux）
CUR_DNS_LIST=()
if [ "$(uname -s)" = "Darwin" ] && command -v scutil >/dev/null 2>&1; then
  for _ns in $(scutil --dns 2>/dev/null | sed -n 's/^ *nameserver\[[0-9][0-9]*\] : \([0-9a-fA-F.:]*\)$/\1/p' | sort -u); do
    CUR_DNS_LIST+=("$_ns")
  done
elif command -v resolvectl >/dev/null 2>&1 && resolvectl dns >/dev/null 2>&1; then
  for _ns in $(resolvectl dns 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}|([0-9a-fA-F]{1,4}:){2,7}[0-9a-fA-F]{0,4}' | sort -u); do
    CUR_DNS_LIST+=("$_ns")
  done
fi
if [ ${#CUR_DNS_LIST[@]} -eq 0 ] && [ -r /etc/resolv.conf ]; then
  for _ns in $(sed -n 's/^nameserver \([0-9a-fA-F.:][0-9a-fA-F.:]*\).*/\1/p' /etc/resolv.conf | sort -u); do
    CUR_DNS_LIST+=("$_ns")
  done
fi
# is_current_dns <addr>：该地址是否为当前系统在用 DNS（线性查，兼容bash 3.2）
is_current_dns() {
  [ ${#CUR_DNS_LIST[@]} -eq 0 ] && return 1
  for _c in "${CUR_DNS_LIST[@]}"; do [ "$_c" = "$1" ] && return 0; done
  return 1
}
if [ ${#CUR_DNS_LIST[@]} -gt 0 ]; then
  echo "  👤 当前系统DNS: ${CUR_DNS_LIST[*]}"
fi

# ============================================================================
# 1) 延迟探测：每DNS 3次dig（par_run并行），取中位数
#    平行数组 DELAY_VAL[i] 对应 DNS_ARGS[i]
# ============================================================================
DELAY_VAL=()
echo ""
echo "  ━━━ [0] 延迟探测（每DNS 3次dig → 中位数） ━━━"
PARR_CMDS=()
for d in "${DNS_ARGS[@]}"; do
  for i in 1 2 3; do
    PARR_CMDS+=("dig @$(dig_target "$d") www.baidu.com A +time=2 +tries=1 2>/dev/null | sed -n 's/.*Query time: \\([0-9]*\\) msec.*/\\1/p'")
  done
done
par_run
idx=0
for d in "${DNS_ARGS[@]}"; do
  vals=()
  for i in 1 2 3; do
    v=$(cat "${PARR_TMPDIR}/${idx}.out" 2>/dev/null | tr -d '[:space:]')
    [ -n "$v" ] && [[ "$v" =~ ^[0-9]+$ ]] && vals+=("$v")
    idx=$((idx+1))
  done
  if [ ${#vals[@]} -gt 0 ]; then
    sorted=$(printf '%s\n' "${vals[@]}" | sort -n)
    DELAY_VAL+=("$(echo "$sorted" | sed -n "$(( (${#vals[@]} / 2) + 1 ))p")")
    printf "     ✅ %-42s 延迟中位 %sms (样本%d)\n" "$d" "${DELAY_VAL[${#DELAY_VAL[@]}-1]}" "${#vals[@]}"
  else
    DELAY_VAL+=("")
    printf "     ❌ %-42s 不可达（3次dig均无响应）\n" "$d"
  fi
done

# ============================================================================
# 2) lite 测试（批次并发，上限 MAXC）
#    平行数组 SCORE_VAL[i] / STAB_VAL[i] 对应 DNS_ARGS[i]
# ============================================================================
SCORE_VAL=()
STAB_VAL=()
MAXC="${COMPARE_MAX_CONCURRENCY:-3}"
[[ "$MAXC" =~ ^[1-9][0-9]*$ ]] || MAXC=3
echo ""
echo "  ━━━ [1] 测试（$( [ "$MODE" = "full" ] && echo "完整版 77~78项" || echo "lite精简版 ${LITE_ITEMS}项" )/DNS, 并发${MAXC}） ━━━"
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/dns-test-compare.XXXXXX")
TMPDIR_LIST+=("$TMPD")

IDX_MAP=()
for i in "${!DNS_ARGS[@]}"; do
  if [ -z "${DELAY_VAL[$i]}" ]; then
    SCORE_VAL[$i]="不可达"; STAB_VAL[$i]="-"
    echo "     ⏭️  ${DNS_ARGS[$i]} 不可达，跳过测试"
    continue
  fi
  echo "     ⏳ ${DNS_ARGS[$i]} 测试中..."
  IDX_MAP+=("$i")
done

pids=(); n=0
for i in "${IDX_MAP[@]}"; do
  bash "${MODE}.sh" "${DNS_ARGS[$i]}" 0 > "$TMPD/$n.out" 2>&1 &
  pids+=($!)
  n=$((n+1))
  if [ $((n % MAXC)) -eq 0 ]; then
    for p in "${pids[@]}"; do wait "$p" 2>/dev/null; done
    pids=()
  fi
done
for p in "${pids[@]}"; do wait "$p" 2>/dev/null; done

n=0
for i in "${IDX_MAP[@]}"; do
  out=$(cat "$TMPD/$n.out")
  SCORE_VAL[$i]=$(echo "$out" | grep -oE "综合评分: [0-9]+" | grep -oE "[0-9]+")
  STAB_VAL[$i]=$(echo "$out" | grep -oE "稳定性: [0-9]+%" | grep -oE "[0-9]+")
  [ -z "${SCORE_VAL[$i]}" ] && SCORE_VAL[$i]="不可达"
  [ -z "${STAB_VAL[$i]}" ] && STAB_VAL[$i]="-"
  # 百分号只在有数值时拼接（防 "不可达%" / "稳定性-%" 的破相显示）
  _sv="${SCORE_VAL[$i]}"; [ "$_sv" != "不可达" ] && _sv="${_sv}%"
  _tv="${STAB_VAL[$i]}";  [ "$_tv" != "-" ] && _tv="${_tv}%"
  printf "     ✅ %-42s 评分%s 稳定性%s\n" "${DNS_ARGS[$i]}" "$_sv" "$_tv"
  n=$((n+1))
done

T1=$(date +%s)
COST=$((T1 - T0))

# ============================================================================
# 3) 文本对比结果 + 推荐
# ============================================================================
echo ""
echo "════ 对比结果（总耗时 ${COST}s） ════"
printf "  %-3s %-42s %-9s %-10s %-8s\n" "#" "DNS" "评分" "延迟ms" "稳定性"
rank=0
for i in "${!DNS_ARGS[@]}"; do
  rank=$((rank+1))
  sv="${SCORE_VAL[$i]}"; [ "$sv" != "不可达" ] && sv="${sv}%"
  tv="${STAB_VAL[$i]}"; [ "$tv" != "-" ] && tv="${tv}%"
  printf "  %-3d %-42s %-9s %-10s %-8s\n" "$rank" "${DNS_ARGS[$i]}" "$sv" "${DELAY_VAL[$i]:-—}" "$tv"
done

BEST=""; BEST_IDX=-1; BEST_SCORE=-1; BEST_DELAY=99999
for i in "${!DNS_ARGS[@]}"; do
  [ "${SCORE_VAL[$i]}" = "不可达" ] && continue
  s="${SCORE_VAL[$i]}"; [ -z "$s" ] && continue
  dl="${DELAY_VAL[$i]:-99999}"
  if [ "$s" -gt "$BEST_SCORE" ] || { [ "$s" -eq "$BEST_SCORE" ] && [ "$dl" -lt "$BEST_DELAY" ]; }; then
    BEST="${DNS_ARGS[$i]}"; BEST_IDX=$i; BEST_SCORE=$s; BEST_DELAY=$dl
  fi
done
if [ "$BEST_IDX" -ge 0 ]; then
  echo ""
  _best_note=""
  is_current_dns "$BEST" && _best_note=" — 👤 当前正在使用，无需切换"
  echo "  🏆 综合推荐: $BEST （评分${BEST_SCORE}% 延迟${BEST_DELAY}ms）${_best_note}"
else
  echo ""
  echo "  💀 全部DNS不可达"
fi

# ---------- 排名序列（HTML/MD 报告共享）：评分降序 + 延迟升序，不可达沉底 ----------
# 排序键: 可达(1/0)|评分%03d|延迟%05d|原始下标 —— 平行文本排序，兼容 bash 3.2
RANK_LINES=""
for i in "${!DNS_ARGS[@]}"; do
  s="${SCORE_VAL[$i]}"; dl="${DELAY_VAL[$i]:-0}"
  if [ "$s" = "不可达" ]; then
    RANK_LINES="${RANK_LINES}0|000|99999|$i
"
  else
    RANK_LINES="${RANK_LINES}1|$(printf '%03d' "$s")|$(printf '%05d' "$dl")|$i
"
  fi
done
RANKED_IDX=()
while IFS='|' read -r _rk _sk _dk oi; do
  [ -z "$oi" ] && continue
  RANKED_IDX+=("$oi")
done <<EOF
$(printf '%s' "$RANK_LINES" | sort -t'|' -k1,1r -k2,2r -k3,3n)
EOF

# ---------- 切换建议：按当前系统给出可直接复制的命令（只提示，不代执行） ----------
SWITCH_OS=""; SWITCH_LINES=()
if [ "$BEST_IDX" -ge 0 ]; then
  osn=$(uname -s)
  if [ "$osn" = "Darwin" ]; then
    SWITCH_OS="macOS"
    SWITCH_LINES+=("sudo networksetup -setdnsservers Wi-Fi ${BEST}")
    SWITCH_LINES+=("# 其他网络服务名: networksetup -listallnetworkservices 查看，替换 Wi-Fi")
    SWITCH_LINES+=("# 恢复自动获取: sudo networksetup -setdnsservers Wi-Fi \"Empty\"")
  elif [ -r /proc/version ] && grep -qi microsoft /proc/version; then
    SWITCH_OS="WSL"
    SWITCH_LINES+=("sudo sh -c 'echo nameserver ${BEST} > /etc/resolv.conf'")
    SWITCH_LINES+=("# WSL 自动重生成时: /etc/wsl.conf 加 [network] generateResolvConf=false 后 wsl --shutdown 重启")
  elif command -v nmcli >/dev/null 2>&1; then
    SWITCH_OS="Linux (NetworkManager)"
    SWITCH_LINES+=("nmcli con mod \"<连接名>\" ipv4.dns \"${BEST}\" && nmcli con up \"<连接名>\"")
    SWITCH_LINES+=("# 连接名查看: nmcli -g NAME,DEVICE con show --active")
  elif command -v resolvectl >/dev/null 2>&1; then
    SWITCH_OS="Linux (systemd-resolved)"
    SWITCH_LINES+=("sudo resolvectl dns <网卡名> ${BEST}")
    SWITCH_LINES+=("# 网卡名查看: ip link")
  else
    SWITCH_OS="${osn}"
    SWITCH_LINES+=("sudo sh -c 'echo nameserver ${BEST} > /etc/resolv.conf'")
  fi
  echo ""
  echo "  🔧 切换到推荐 DNS（${SWITCH_OS}，复制执行）:"
  for sl in "${SWITCH_LINES[@]}"; do
    echo "      $sl"
  done
fi

# ============================================================================
# 4) 结构化JSON结果（默认保存，供趋势积累）
# ============================================================================
# JSON 字符串编码：优先 python3（macOS/Linux 自带），无则 sed 转义回退（审阅#15，零新增硬依赖）
json_enc() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys,json; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$1"
  else
    printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  fi
}
TS=$(date '+%Y%m%d-%H%M%S')
if [ "$SAVE_JSON" = "1" ]; then
  mkdir -p results
  JF="results/compare-${TS}.json"
  {
    echo "{"
    echo "  \"tool\": \"dns-test/compare.sh\","
    echo "  \"version\": \"${VERSION}\","
    echo "  \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S %z')\","
    echo "  \"mode\": \"${MODE}\","
    echo "  \"cost_s\": ${COST},"
    echo "  \"dns\": ["
    i=0
    for d in "${DNS_ARGS[@]}"; do
      esc_d=$(json_enc "$d")
      [ "${SCORE_VAL[$i]}" = "不可达" ] && reachable=false || reachable=true
      comma=""; [ $i -lt $(( ${#DNS_ARGS[@]} - 1 )) ] && comma=","
      echo "    {\"addr\": ${esc_d}, \"score\": \"${SCORE_VAL[$i]}\", \"stab\": \"${STAB_VAL[$i]}\", \"delay_ms\": ${DELAY_VAL[$i]:-0}, \"reachable\": ${reachable}}${comma}"
      i=$((i+1))
    done
    echo "  ]"
    echo "}"
  } > "$JF"
  echo ""
  echo "  💾 JSON结果已保存: $JF"
fi

# ============================================================================
# 4.5) 环比上次：读取上一份 compare-*.json（排除本轮刚保存的），逐 DNS 算 Δ
#      平行数组 PREV_S/PREV_D/DELTA_S/DELTA_D 对应 DNS_ARGS（空=上次无该DNS或不可达）
# ============================================================================
PREV_TS=""; ANY_DELTA=0
PREV_S=(); PREV_D=(); DELTA_S=(); DELTA_D=()
if [ "$SAVE_JSON" = "1" ] && [ -n "${JF:-}" ]; then
  # glob 字典序迭代，最后一个（排除本轮）即最近一次采集
  PREV_F=""
  for pf in results/compare-*.json; do
    [ -e "$pf" ] || continue
    [ "$pf" = "$JF" ] && continue
    PREV_F="$pf"
  done
  if [ -n "$PREV_F" ]; then
    PREV_TS=$(sed -n 's/.*"timestamp": *"\([^"]*\)".*/\1/p' "$PREV_F" | head -1)
    for i in "${!DNS_ARGS[@]}"; do
      PREV_S[$i]=""; PREV_D[$i]=""; DELTA_S[$i]=""; DELTA_D[$i]=""
      cur_s="${SCORE_VAL[$i]}"; cur_d="${DELAY_VAL[$i]}"
      [ "$cur_s" = "不可达" ] && continue
      [ -z "$cur_d" ] && continue
      # DNS 地址仅含 hex/点/冒号，可安全内嵌 ERE；按行取该 DNS 上次记录
      pline=$(grep -oE "\"addr\": *\"${DNS_ARGS[$i]}\", *\"score\": *\"[^\"]*\", *\"stab\": *\"[^\"]*\", *\"delay_ms\": *[0-9]+" "$PREV_F" | head -1)
      [ -z "$pline" ] && continue
      p_s=$(printf '%s' "$pline" | sed -n 's/.*"score": *"\([^"]*\)".*/\1/p')
      p_d=$(printf '%s' "$pline" | sed -n 's/.*"delay_ms": *\([0-9]*\).*/\1/p')
      [ -z "$p_s" ] || [ -z "$p_d" ] || [ "$p_s" = "不可达" ] && continue
      PREV_S[$i]="$p_s"; PREV_D[$i]="$p_d"
      DELTA_S[$i]=$((cur_s - p_s)); DELTA_D[$i]=$((cur_d - p_d))
      ANY_DELTA=1
    done
  fi
fi
if [ "$ANY_DELTA" = "1" ]; then
  echo ""
  echo "  📈 环比上次采集（${PREV_TS}）:"
  for i in "${!DNS_ARGS[@]}"; do
    [ -z "${PREV_S[$i]}" ] && continue
    printf "       %-42s 评分 %s→%s (%+d)  延迟 %s→%sms (%+d)\n" \
      "${DNS_ARGS[$i]}" "${PREV_S[$i]}" "${SCORE_VAL[$i]}" "${DELTA_S[$i]}" \
      "${PREV_D[$i]}" "${DELAY_VAL[$i]}" "${DELTA_D[$i]}"
  done
fi

# ============================================================================
# 5) HTML 报告（--html）— 零JS/零外部依赖；CSS 变量双主题（自动跟随系统暗色）
# ============================================================================
if [ "$GEN_HTML" = "1" ]; then
  mkdir -p results
  HF="results/report.html"
  {
    echo "<!DOCTYPE html>"
    echo "<html lang='zh'>"
    echo "<head>"
    echo "<meta charset='utf-8'>"
    echo "<meta name='viewport' content='width=device-width,initial-scale=1'>"
    echo "<meta name='color-scheme' content='light dark'>"
    echo "<title>DNS对比报告</title>"
    echo "<style>"
    echo ":root{--bg:#f5f7fa;--card:#fff;--tx:#333;--sub:#888;--th-bg:#fafbfc;--th-tx:#666;--line:#eee;--track:#e5e7eb;--green:#22c55e;--amber:#f59e0b;--red:#ef4444;--gtx:#16a34a;--atx:#d97706;--rtx:#dc2626;--rec-bg:#f0fdf4;--rec-bd:#bbf7d0;--rec-tx:#166534;--best:#f0fdf4;--mono:ui-monospace,SFMono-Regular,Menlo,Consolas,'Courier New',monospace}"
    echo "@media(prefers-color-scheme:dark){:root{--bg:#0f172a;--card:#1e293b;--tx:#e2e8f0;--sub:#94a3b8;--th-bg:#283548;--th-tx:#94a3b8;--line:#334155;--track:#334155;--gtx:#4ade80;--atx:#fbbf24;--rtx:#f87171;--rec-bg:#052e16;--rec-bd:#14532d;--rec-tx:#86efac;--best:#052e16}}"
    echo "body{font-family:-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;margin:0;background:var(--bg);color:var(--tx)}"
    echo ".wrap{max-width:860px;margin:24px auto;padding:0 16px}"
    echo ".card{background:var(--card);border-radius:12px;padding:20px 24px;margin:16px 0;box-shadow:0 2px 8px rgba(0,0,0,.06)}"
    echo "h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:0 0 14px;color:var(--sub)}"
    echo ".meta{color:var(--sub);font-size:13px;margin:6px 0 14px}"
    echo ".tbl-wrap{overflow-x:auto;-webkit-overflow-scrolling:touch}"
    echo "table{width:100%;border-collapse:collapse;font-size:14px}"
    echo "th,td{padding:10px 8px;text-align:left;border-bottom:1px solid var(--line);white-space:nowrap}"
    echo "th{background:var(--th-bg);color:var(--th-tx);font-weight:600}"
    echo "tbody tr:nth-child(even){background:rgba(127,127,127,.04)}"
    echo "td.addr{font-family:var(--mono);font-size:13px}"
    echo "tr.best td{background:var(--best)}"
    echo ".rank{font-family:var(--mono);color:var(--sub)}"
    echo ".bdg{display:inline-block;min-width:44px;text-align:center;padding:2px 10px;border-radius:999px;font-size:12px;font-weight:600;font-family:var(--mono)}"
    echo ".bg-g{background:rgba(34,197,94,.14);color:var(--gtx)}.bg-a{background:rgba(245,158,11,.16);color:var(--atx)}.bg-r{background:rgba(239,68,68,.14);color:var(--rtx)}.bg-n{background:rgba(127,127,127,.12);color:var(--sub)}"
    echo ".row{display:flex;align-items:center;gap:10px;margin:9px 0}"
    echo ".lbl{width:180px;flex:none;font-size:13px;font-family:var(--mono);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}"
    echo ".track{flex:1;min-width:60px;height:14px;background:var(--track);border-radius:7px;overflow:hidden}"
    echo ".fill{height:100%;border-radius:7px;min-width:2px}"
    echo ".f-green{background:var(--green)}.f-amber{background:var(--amber)}.f-red{background:var(--red)}"
    echo ".val{flex:none;width:70px;font-size:13px;font-family:var(--mono)}"
    echo ".rec{background:var(--rec-bg);border:1px solid var(--rec-bd);color:var(--rec-tx);padding:12px 16px;border-radius:10px;font-size:15px}"
    echo "pre.cmd{background:var(--th-bg);border:1px solid var(--line);padding:10px 14px;border-radius:8px;overflow-x:auto;font-family:var(--mono);font-size:13px;line-height:1.7;margin:8px 0 4px}"
    echo ".rec.bad-rec{--rec-bg:#fef2f2;--rec-bd:#fecaca;--rec-tx:#991b1b}"
    echo "@media(prefers-color-scheme:dark){.rec.bad-rec{--rec-bg:#450a0a;--rec-bd:#7f1d1d;--rec-tx:#fca5a5}}"
    echo "@media(max-width:600px){.wrap{padding:0 8px}.card{padding:14px}table{font-size:12px}th,td{padding:8px 6px}.lbl{width:120px}.val{width:56px}}"
    echo "@media print{body{background:#fff}.card{box-shadow:none;border:1px solid #ddd;break-inside:avoid}}"
    echo "</style>"
    echo "</head><body>"
    echo "<div class='wrap'>"
    echo "<div class='card'><h1>🌐 DNS 对比报告</h1>"
    echo "<div class='meta'>$(date '+%Y-%m-%d %H:%M:%S') ｜ $( [ "$MODE" = "full" ] && echo "完整版" || echo "lite精简版" ) ${LITE_ITEMS:+${LITE_ITEMS}项}/DNS ｜ dns-test ${VERSION} ｜ 耗时${COST}s</div>"
    if [ "$BEST_IDX" -ge 0 ]; then
      _rec_note=""; is_current_dns "$BEST" && _rec_note=" ｜ 👤 当前正在使用"
      echo "<div class='rec'>🏆 综合推荐: <b>$BEST</b> — 评分${BEST_SCORE}% ｜ 延迟${BEST_DELAY}ms${_rec_note}</div>"
    else
      echo "<div class='rec bad-rec'>💀 全部DNS不可达，请检查网络/加速器状态后重试</div>"
    fi
    echo "</div>"
    # 汇总表：消费共享排名序列 RANKED_IDX（评分降序 + 延迟升序，不可达沉底，见 4.5 前计算）
    echo "<div class='card'><h2>排名（按评分，同分比延迟）$( [ "$ANY_DELTA" = "1" ] && echo " ｜ 环比: ${PREV_TS}" )</h2>"
    if [ "$ANY_DELTA" = "1" ]; then
      echo "<div class='tbl-wrap'><table><thead><tr><th>#</th><th>DNS</th><th>评分</th><th>Δ评分</th><th>延迟(ms)</th><th>Δ延迟</th><th>稳定性</th><th>状态</th></tr></thead><tbody>"
    else
      echo "<div class='tbl-wrap'><table><thead><tr><th>#</th><th>DNS</th><th>评分</th><th>延迟(ms)</th><th>稳定性</th><th>状态</th></tr></thead><tbody>"
    fi
    rank=0
    for oi in "${RANKED_IDX[@]}"; do
      rank=$((rank+1))
      sv="${SCORE_VAL[$oi]}"; tv="${STAB_VAL[$oi]}"; dl="${DELAY_VAL[$oi]:-—}"
      bcls="bg-n"; [ "$sv" != "不可达" ] && bcls="bg-g"
      if [ "$sv" != "不可达" ]; then
        [ "$sv" -lt 80 ] && bcls="bg-a"
        [ "$sv" -lt 60 ] && bcls="bg-r"
        sv="$sv%"
      fi
      if [ "$tv" != "-" ]; then
        tcls="bg-g"; [ "$tv" -lt 80 ] && tcls="bg-a"; [ "$tv" -lt 50 ] && tcls="bg-r"
        tvs="$tv%"
      else
        tcls="bg-n"; tvs="-"
      fi
      if [ "$dl" != "—" ]; then
        dcls="bg-g"; [ "$dl" -ge 100 ] && dcls="bg-a"; [ "$dl" -ge 300 ] && dcls="bg-r"
        dvs="${dl}ms"
      else
        dcls="bg-n"; dvs="—"
      fi
      if [ "${SCORE_VAL[$oi]}" = "不可达" ]; then
        st="<span class='bdg bg-r'>不可达</span>"
      else
        st="<span class='bdg bg-g'>可达</span>"
      fi
      case "$rank" in
        1) mk="🥇";; 2) mk="🥈";; 3) mk="🥉";; *) mk="$rank";;
      esac
      # 不可达的 DNS 不授奖牌（全部故障时给金牌属视觉误导），降级为纯序号
      [ "${SCORE_VAL[$oi]}" = "不可达" ] && mk="$rank"
      rowcls=""; [ "$oi" = "$BEST_IDX" ] && rowcls=" class='best'"
      # 环比单元格（仅有上次数据时渲染 Δ 列）：评分升=绿/降=红，延迟降=绿/升=红，0=中性
      if [ "$ANY_DELTA" = "1" ]; then
        ds="${DELTA_S[$oi]:-}"; dd="${DELTA_D[$oi]:-}"
        if [ -n "$ds" ]; then
          dsc="bg-n"; [ "$ds" -gt 0 ] && dsc="bg-g"; [ "$ds" -lt 0 ] && dsc="bg-r"
          ds_cell="<td><span class='bdg $dsc'>$(printf '%+d' "$ds")</span></td>"
        else
          ds_cell="<td><span class='bdg bg-n'>—</span></td>"
        fi
        if [ -n "$dd" ]; then
          ddc="bg-n"; [ "$dd" -lt 0 ] && ddc="bg-g"; [ "$dd" -gt 0 ] && ddc="bg-r"
          dd_cell="<td><span class='bdg $ddc'>$(printf '%+d' "$dd")ms</span></td>"
        else
          dd_cell="<td><span class='bdg bg-n'>—</span></td>"
        fi
      else
        ds_cell=""; dd_cell=""
      fi
      # 当前系统 DNS 徽章（命中才渲染，不破坏 addr 列等宽字体排版）
      cur_b=""; is_current_dns "${DNS_ARGS[$oi]}" && cur_b=" <span class='bdg bg-n'>👤当前</span>"
      echo "<tr${rowcls}><td class='rank'>$mk</td><td class='addr'>${DNS_ARGS[$oi]}${cur_b}</td><td><span class='bdg $bcls'>$sv</span></td>${ds_cell}<td><span class='bdg $dcls'>$dvs</span></td>${dd_cell}<td><span class='bdg $tcls'>$tvs</span></td><td>$st</td></tr>"
    done
    echo "</tbody></table></div></div>"
    # 切换命令卡片（终端已打印同款；HTML 内 < > 转义防当标签解析）
    if [ "$BEST_IDX" -ge 0 ]; then
      echo "<div class='card'><h2>如何切换到推荐 DNS（${SWITCH_OS}）</h2>"
      echo "<pre class='cmd'>"
      for sl in "${SWITCH_LINES[@]}"; do
        printf '%s\n' "$sl" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
      done
      echo "</pre>"
      echo "<div class='meta'>命令仅供参考，请确认网络服务名/连接名后再执行；sudo 需输入密码</div>"
      echo "</div>"
    fi
    # 评分条形图（track/fill 自适应布局，小屏不溢出换行）
    echo "<div class='card'><h2>综合评分</h2>"
    for i in "${!DNS_ARGS[@]}"; do
      s="${SCORE_VAL[$i]}"; [ "$s" = "不可达" ] && s=0
      color="f-green"; [ "$s" -lt 80 ] && color="f-amber"; [ "$s" -lt 60 ] && color="f-red"
      sv="${SCORE_VAL[$i]}"; [ "$sv" != "不可达" ] && sv="${sv}%"
      echo "<div class='row'>"
      echo "<span class='lbl' title='${DNS_ARGS[$i]}'>${DNS_ARGS[$i]}</span>"
      echo "<div class='track'><div class='fill ${color}' style='width:${s}%'></div></div>"
      echo "<span class='val'>$sv</span>"
      echo "</div>"
    done
    echo "</div>"
    # 延迟条形图（越低越好，宽度按最大延迟归一）
    echo "<div class='card'><h2>延迟 (ms) — 越低越好</h2>"
    maxd=1
    for i in "${!DNS_ARGS[@]}"; do
      dl="${DELAY_VAL[$i]:-0}"
      [ "$dl" -gt "$maxd" ] 2>/dev/null && maxd="$dl"
    done
    for i in "${!DNS_ARGS[@]}"; do
      dl="${DELAY_VAL[$i]:-0}"
      w=0; [ "$maxd" -gt 0 ] && w=$(( dl * 100 / maxd ))
      color="f-green"
      [ "$dl" -ge 100 ] && color="f-amber"
      [ "$dl" -ge 300 ] && color="f-red"
      [ "${SCORE_VAL[$i]}" = "不可达" ] && color="f-red"
      echo "<div class='row'>"
      echo "<span class='lbl' title='${DNS_ARGS[$i]}'>${DNS_ARGS[$i]}</span>"
      echo "<div class='track'><div class='fill ${color}' style='width:${w}%'></div></div>"
      echo "<span class='val'>${DELAY_VAL[$i]:-—}ms</span>"
      echo "</div>"
    done
    echo "<div class='meta'>颜色: 绿&lt;100ms ｜ 黄100~300ms ｜ 红≥300ms或不可达</div>"
    echo "</div>"
    echo "</div>"
    echo "</body></html>"
  } > "$HF"
  echo ""
  echo "  📄 HTML报告已生成: $HF"
fi

# ============================================================================
# 6) Markdown 报告（--md）— GitHub/PR/Issue 友好，可直接粘贴存档
# ============================================================================
if [ "$GEN_MD" = "1" ]; then
  mkdir -p results
  MF="results/report.md"
  {
    echo "# DNS 对比报告"
    echo ""
    echo "> $(date '+%Y-%m-%d %H:%M:%S') ｜ $( [ "$MODE" = "full" ] && echo "完整版" || echo "lite精简版" ) ${LITE_ITEMS:+${LITE_ITEMS}项}/DNS ｜ dns-test ${VERSION} ｜ 耗时${COST}s"
    echo ""
    if [ "$BEST_IDX" -ge 0 ]; then
      _md_note=""; is_current_dns "$BEST" && _md_note=" ｜ 👤 当前正在使用"
      echo "**🏆 综合推荐: \`${BEST}\`** — 评分${BEST_SCORE}% ｜ 延迟${BEST_DELAY}ms${_md_note}"
    else
      echo "**💀 全部DNS不可达，请检查网络/加速器状态后重试**"
    fi
    echo ""
    if [ "$ANY_DELTA" = "1" ]; then
      echo "排名（按评分，同分比延迟；环比基准: ${PREV_TS}）："
      echo ""
      echo "| # | DNS | 评分 | Δ评分 | 延迟 | Δ延迟 | 稳定性 | 状态 |"
      echo "|---|-----|------|-------|------|-------|--------|------|"
    else
      echo "排名（按评分，同分比延迟）："
      echo ""
      echo "| # | DNS | 评分 | 延迟 | 稳定性 | 状态 |"
      echo "|---|-----|------|------|--------|------|"
    fi
    rank=0
    for oi in "${RANKED_IDX[@]}"; do
      rank=$((rank+1))
      sv="${SCORE_VAL[$oi]}"; tv="${STAB_VAL[$oi]}"
      if [ "$sv" = "不可达" ]; then
        mk="$rank"; sv="不可达"; dvs="—"; st="❌ 不可达"
      else
        case "$rank" in 1) mk="🥇";; 2) mk="🥈";; 3) mk="🥉";; *) mk="$rank";; esac
        sv="${sv}%"; dvs="${DELAY_VAL[$oi]}ms"; st="✅ 可达"
      fi
      [ "$tv" != "-" ] && tv="${tv}%" || tv="—"
      cur_md=""; is_current_dns "${DNS_ARGS[$oi]}" && cur_md=" 👤"
      if [ "$ANY_DELTA" = "1" ]; then
        ds="${DELTA_S[$oi]:-}"; dd="${DELTA_D[$oi]:-}"
        ds="$( [ -n "$ds" ] && printf '%+d' "$ds" || echo —)"
        if [ -n "$dd" ]; then
          dd="$(printf '%+d' "$dd")ms"
        else
          dd="—"
        fi
        echo "| ${mk} | \`${DNS_ARGS[$oi]}\`${cur_md} | ${sv} | ${ds} | ${dvs} | ${dd} | ${tv} | ${st} |"
      else
        echo "| ${mk} | \`${DNS_ARGS[$oi]}\`${cur_md} | ${sv} | ${dvs} | ${tv} | ${st} |"
      fi
    done
    echo ""
    if [ "$BEST_IDX" -ge 0 ]; then
      echo "## 如何切换到推荐 DNS（${SWITCH_OS}）"
      echo ""
      echo '```bash'
      for sl in "${SWITCH_LINES[@]}"; do
        echo "$sl"
      done
      echo '```'
      echo ""
    fi
    echo "---"
    echo "<sub>由 dns-test ${VERSION} 生成；趋势: \`bash trends.sh --html\`；定时采集: \`bash compare.sh DNS1 DNS2 --watch 30\`</sub>"
  } > "$MF"
  echo ""
  echo "  📝 Markdown报告已生成: $MF"
fi

# ---------- 退出码 ----------
echo ""
echo "  💡 想看历史趋势？ → bash trends.sh --html   （数据已自动积累，评分/延迟随时间变化一目了然）"
REACH=0
for i in "${!DNS_ARGS[@]}"; do
  [ "${SCORE_VAL[$i]}" != "不可达" ] && REACH=1
done
[ "$REACH" = "0" ] && exit 2
exit 0
