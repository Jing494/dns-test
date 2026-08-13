#!/bin/bash
# ============================================================================
# DNS 趋势洞察：聚合 compare.sh 的历史 JSON 结果，输出趋势总览/CSV/HTML报告
# 兼容性: bash 3.2+（无关联数组依赖，macOS 默认 bash 可直接运行）
# 用法: bash trends.sh [DNS地址...] [--html] [--csv] [--cron] [--detail] [--limit N] [--since YYYY-MM-DD]
#   例: bash trends.sh                              # 全部DNS趋势总览（文本）
#       bash trends.sh 223.5.5.5                    # 只看223.5.5.5
#       bash trends.sh --html --csv                 # 生成 trends/report.html + trends.csv
#       bash trends.sh --cron 223.5.5.5 119.29.29.29  # 先采集(跑compare)再聚合（crontab用）
#       bash trends.sh --detail --limit 5           # 每个DNS列最近5条明细
# 环境变量:
#   TRENDS_DIR              趋势产物目录（默认 trends/）
#   COMPARE_RESULTS_DIR     compare JSON 数据源目录（默认 results/）
# 趋势判断: 线性回归斜率为主 + 首尾对比为辅
#   评分: ↑=变好 ↓=变差；延迟: ↑=变好 ↓=变差（箭头=好坏方向，非数值方向）
# 退出码: 0=完成  1=参数/错误  2=无可用数据
# ============================================================================
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 1
cd "$SCRIPT_DIR" || exit 1
source lib/core.sh

VERSION="v2026.08.6"
SRC_DIR="${COMPARE_RESULTS_DIR:-results}"   # compare JSON 数据源
OUT_DIR="${TRENDS_DIR:-trends}"             # 趋势产物目录
GEN_HTML=0
GEN_CSV=0
CRON_MODE=0
DETAIL=0
LIMIT=""
SINCE=""
FILTER=()

# ---------- 参数解析（while+shift风格，兼容--limit N成对取值） ----------
ARGS=("$@")
i=0
while [ $i -lt ${#ARGS[@]} ]; do
  a="${ARGS[$i]}"
  case "$a" in
    --html)   GEN_HTML=1 ;;
    --csv)    GEN_CSV=1 ;;
    --cron)   CRON_MODE=1 ;;
    --detail) DETAIL=1 ;;
    --limit)  i=$((i+1)); LIMIT="${ARGS[$i]:-}"; [ -z "$LIMIT" ] && { echo "❌ --limit 缺少值"; exit 1; } ;;
    --since)  i=$((i+1)); SINCE="${ARGS[$i]:-}"; [ -z "$SINCE" ] && { echo "❌ --since 缺少值"; exit 1; } ;;
    --help|-h)
      echo "用法: bash trends.sh [DNS地址...] [--html] [--csv] [--cron] [--detail] [--limit N] [--since YYYY-MM-DD]"
      echo "  例: bash trends.sh --html --csv"
      echo "      bash trends.sh --cron 223.5.5.5 119.29.29.29   # 先采集再聚合(crontab用)"
      echo "环境变量: TRENDS_DIR(默认trends/)  COMPARE_RESULTS_DIR(默认results/)"
      exit 0 ;;
    --*)
      echo "❌ 未知参数: $a"; exit 1 ;;
    *)
      if valid_dns_addr "$a"; then FILTER+=("$a")
      else echo "❌ 非法DNS地址: $a"; exit 1; fi ;;
  esac
  i=$((i+1))
done

