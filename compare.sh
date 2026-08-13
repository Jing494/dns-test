#!/bin/bash
# ============================================================================
# 多DNS对比模式（v3：并行 + 延迟中位数 + 结构化JSON + HTML报告）
# 兼容性: bash 3.2+（无关联数组依赖，macOS 默认 bash 可直接运行）
# 用法: bash compare.sh DNS1 [DNS2] ... [--html] [--no-save]
#   例: bash compare.sh 223.5.5.5 119.29.29.29 222.172.200.68
#       bash compare.sh 223.5.5.5 119.29.29.29 --html   # 生成 results/report.html
#       bash compare.sh 223.5.5.5 --no-save             # 不保存JSON结果
# 环境变量:
#   COMPARE_MAX_CONCURRENCY  lite测试并行数上限（默认3；设1为串行，结果最稳）
# 输出:
#   文本对比表格；--html 生成 results/report.html（响应式，手机可看）；
#   JSON结果默认保存 results/compare-<时间戳>.json（供历史趋势积累）
# 退出码: 0=完成  1=参数错误  2=全部DNS不可达
# ============================================================================
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 1
cd "$SCRIPT_DIR" || exit 1
source lib/core.sh

VERSION="v2026.08.7"
GEN_HTML=0
SAVE_JSON=1
MODE="lite"    # lite(默认) / full
# lite默认计分点（无IPv6环境=63；IPv6可用时7b项参与计分=64，环境相关）
LITE_ITEMS="63"

# ---------- 参数解析 ----------
DNS_ARGS=()
for a in "$@"; do
  case "$a" in
    --html)     GEN_HTML=1 ;;
    --full)     MODE="full" ;;
    --no-save)  SAVE_JSON=0 ;;
    --help|-h)
      echo "用法: bash compare.sh DNS1 [DNS2] ... [--html] [--full] [--no-save]"
      echo "  例: bash compare.sh 223.5.5.5 119.29.29.29 222.172.200.68"
      echo "      bash compare.sh 223.5.5.5 119.29.29.29 --html"
      echo "      bash compare.sh 223.5.5.5 119.29.29.29 --full   # 用完整版测试(77~78项/DNS)"
      echo "环境变量: COMPARE_MAX_CONCURRENCY=3  (并行数,1=串行最稳)"
      exit 0 ;;
    *) DNS_ARGS+=("$a") ;;
  esac
done

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
  echo "用法: bash compare.sh DNS1 [DNS2] ... [--html] [--no-save]"
  exit 1
fi

print_header "多DNS对比测试 (v3) — $( [ "$MODE" = "full" ] && echo "完整版 77~78项/DNS" || echo "lite精简版 ${LITE_ITEMS}项/DNS" )"
echo "  对比DNS: ${DNS_ARGS[*]}"
echo "  测试并发: ${COMPARE_MAX_CONCURRENCY:-3}（设1为串行最稳）"
T0=$(date +%s)

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
    PARR_CMDS+=("dig @${d} www.baidu.com A +time=2 +tries=1 2>/dev/null | sed -n 's/.*Query time: \\([0-9]*\\) msec.*/\\1/p'")
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
rm -rf "$PARR_TMPDIR"

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
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT INT TERM

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
  printf "     ✅ %-42s 评分%s 稳定性%s%%\n" "${DNS_ARGS[$i]}" "${SCORE_VAL[$i]}%" "${STAB_VAL[$i]}"
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
  echo "  🏆 综合推荐: $BEST （评分${BEST_SCORE}% 延迟${BEST_DELAY}ms）"
else
  echo ""
  echo "  💀 全部DNS不可达"
fi

# ============================================================================
# 4) 结构化JSON结果（默认保存，供趋势积累）
# ============================================================================
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
      esc_d=$(printf '%s' "$d" | sed 's/\\/\\\\/g; s/"/\\"/g')
      [ "${SCORE_VAL[$i]}" = "不可达" ] && reachable=false || reachable=true
      comma=""; [ $i -lt $(( ${#DNS_ARGS[@]} - 1 )) ] && comma=","
      echo "    {\"addr\": \"${esc_d}\", \"score\": \"${SCORE_VAL[$i]}\", \"stab\": \"${STAB_VAL[$i]}\", \"delay_ms\": ${DELAY_VAL[$i]:-0}, \"reachable\": ${reachable}}${comma}"
      i=$((i+1))
    done
    echo "  ]"
    echo "}"
  } > "$JF"
  echo ""
  echo "  💾 JSON结果已保存: $JF"
fi

# ============================================================================
# 5) HTML 报告（--html）
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
    echo "<title>DNS对比报告</title>"
    echo "<style>"
    echo "body{font-family:-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;margin:0;background:#f5f7fa;color:#333}"
    echo ".wrap{max-width:860px;margin:24px auto;padding:0 16px}"
    echo ".card{background:#fff;border-radius:12px;padding:20px 24px;margin:16px 0;box-shadow:0 2px 8px rgba(0,0,0,.06)}"
    echo "h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:0 0 14px;color:#555}"
    echo ".meta{color:#888;font-size:13px;margin-bottom:14px}"
    echo "table{width:100%;border-collapse:collapse;font-size:14px}"
    echo "th,td{padding:10px 8px;text-align:left;border-bottom:1px solid #eee}"
    echo "th{background:#fafbfc;color:#666;font-weight:600}"
    echo ".bar{height:14px;border-radius:7px;min-width:2px;background:#e5e7eb}"
    echo ".b-green{background:#22c55e}.b-amber{background:#f59e0b}.b-red{background:#ef4444}"
    echo ".rec{background:#f0fdf4;border:1px solid #bbf7d0;color:#166534;padding:12px 16px;border-radius:10px;font-size:15px}"
    echo ".bad{color:#dc2626}.ok{color:#16a34a}"
    echo "@media(max-width:600px){.wrap{padding:0 8px}.card{padding:14px}table{font-size:12px}th,td{padding:8px 4px}}"
    echo "</style>"
    echo "</head><body>"
    echo "<div class='wrap'>"
    echo "<div class='card'><h1>🌐 DNS 对比报告</h1>"
    echo "<div class='meta'>$(date '+%Y-%m-%d %H:%M:%S') ｜ $( [ "$MODE" = "full" ] && echo "完整版" || echo "lite精简版" ) ${LITE_ITEMS:+${LITE_ITEMS}项}/DNS ｜ dns-test ${VERSION} ｜ 耗时${COST}s</div>"
    if [ "$BEST_IDX" -ge 0 ]; then
      echo "<div class='rec'>🏆 综合推荐: <b>$BEST</b> — 评分${BEST_SCORE}% ｜ 延迟${BEST_DELAY}ms</div>"
    else
      echo "<div class='rec' style='background:#fef2f2;border-color:#fecaca;color:#991b1b'>💀 全部DNS不可达，请检查网络/加速器状态后重试</div>"
    fi
    echo "</div>"
    # 汇总表
    echo "<div class='card'><h2>对比明细</h2>"
    echo "<table><tr><th>DNS</th><th>评分</th><th>延迟(ms)</th><th>稳定性</th><th>状态</th></tr>"
    for i in "${!DNS_ARGS[@]}"; do
      sv="${SCORE_VAL[$i]}"; [ "$sv" != "不可达" ] && sv="${sv}%"
      tv="${STAB_VAL[$i]}"; [ "$tv" != "-" ] && tv="${tv}%"
      if [ "${SCORE_VAL[$i]}" = "不可达" ]; then
        st="<span class='bad'>不可达</span>"
      else
        st="<span class='ok'>可达</span>"
      fi
      echo "<tr><td>${DNS_ARGS[$i]}</td><td>$sv</td><td>${DELAY_VAL[$i]:-—}</td><td>$tv</td><td>$st</td></tr>"
    done
    echo "</table></div>"
    # 评分柱状
    echo "<div class='card'><h2>综合评分</h2>"
    for i in "${!DNS_ARGS[@]}"; do
      s="${SCORE_VAL[$i]}"; [ "$s" = "不可达" ] && s=0
      color="b-green"; [ "$s" -lt 80 ] && color="b-amber"; [ "$s" -lt 60 ] && color="b-red"
      echo "<div style='display:flex;align-items:center;margin:8px 0;flex-wrap:wrap'>"
      echo "<span style='width:190px;font-size:13px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap'>${DNS_ARGS[$i]}</span>"
      echo "<div class='bar ${color}' style='width:${s}%;max-width:420px'></div>"
      sv="${SCORE_VAL[$i]}"; [ "$sv" != "不可达" ] && sv="${sv}%"
      echo "<span style='margin-left:10px;font-size:13px;min-width:48px'>$sv</span>"
      echo "</div>"
    done
    echo "</div>"
    # 延迟柱状（越低越好）
    echo "<div class='card'><h2>延迟 (ms) — 越低越好</h2>"
    maxd=1
    for i in "${!DNS_ARGS[@]}"; do
      dl="${DELAY_VAL[$i]:-0}"
      [ "$dl" -gt "$maxd" ] 2>/dev/null && maxd="$dl"
    done
    for i in "${!DNS_ARGS[@]}"; do
      dl="${DELAY_VAL[$i]:-0}"
      w=0; [ "$maxd" -gt 0 ] && w=$(( dl * 100 / maxd ))
      color="b-green"
      [ "$dl" -ge 100 ] && color="b-amber"
      [ "$dl" -ge 300 ] && color="b-red"
      [ "${SCORE_VAL[$i]}" = "不可达" ] && color="b-red"
      echo "<div style='display:flex;align-items:center;margin:8px 0;flex-wrap:wrap'>"
      echo "<span style='width:190px;font-size:13px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap'>${DNS_ARGS[$i]}</span>"
      echo "<div class='bar ${color}' style='width:${w}%;max-width:420px'></div>"
      echo "<span style='margin-left:10px;font-size:13px;min-width:48px'>${DELAY_VAL[$i]:-—}ms</span>"
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

# ---------- 退出码 ----------
echo ""
echo "  💡 想看历史趋势？ → bash trends.sh --html   （数据已自动积累，评分/延迟随时间变化一目了然）"
REACH=0
for i in "${!DNS_ARGS[@]}"; do
  [ "${SCORE_VAL[$i]}" != "不可达" ] && REACH=1
done
[ "$REACH" = "0" ] && exit 2
exit 0