# ---------- --cron 采集模式：先跑 compare 再聚合 ----------
if [ "$CRON_MODE" = "1" ]; then
  if [ ${#FILTER[@]} -eq 0 ]; then
    echo "❌ --cron 需要至少一个DNS参数（要采集的DNS）"
    echo "  例: bash trends.sh --cron 223.5.5.5 119.29.29.29"
    exit 1
  fi
  mkdir -p "$OUT_DIR"
  echo "⏳ 采集: compare.sh ${FILTER[*]}"
  bash compare.sh "${FILTER[@]}" >> "$OUT_DIR/cron.log" 2>&1
  echo "   采集完成，开始聚合..."
fi

# ---------- 数据扫描 ----------
mkdir -p "$SRC_DIR" "$OUT_DIR"
FILES=$(ls "$SRC_DIR"/compare-*.json 2>/dev/null | sort)
if [ -z "$FILES" ]; then
  echo "❌ 无数据: $SRC_DIR/compare-*.json 不存在"
  echo "  请先运行 compare.sh 至少一次，例如: bash compare.sh 223.5.5.5 119.29.29.29"
  exit 2
fi

# ============================================================================
# 解析: 拉平为 时间|addr|score|stab|delay 行
# 平行数组（兼容bash 3.2）:
#   RAW_ADDR[i] = DNS地址（出现顺序）
#   RAW_VAL[i]  = 该地址的多行数据（每行 ts|score|stab|delay，不可达行尾标UNREACH）
# ============================================================================
RAW_ADDR=()
RAW_VAL=()

# 查找 addr 在 RAW_ADDR 的下标（-1=不存在）
raw_idx() {
  local d="$1" k=0
  for a in "${RAW_ADDR[@]}"; do
    [ "$a" = "$d" ] && { echo "$k"; return 0; }
    k=$((k+1))
  done
  echo "-1"
}

rec_total=0
for f in $FILES; do
  ts=$(grep -oE '"timestamp": ?"[^"]+"' "$f" | head -1 | sed 's/"timestamp": *"//;s/"$//')
  [ -z "$ts" ] && continue
  if [ -n "$SINCE" ] && [[ "$ts" < "$SINCE" ]]; then continue; fi
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    addr=$(echo "$line" | sed -n 's/.*"addr": *"\([^"]*\)".*/\1/p')
    [ -z "$addr" ] && continue
    score=$(echo "$line" | sed -n 's/.*"score": *"\([^"]*\)".*/\1/p')
    stab=$(echo "$line" | sed -n 's/.*"stab": *"\([^"]*\)".*/\1/p')
    delay=$(echo "$line" | sed -n 's/.*"delay_ms": *\([0-9]*\).*/\1/p')
    if [ ${#FILTER[@]} -gt 0 ]; then
      in=0
      for fd in "${FILTER[@]}"; do [ "$fd" = "$addr" ] && in=1; done
      [ "$in" = "0" ] && continue
    fi
    ix=$(raw_idx "$addr")
    if [ "$ix" = "-1" ]; then
      RAW_ADDR+=("$addr"); RAW_VAL+=("")
      ix=$(( ${#RAW_ADDR[@]} - 1 ))
    fi
    if [ "$score" = "不可达" ]; then
      RAW_VAL[$ix]="${RAW_VAL[$ix]}${ts}|不可达|-|${delay}|UNREACH
"
    else
      RAW_VAL[$ix]="${RAW_VAL[$ix]}${ts}|${score}|${stab}|${delay}
"
      rec_total=$((rec_total+1))
    fi
  done < <(grep -oE '"addr": ?"[^"]+", ?"score": ?"[^"]*", ?"stab": ?"[^"]*", ?"delay_ms": ?[0-9]+' "$f")
done

if [ "$rec_total" -eq 0 ]; then
  echo "❌ 无可用数据（所有记录均为不可达，或已被 --since/过滤条件排除）"
  exit 2
fi

T0_TS=$(echo "$FILES" | head -1 | sed 's/.*compare-//;s/.json//' | sed 's/\(....\)\(..\)\(..\)-\(..\)\(..\)\(..\)/\1-\2-\3 \4:\5/')
T1_TS=$(echo "$FILES" | tail -1 | sed 's/.*compare-//;s/.json//' | sed 's/\(....\)\(..\)\(..\)-\(..\)\(..\)\(..\)/\1-\2-\3 \4:\5/')
N_FILES=$(echo "$FILES" | wc -l | tr -d ' ')

print_header "DNS趋势洞察 — ${N_FILES}次采集 | ${rec_total}条可达记录"
echo "  数据源: $SRC_DIR/compare-*.json  |  产物: $OUT_DIR/"
echo "  期间: ${T0_TS} ~ ${T1_TS}"
echo ""

printf "  %-40s %-6s %-9s %-8s %-9s %-8s\n" "DNS" "样本" "评分均值" "评分趋势" "延迟均值" "延迟趋势"
print_separator

if [ "$GEN_CSV" = "1" ]; then
  CSVF="$OUT_DIR/trends.csv"
  echo "timestamp,addr,score,stab,delay_ms" > "$CSVF"
fi

HTML_ROWS=""      # 总览表行
HTML_CHARTS=""    # 图表卡片

# ============================================================================
# 趋势统计函数: 输出 "score_t|delay_t|score_mean|stab_mean|delay_mean|score_last|delay_last|n_ok|n_un"
# ============================================================================
trend_stats() {
  local lines="$1"
  local ok_lines n_ok n_un
  ok_lines=$(printf '%s\n' "$lines" | grep -v UNREACH)
  n_ok=$(printf '%s\n' "$ok_lines" | grep -c '|' )
  n_un=$(printf '%s\n' "$lines" | grep -c UNREACH)
  [ -z "$n_ok" ] && n_ok=0
  [ -z "$n_un" ] && n_un=0
  if [ "$n_ok" -lt 1 ]; then
    echo "-|-|-|-|-|-|-|0|$n_un"; return
  fi
  local score_mean stab_mean delay_mean score_last delay_last
  score_mean=$(printf '%s\n' "$ok_lines" | awk -F'|' '{s+=$2} END{printf "%.1f", s/NR}')
  stab_mean=$(printf '%s\n' "$ok_lines" | awk -F'|' '{s+=$3} END{printf "%.1f", s/NR}')
  delay_mean=$(printf '%s\n' "$ok_lines" | awk -F'|' '{s+=$4} END{printf "%.1f", s/NR}')
  score_last=$(printf '%s\n' "$ok_lines" | tail -1 | cut -d'|' -f2)
  delay_last=$(printf '%s\n' "$ok_lines" | tail -1 | cut -d'|' -f4)
  local score_slope=0 delay_slope=0
  if [ "$n_ok" -ge 3 ]; then
    score_slope=$(printf '%s\n' "$ok_lines" | awk -F'|' '{n++;sx+=n-1;sy+=$2;sxx+=(n-1)*(n-1);sxy+=(n-1)*$2} END{d=n*sxx-sx*sx; printf "%.4f", (d==0)?0:(n*sxy-sx*sy)/d}')
    delay_slope=$(printf '%s\n' "$ok_lines" | awk -F'|' '{n++;sx+=n-1;sy+=$4;sxx+=(n-1)*(n-1);sxy+=(n-1)*$4} END{d=n*sxx-sx*sx; printf "%.4f", (d==0)?0:(n*sxy-sx*sy)/d}')
  fi
  local score_first delay_first score_diff delay_diff
  score_first=$(printf '%s\n' "$ok_lines" | head -1 | cut -d'|' -f2)
  delay_first=$(printf '%s\n' "$ok_lines" | head -1 | cut -d'|' -f4)
  score_diff=$((score_last - score_first))
  delay_diff=$((delay_last - delay_first))

  # 评分趋势（回归为主，首尾为辅）
  local score_t="→ 平稳"
  if awk "BEGIN{exit !($score_slope > 0.05)}"; then score_t="↑ 变好"
  elif awk "BEGIN{exit !($score_slope < -0.05)}"; then score_t="↓ 变差"
  else
    if [ "$score_diff" -gt 0 ]; then score_t="↗ 微升"
    elif [ "$score_diff" -lt 0 ]; then score_t="↘ 微降"; fi
  fi
  # 延迟趋势（箭头=好坏方向）
  local delay_t="→ 平稳"
  if awk "BEGIN{exit !($delay_slope > 0.05)}"; then delay_t="↓ 变差"
  elif awk "BEGIN{exit !($delay_slope < -0.05)}"; then delay_t="↑ 变好"
  else
    if [ "$delay_diff" -gt 0 ]; then delay_t="↘ 变差"
    elif [ "$delay_diff" -lt 0 ]; then delay_t="↗ 变好"; fi
  fi
  echo "$score_t|$delay_t|$score_mean|$stab_mean|$delay_mean|$score_last|$delay_last|$n_ok|$n_un"
}

# ============================================================================
# SVG 折线图（纯bash生成，无JS依赖）
# 用法: svg_chart "addr" "数据行" "score|delay" "趋势文字" "单位" "最新值" "均值"
# ============================================================================
svg_chart() {
  local addr="$1" data="$2" metric="$3" trend="$4" unit="$5" last_disp="$6" mean_disp="$7"
  local title color
  if [ "$metric" = "score" ]; then
    title="综合评分趋势"; color="#22c55e"
  else
    title="延迟趋势 (ms) — 越低越好"; color="#3b82f6"
  fi
  local w=660 h=170 pad_l=44 pad_r=14 pad_t=22 pad_b=28
  local plot_w=$((w - pad_l - pad_r)) plot_h=$((h - pad_t - pad_b))
  local n=0
  while IFS= read -r line; do [ -n "$line" ] && n=$((n+1)); done <<< "$data"
  if [ "$n" -lt 2 ]; then
    echo "<div class='card'><h2>$addr — $title</h2><div class='meta'>样本不足（$n条，至少2条才出图）</div></div>"
    return
  fi
  local col=2; [ "$metric" = "delay" ] && col=4
  local minv maxv
  minv=$(printf '%s\n' "$data" | awk -F'|' -v c=$col 'NR==1{m=$c} {if($c<m)m=$c} END{print m}')
  maxv=$(printf '%s\n' "$data" | awk -F'|' -v c=$col 'NR==1{m=$c} {if($c>m)m=$c} END{print m}')
  [ "$minv" = "$maxv" ] && maxv=$((minv + 1))
  local pts="" dots="" labels="" i=0
  while IFS='|' read -r ts sc st dl; do
    local v=""; [ "$metric" = "score" ] && v=$sc || v=$dl
    local x=$((pad_l + i * plot_w / (n - 1)))
    local y=$((pad_t + (maxv - v) * plot_h / (maxv - minv)))
    pts="$pts $x,$y"
    dots="$dots<circle cx='$x' cy='$y' r='3' fill='$color'/>"
    if [ $i -eq 0 ] || [ $i -eq $((n - 1)) ] || [ $n -le 10 ]; then
      labels="$labels<text x='$x' y='$((h - 8))' font-size='10' fill='#999' text-anchor='middle'>${ts:5:11}</text>"
    fi
    i=$((i+1))
  done <<< "$data"
  echo "<div class='card'><h2>$addr — $title</h2>"
  echo "<div class='meta'>最新: $last_disp$unit ｜ 均值: $mean_disp$unit ｜ 趋势: $trend</div>"
  echo "<div class='sc'><svg viewBox='0 0 $w $h' style='min-width:${w}px;max-width:100%'>"
  echo "<line x1='$pad_l' y1='$pad_t' x2='$pad_l' y2='$((pad_t + plot_h))' stroke='#ddd'/>"
  echo "<line x1='$pad_l' y1='$((pad_t + plot_h))' x2='$((pad_l + plot_w))' y2='$((pad_t + plot_h))' stroke='#ddd'/>"
  echo "<text x='6' y='$((pad_t + 4))' font-size='10' fill='#999'>$maxv</text>"
  echo "<text x='6' y='$((pad_t + plot_h + 4))' font-size='10' fill='#999'>$minv</text>"
  echo "<polyline points='$pts' fill='none' stroke='$color' stroke-width='2' stroke-linejoin='round'/>"
  echo "$dots"
  echo "$labels"
  echo "</svg></div></div>"
}

# ============================================================================
# 主循环：每个DNS统计 + 输出
# ============================================================================
for k in "${!RAW_ADDR[@]}"; do
  addr="${RAW_ADDR[$k]}"
  lines="${RAW_VAL[$k]}"
  stats=$(trend_stats "$lines")
  score_t=$(echo "$stats" | cut -d'|' -f1)
  delay_t=$(echo "$stats" | cut -d'|' -f2)
  score_mean=$(echo "$stats" | cut -d'|' -f3)
  stab_mean=$(echo "$stats" | cut -d'|' -f4)
  delay_mean=$(echo "$stats" | cut -d'|' -f5)
  score_last=$(echo "$stats" | cut -d'|' -f6)
  delay_last=$(echo "$stats" | cut -d'|' -f7)
  n_ok=$(echo "$stats" | cut -d'|' -f8)
  n_un=$(echo "$stats" | cut -d'|' -f9)

  un_suffix=""
  [ "$n_un" -gt 0 ] && un_suffix=" (含${n_un}次不可达)"

  if [ "$n_ok" -ge 1 ]; then
    printf "  %-40s %-6s %-9s %-8s %-9s %-8s%s\n" "$addr" "$n_ok" "$score_mean%" "$score_t" "${delay_mean}ms" "$delay_t" "$un_suffix"
  else
    printf "  %-40s %-6s %-9s %-8s %-9s %-8s%s\n" "$addr" "0" "-" "-" "-" "-" "$un_suffix"
  fi

  # CSV
  if [ "$GEN_CSV" = "1" ] && [ "$n_ok" -ge 1 ]; then
    printf '%s\n' "$lines" | grep -v UNREACH | grep -v '^$' | while IFS='|' read -r ts sc st dl; do
      echo "$ts,$addr,$sc,$st,$dl" >> "$CSVF"
    done
  fi

  # 明细（--detail）
  if [ "$DETAIL" = "1" ] && [ "$n_ok" -ge 1 ]; then
    printf '     ── %s 明细（最早→最新）──\n' "$addr"
    printf '%s\n' "$lines" | grep -v UNREACH | grep -v '^$' | tail -n "${LIMIT:-10}" | while IFS='|' read -r ts sc st dl; do
      tss=$(echo "$ts" | sed 's/^[0-9]*-\([0-9]*-[0-9]* [0-9]*:[0-9]*\).*/\1/')
      printf '        %-12s 评分%-4s 稳定性%-4s 延迟%sms\n' "$tss" "$sc" "$st" "$dl"
    done
  fi

  # HTML
  if [ "$GEN_HTML" = "1" ]; then
    if [ "$n_ok" -ge 1 ]; then
      stc="flat"
      case "$score_t" in *变好*) stc="up";; *变差*) stc="down";; esac
      dtc="flat"
      case "$delay_t" in *变好*) dtc="up";; *变差*) dtc="down";; esac
      HTML_ROWS="$HTML_ROWS<tr><td>$addr</td><td>$n_ok</td><td>${score_mean}%</td><td class='$stc'>$score_t</td><td>${delay_mean}ms</td><td class='$dtc'>$delay_t</td></tr>"
    else
      HTML_ROWS="$HTML_ROWS<tr><td>$addr</td><td>0</td><td>—</td><td>—</td><td>—</td><td>—</td></tr>"
    fi
    ok_lines=$(printf '%s\n' "$lines" | grep -v UNREACH)
    if [ "$n_ok" -ge 2 ]; then
      HTML_CHARTS="$HTML_CHARTS$(svg_chart "$addr" "$ok_lines" score "$score_t" "%" "$score_last" "$score_mean")"
      HTML_CHARTS="$HTML_CHARTS$(svg_chart "$addr" "$ok_lines" delay "$delay_t" "ms" "$delay_last" "$delay_mean")"
    fi
  fi
done

if [ "$GEN_CSV" = "1" ]; then
  echo ""
  echo "  📄 CSV已导出: $CSVF"
fi

# ---------- HTML 报告 ----------
if [ "$GEN_HTML" = "1" ]; then
  HF="$OUT_DIR/report.html"
  {
    echo "<!DOCTYPE html>"
    echo "<html lang='zh'><head><meta charset='utf-8'>"
    echo "<meta name='viewport' content='width=device-width,initial-scale=1'>"
    echo "<title>DNS趋势报告</title>"
    echo "<style>"
    echo "body{font-family:-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;margin:0;background:#f5f7fa;color:#333}"
    echo ".wrap{max-width:920px;margin:24px auto;padding:0 16px}"
    echo ".card{background:#fff;border-radius:12px;padding:20px 24px;margin:16px 0;box-shadow:0 2px 8px rgba(0,0,0,.06)}"
    echo "h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:14px 0 6px;color:#555}"
    echo ".meta{color:#888;font-size:13px;margin-bottom:10px}"
    echo ".up{color:#16a34a}.down{color:#dc2626}.flat{color:#888}"
    echo "table{width:100%;border-collapse:collapse;font-size:14px;margin:10px 0}"
    echo "th,td{padding:8px;text-align:left;border-bottom:1px solid #eee}"
    echo "th{background:#fafbfc;color:#666}"
    echo ".sc{overflow-x:auto}"
    echo "@media(max-width:600px){.wrap{padding:0 8px}.card{padding:14px}table{font-size:12px}}"
    echo "</style></head><body>"
    echo "<div class='wrap'>"
    echo "<div class='card'><h1>📈 DNS 趋势报告</h1>"
    echo "<div class='meta'>${N_FILES}次采集（${T0_TS} ~ ${T1_TS}）｜ dns-test ${VERSION} ｜ 数据源 ${SRC_DIR}/compare-*.json</div>"
    echo "<table><tr><th>DNS</th><th>样本</th><th>评分均值</th><th>评分趋势</th><th>延迟均值</th><th>延迟趋势</th></tr>"
    echo "$HTML_ROWS"
    echo "</table></div>"
    echo "$HTML_CHARTS"
    echo "</div></body></html>"
  } > "$HF"
  echo ""
  echo "  📄 HTML趋势报告已生成: $HF"
fi

exit 0
