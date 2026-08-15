#!/bin/bash
# ============================================================================
# DNS 趋势洞察：聚合 compare.sh 的历史 JSON 结果，输出趋势总览/CSV/HTML报告
# 兼容性: bash 3.2+（无关联数组依赖，macOS 默认 bash 可直接运行）
# 用法: bash trends.sh [DNS地址...] [--html] [--open] [--csv] [--cron] [--detail] [--limit N] [--since YYYY-MM-DD] [--prune N]
#   例: bash trends.sh                              # 全部DNS趋势总览（文本，含P95/时段分析）
#       bash trends.sh 223.5.5.5                    # 只看223.5.5.5
#       bash trends.sh --html --csv                 # 生成 trends/report.html + trends.csv
#       bash trends.sh --html --open                # 生成HTML并自动在浏览器打开（隐含--html）
#       bash trends.sh --cron 223.5.5.5 119.29.29.29  # 先采集(跑compare)再聚合（crontab用）
#       bash trends.sh --detail --limit 5           # 每个DNS列最近5条明细
# 环境变量:
#   TRENDS_DIR              趋势产物目录（默认 trends/）
#   COMPARE_RESULTS_DIR     compare JSON 数据源目录（默认 results/）
# 趋势判断: 线性回归斜率为主 + 首尾对比为辅
#   评分: ↑=变好 ↓=变差；延迟: ↑=变好 ↓=变差（箭头=好坏方向，非数值方向）
#   延迟统计: 均值 + P50/P95 分位（长尾场景均值失真，P95 更真实）
#   时段分析: 按小时聚合延迟，标出最优/最差时段（每小时≥3样本才统计）
# 退出码: 0=完成  1=参数/错误  2=无可用数据
# ============================================================================
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 1
cd "$SCRIPT_DIR" || exit 1
source lib/core.sh

VERSION="${PROJECT_VERSION}"
SRC_DIR="${COMPARE_RESULTS_DIR:-results}"   # compare JSON 数据源
OUT_DIR="${TRENDS_DIR:-trends}"             # 趋势产物目录
GEN_HTML=0
GEN_CSV=0
GEN_OPEN=0
CRON_MODE=0
DETAIL=0
LIMIT=""
SINCE=""
PRUNE_N=""
FILTER=()

# ---------- 参数解析（while+shift风格，兼容--limit N成对取值） ----------
ARGS=("$@")
i=0
while [ $i -lt ${#ARGS[@]} ]; do
  a="${ARGS[$i]}"
  case "$a" in
    --html)   GEN_HTML=1 ;;
    --open)   GEN_HTML=1; GEN_OPEN=1 ;;   # --open 隐含 --html（打开的前提是生成）
    --csv)    GEN_CSV=1 ;;
    --cron)   CRON_MODE=1 ;;
    --detail) DETAIL=1 ;;
    --limit)  i=$((i+1)); LIMIT="${ARGS[$i]:-}"; [ -z "$LIMIT" ] && { echo "❌ --limit 缺少值"; exit 1; } ;;
    --since)  i=$((i+1)); SINCE="${ARGS[$i]:-}"; [ -z "$SINCE" ] && { echo "❌ --since 缺少值"; exit 1; } ;;
    --prune)  i=$((i+1)); PRUNE_N="${ARGS[$i]:-}"; [ -z "$PRUNE_N" ] && { echo "❌ --prune 缺少值"; exit 1; } ;;
    --version)
      echo "dns-test ${PROJECT_VERSION} (${PROJECT_RELEASE})"
      exit 0 ;;
    --help|-h)
      echo "用法: bash trends.sh [DNS地址...] [--html] [--open] [--csv] [--cron] [--detail] [--limit N] [--since YYYY-MM-DD] [--prune N]"
      echo "  例: bash trends.sh --html --csv"
      echo "      bash trends.sh --html --open                    # 生成HTML并自动打开(隐含--html)"
      echo "      bash trends.sh --cron 223.5.5.5 119.29.29.29   # 先采集再聚合(crontab用)"
      echo "      bash trends.sh --prune 200 --html              # 只保留最近200份JSON再聚合(--watch配套)"
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

# --since 日期格式校验（写错格式会静默全排除/全保留，与静默吞错不同，必须显式报错）
if [ -n "$SINCE" ] && ! [[ "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "❌ --since 格式必须为 YYYY-MM-DD（例: --since 2026-08-01），收到: $SINCE"
  exit 1
fi

# ---------- --cron 采集模式：先跑 compare 再聚合 ----------
if [ "$CRON_MODE" = "1" ]; then
  if [ ${#FILTER[@]} -eq 0 ]; then
    echo "❌ --cron 需要至少一个DNS参数（要采集的DNS）"
    echo "  例: bash trends.sh --cron 223.5.5.5 119.29.29.29"
    exit 1
  fi
  mkdir -p "$OUT_DIR"
  # cron.log 超过 512KB 先轮转为 cron.log.1（防长期 cron 无限增长；只留一代足够排查）
  if [ -f "$OUT_DIR/cron.log" ] && [ "$(wc -c < "$OUT_DIR/cron.log")" -gt 524288 ]; then
    mv -f "$OUT_DIR/cron.log" "$OUT_DIR/cron.log.1"
    echo "  ♻️  cron.log 超过512KB，已轮转为 cron.log.1"
  fi
  echo "⏳ 采集: compare.sh ${FILTER[*]}"
  bash compare.sh "${FILTER[@]}" >> "$OUT_DIR/cron.log" 2>&1
  echo "   采集完成，开始聚合..."
fi

# ---------- --prune N：只保留最近 N 份 compare JSON（--watch/定时长期采集的磁盘配套清理） ----------
# glob 字典序=时间序（时间戳文件名），删最老的 TOTAL-N 份；先清理再聚合，报告口径与留存一致
if [ -n "$PRUNE_N" ]; then
  if ! [[ "$PRUNE_N" =~ ^[1-9][0-9]*$ ]]; then
    echo "❌ --prune 参数必须为正整数（保留份数），收到: $PRUNE_N"; exit 1
  fi
  PFILES=()
  for _f in "$SRC_DIR"/compare-*.json; do
    [ -e "$_f" ] && PFILES+=("$_f")
  done
  PTOTAL=${#PFILES[@]}
  if [ "$PTOTAL" -le "$PRUNE_N" ]; then
    echo "  ♻️  --prune: 共 ${PTOTAL} 份 ≤ 保留 ${PRUNE_N} 份，无需清理"
  else
    DELN=$((PTOTAL - PRUNE_N))
    echo "  ♻️  --prune: 共 ${PTOTAL} 份，保留最近 ${PRUNE_N} 份，删除 ${DELN} 份:"
    k=0
    for _f in "${PFILES[@]}"; do
      k=$((k+1))
      if [ "$k" -le "$DELN" ]; then
        echo "     🗑️  $(basename "$_f")"
        rm -f "$_f"
      fi
    done
  fi
fi

# ---------- 数据扫描 ----------
mkdir -p "$SRC_DIR" "$OUT_DIR"
# glob 展开天然按字典序（含时间戳文件名即时间序），不解析 ls 输出（规避 SC2012：文件名含空格/换字的解析风险）
FILES=""
for _f in "$SRC_DIR"/compare-*.json; do
  [ -e "$_f" ] && FILES="$FILES$_f
"
done
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
#   ROUNDS_TS[] = 全局轮次轴（每份JSON的采集时间戳，文件序=时间序）
#                 多DNS同图对比的共享X轴：各DNS样本按所属轮次对齐，缺轮自然留缺口
# ============================================================================
RAW_ADDR=()
RAW_VAL=()
ROUNDS_TS=()

# 查找 addr 在 RAW_ADDR 的下标（-1=不存在）
raw_idx() {
  local d="$1" k=0
  for a in "${RAW_ADDR[@]}"; do
    [ "$a" = "$d" ] && { echo "$k"; return 0; }
    k=$((k+1))
  done
  echo "-1"
}

# 查找时间戳在 ROUNDS_TS 的轮次下标（-1=不在轴上）
round_idx() {
  local t="$1" k=0
  for r in "${ROUNDS_TS[@]}"; do
    [ "$r" = "$t" ] && { echo "$k"; return 0; }
    k=$((k+1))
  done
  echo "-1"
}

rec_total=0
for f in $FILES; do
  ts=$(grep -oE '"timestamp": ?"[^"]+"' "$f" | head -1 | sed 's/"timestamp": *"//;s/"$//')
  [ -z "$ts" ] && continue
  if [ -n "$SINCE" ] && [[ "$ts" < "$SINCE" ]]; then continue; fi
  ROUNDS_TS+=("$ts")
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

# 修尾换行坑：FILES 构造时每行带 \n，尾部空行会让 wc -l 多算1、tail -1 取到空行（期间终点显示为空）
# 统一按"非空行"口径取首/尾/计数
fmt_ts() { sed 's/.*compare-//;s/.json//' | sed 's/\(....\)\(..\)\(..\)-\(..\)\(..\)\(..\)/\1-\2-\3 \4:\5/'; }
T0_TS=$(printf '%s\n' "$FILES" | awk 'NF{print; exit}' | fmt_ts)
T1_TS=$(printf '%s\n' "$FILES" | awk 'NF{f=$0} END{print f}' | fmt_ts)
N_FILES=$(printf '%s\n' "$FILES" | grep -c .)

print_header "DNS趋势洞察 — ${N_FILES}次采集 | ${rec_total}条可达记录"
echo "  数据源: $SRC_DIR/compare-*.json  |  产物: $OUT_DIR/"
echo "  期间: ${T0_TS} ~ ${T1_TS}"
echo ""

printf "  %-46s %-6s %-9s %-8s %-9s %-8s %-9s\n" "DNS" "样本" "评分均值" "评分趋势" "延迟均值" "延迟趋势" "P95延迟"
print_separator

if [ "$GEN_CSV" = "1" ]; then
  CSVF="$OUT_DIR/trends.csv"
  echo "timestamp,addr,score,stab,delay_ms" > "$CSVF"
fi

HTML_ROWS=""      # 总览表行
HTML_CHARTS=""    # 图表卡片

# ============================================================================
# 趋势统计函数: 输出 "score_t|delay_t|score_mean|stab_mean|delay_mean|score_last|delay_last|n_ok|n_un|p50|p95"
#   p50/p95 = 延迟分位数（排序取位；样本≥2才出，否则 - ）
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
    echo "-|-|-|-|-|-|-|0|$n_un|-|-"; return
  fi
  local score_mean stab_mean delay_mean score_last delay_last
  score_mean=$(printf '%s\n' "$ok_lines" | awk -F'|' '{s+=$2} END{printf "%.1f", s/NR}')
  stab_mean=$(printf '%s\n' "$ok_lines" | awk -F'|' '{s+=$3} END{printf "%.1f", s/NR}')
  delay_mean=$(printf '%s\n' "$ok_lines" | awk -F'|' '{s+=$4} END{printf "%.1f", s/NR}')
  score_last=$(printf '%s\n' "$ok_lines" | tail -1 | cut -d'|' -f2)
  delay_last=$(printf '%s\n' "$ok_lines" | tail -1 | cut -d'|' -f4)
  # 延迟分位数：P50 中位 / P95 长尾上界（均值被长尾拉高时，P50 更接近体感）
  local p50="-" p95="-"
  if [ "$n_ok" -ge 2 ]; then
    p50=$(printf '%s\n' "$ok_lines" | awk -F'|' '{print $4}' | sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}')
    p95=$(printf '%s\n' "$ok_lines" | awk -F'|' '{print $4}' | sort -n | awk '{a[NR]=$1} END{print a[int(NR*0.95+0.5)]}')
  fi
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
  echo "$score_t|$delay_t|$score_mean|$stab_mean|$delay_mean|$score_last|$delay_last|$n_ok|$n_un|$p50|$p95"
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
    if [ $i -eq 0 ] || [ $i -eq $((n - 1)) ] || [ "$n" -le 10 ]; then
      labels="$labels<text x='$x' y='$((h - 8))' font-size='10' class='ax-t' text-anchor='middle'>${ts:5:11}</text>"
    fi
    i=$((i+1))
  done <<< "$data"
  echo "<div class='card'><h2><span class='mono'>$addr</span> — $title</h2>"
  echo "<div class='meta'>最新: $last_disp$unit ｜ 均值: $mean_disp$unit ｜ 趋势: $trend</div>"
  echo "<div class='sc'><svg viewBox='0 0 $w $h' style='min-width:${w}px;max-width:100%'>"
  echo "<line class='ax' x1='$pad_l' y1='$pad_t' x2='$pad_l' y2='$((pad_t + plot_h))'/>"
  echo "<line class='ax' x1='$pad_l' y1='$((pad_t + plot_h))' x2='$((pad_l + plot_w))' y2='$((pad_t + plot_h))'/>"
  echo "<text x='6' y='$((pad_t + 4))' font-size='10' class='ax-t'>$maxv</text>"
  echo "<text x='6' y='$((pad_t + plot_h + 4))' font-size='10' class='ax-t'>$minv</text>"
  echo "<polyline points='$pts' fill='none' stroke='$color' stroke-width='2' stroke-linejoin='round'/>"
  echo "$dots"
  echo "$labels"
  echo "</svg></div></div>"
}

# ============================================================================
# SVG 多DNS同图对比（纯bash生成）：所有DNS画在同一坐标系，共享轮次X轴（ROUNDS_TS）
# 用法: svg_multi_chart "score|delay"
#   读全局 RAW_ADDR/RAW_VAL/ROUNDS_TS；缺轮的DNS点跳过（线跨缺口直连），颜色按DNS序循环
# ============================================================================
MULTI_COLORS=("#22c55e" "#3b82f6" "#f59e0b" "#ef4444" "#8b5cf6" "#14b8a6" "#f97316" "#64748b")
svg_multi_chart() {
  local metric="$1"
  local n_rounds=${#ROUNDS_TS[@]}
  if [ "$n_rounds" -lt 2 ] || [ ${#RAW_ADDR[@]} -lt 2 ]; then return 0; fi
  local col=2 title unit
  if [ "$metric" = "score" ]; then title="综合评分对比"; col=2; unit="%"
  else title="延迟对比 (ms) — 越低越好"; col=4; unit="ms"; fi
  local w=660 h=200 pad_l=44 pad_r=14 pad_t=14 pad_b=40
  local plot_w=$((w - pad_l - pad_r)) plot_h=$((h - pad_t - pad_b))
  # Y 轴值域：所有DNS该指标的全局 min/max（不可达轮不参与，天然留缺口）
  local gmin="" gmax=""
  for k in "${!RAW_ADDR[@]}"; do
    while IFS='|' read -r ts sc st dl; do
      [ -z "$ts" ] && continue
      local v; [ "$metric" = "score" ] && v="$sc" || v="$dl"
      [ -z "$gmin" ] && gmin="$v"
      [ -z "$gmax" ] && gmax="$v"
      [ "$v" -lt "$gmin" ] 2>/dev/null && gmin="$v"
      [ "$v" -gt "$gmax" ] 2>/dev/null && gmax="$v"
    done <<< "$(printf '%s\n' "${RAW_VAL[$k]}" | grep -v UNREACH)"
  done
  [ -z "$gmin" ] && return 0
  [ "$gmin" = "$gmax" ] && gmax=$((gmin + 1))
  local legend="" ci=0
  echo "<div class='card'><h2>📊 $title（${#RAW_ADDR[@]}个DNS × ${n_rounds}轮）</h2>"
  echo "<div class='sc'><svg viewBox='0 0 $w $h' style='min-width:${w}px;max-width:100%'>"
  echo "<line class='ax' x1='$pad_l' y1='$pad_t' x2='$pad_l' y2='$((pad_t + plot_h))'/>"
  echo "<line class='ax' x1='$pad_l' y1='$((pad_t + plot_h))' x2='$((pad_l + plot_w))' y2='$((pad_t + plot_h))'/>"
  echo "<text x='4' y='$((pad_t + 4))' font-size='10' class='ax-t'>$gmax</text>"
  echo "<text x='4' y='$((pad_t + plot_h + 4))' font-size='10' class='ax-t'>$gmin</text>"
  # X 轴标签：首/尾 + 中点（轮次≥3才画中点，2轮时中=尾会重叠）
  local mid_r=$((n_rounds / 2))
  local xlabels="0 $((n_rounds - 1))"
  [ "$n_rounds" -ge 3 ] && xlabels="0 $mid_r $((n_rounds - 1))"
  for r in $xlabels; do
    local lx=$((pad_l + r * plot_w / (n_rounds - 1)))
    [ "$r" = "$((n_rounds - 1))" ] && lx=$((pad_l + plot_w))
    local anchor="middle"; [ "$r" = "0" ] && anchor="start"; [ "$r" = "$((n_rounds - 1))" ] && anchor="end"
    echo "<text x='$lx' y='$((h - 26))' font-size='10' class='ax-t' text-anchor='$anchor'>${ROUNDS_TS[$r]:5:11}</text>"
  done
  for k in "${!RAW_ADDR[@]}"; do
    local color="${MULTI_COLORS[$((ci % ${#MULTI_COLORS[@]}))]}"
    local pts="" dots="" first=1
    while IFS='|' read -r ts sc st dl; do
      [ -z "$ts" ] && continue
      local v; [ "$metric" = "score" ] && v="$sc" || v="$dl"
      local ri; ri=$(round_idx "$ts")
      [ "$ri" = "-1" ] && continue
      local x=$((pad_l + ri * plot_w / (n_rounds - 1)))
      local y=$((pad_t + (gmax - v) * plot_h / (gmax - gmin)))
      if [ "$first" = "1" ]; then pts="$x,$y"; first=0; else pts="$pts $x,$y"; fi
      dots="$dots<circle cx='$x' cy='$y' r='2.5' fill='$color'/>"
    done <<< "$(printf '%s\n' "${RAW_VAL[$k]}" | grep -v UNREACH)"
    if [ "$first" = "0" ]; then
      echo "<polyline points='$pts' fill='none' stroke='$color' stroke-width='2' stroke-linejoin='round' opacity='.85'/>"
      echo "$dots"
    fi
    # 图例：色块 + 地址（+提供商标签）
    local _lg="${RAW_ADDR[$k]}"; _lt=$(dns_preset_label "${RAW_ADDR[$k]}") && _lg="${_lg}·${_lt}"
    legend="$legend<span class='lg-i'><span class='lg-c' style='background:$color'></span>${_lg}</span>"
    ci=$((ci+1))
  done
  echo "</svg></div>"
  echo "<div class='legend'>$legend</div>"
  echo "<div class='meta'>X轴=采集轮次（按时间等距）；某轮不可达的DNS该点缺省，折线跨缺口直连</div>"
  echo "</div>"
}

# ============================================================================
# 主循环：每个DNS统计 + 输出（文本表/明细/时段分析/CSV/HTML行与图表）
# ============================================================================
HOUR_ANALYSIS=""   # 时段分析文本行（凑齐才输出小节）
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
  p50=$(echo "$stats" | cut -d'|' -f10)
  p95=$(echo "$stats" | cut -d'|' -f11)

  # 提供商标签（预设内 DNS 才有，与 compare.sh 报告同口径）
  addr_show="$addr"
  plabel=$(dns_preset_label "$addr") && addr_show="${addr}·${plabel}"

  un_suffix=""
  [ "$n_un" -gt 0 ] && un_suffix=" (含${n_un}次不可达)"
  p95_show="-"; [ "$p95" != "-" ] && p95_show="${p95}ms"

  if [ "$n_ok" -ge 1 ]; then
    printf "  %-46s %-6s %-9s %-8s %-9s %-8s %-9s%s\n" "$addr_show" "$n_ok" "$score_mean%" "$score_t" "${delay_mean}ms" "$delay_t" "$p95_show" "$un_suffix"
  else
    printf "  %-46s %-6s %-9s %-8s %-9s %-8s %-9s%s\n" "$addr_show" "0" "-" "-" "-" "-" "-" "$un_suffix"
  fi

  # 时段分析：按小时聚合延迟（ts 取 HH 字段），每小时≥3样本才可信；输出最优/最差时段
  if [ "$n_ok" -ge 3 ]; then
    hours_stat=$(printf '%s\n' "$lines" | grep -v UNREACH | grep -v '^$' | awk -F'|' '{
      n=split($1, dt, " "); split(dt[2], hm, ":"); h=hm[1]
      sum[h]+=$4; cnt[h]++
    } END {
      for (h in sum) if (cnt[h]>=3) printf "%s %.1f %d\n", h, sum[h]/cnt[h], cnt[h]
    }' | sort -k2 -n)
    if [ -n "$hours_stat" ]; then
      best_h=$(echo "$hours_stat" | head -1)
      worst_h=$(echo "$hours_stat" | tail -1)
      bh=$(echo "$best_h"  | awk '{print $1}'); bd=$(echo "$best_h"  | awk '{print $2}')
      wh=$(echo "$worst_h" | awk '{print $1}'); wd=$(echo "$worst_h" | awk '{print $2}')
      HOUR_ANALYSIS="${HOUR_ANALYSIS}  ${addr_show}
    最差 ${wh}:00 均延${wd}ms ｜ 最优 ${bh}:00 均延${bd}ms ｜ 全程均值${delay_mean}ms
"
    fi
  fi

  # CSV
  if [ "$GEN_CSV" = "1" ] && [ "$n_ok" -ge 1 ]; then
    printf '%s\n' "$lines" | grep -v UNREACH | grep -v '^$' | while IFS='|' read -r ts sc st dl; do
      echo "$ts,$addr,$sc,$st,$dl" >> "$CSVF"
    done
  fi

  # 明细（--detail）
  if [ "$DETAIL" = "1" ] && [ "$n_ok" -ge 1 ]; then
    printf '     ── %s 明细（最早→最新）──\n' "$addr_show"
    printf '%s\n' "$lines" | grep -v UNREACH | grep -v '^$' | tail -n "${LIMIT:-10}" | while IFS='|' read -r ts sc st dl; do
      tss=$(echo "$ts" | sed 's/^[0-9]*-\([0-9]*-[0-9]* [0-9]*:[0-9]*\).*/\1/')
      printf '        %-12s 评分%-4s 稳定性%-4s 延迟%sms\n' "$tss" "$sc" "$st" "$dl"
    done
  fi

  # HTML
  if [ "$GEN_HTML" = "1" ]; then
    pl_b=""; [ -n "${plabel:-}" ] && pl_b="<span class='pname'>${plabel}</span>"
    if [ "$n_ok" -ge 1 ]; then
      stc="flat"
      case "$score_t" in *变好*) stc="up";; *变差*) stc="down";; esac
      dtc="flat"
      case "$delay_t" in *变好*) dtc="up";; *变差*) dtc="down";; esac
      HTML_ROWS="$HTML_ROWS<tr><td class='addr'>$addr$pl_b</td><td>$n_ok</td><td>${score_mean}%</td><td><span class='bdg b-$stc'>$score_t</span></td><td>${delay_mean}ms</td><td><span class='bdg b-$dtc'>$delay_t</span></td><td>${p95_show}</td></tr>"
    else
      HTML_ROWS="$HTML_ROWS<tr><td class='addr'>$addr$pl_b</td><td>0</td><td>—</td><td><span class='bdg b-flat'>—</span></td><td>—</td><td><span class='bdg b-flat'>—</span></td><td>—</td></tr>"
    fi
    ok_lines=$(printf '%s\n' "$lines" | grep -v UNREACH)
    if [ "$n_ok" -ge 2 ]; then
      HTML_CHARTS="$HTML_CHARTS$(svg_chart "$addr_show" "$ok_lines" score "$score_t" "%" "$score_last" "$score_mean")"
      HTML_CHARTS="$HTML_CHARTS$(svg_chart "$addr_show" "$ok_lines" delay "$delay_t" "ms" "$delay_last" "$delay_mean")"
    fi
  fi
done

# ---------- 时段分析小节（文本；有满足条件的DNS才输出） ----------
if [ -n "$HOUR_ANALYSIS" ]; then
  echo ""
  echo "  ━━━ 时段分析（按小时聚合，每小时≥3样本才统计） ━━━"
  printf '%s' "$HOUR_ANALYSIS"
fi

if [ "$GEN_CSV" = "1" ]; then
  echo ""
  echo "  📄 CSV已导出: $CSVF"
fi

# ---------- HTML 报告（与 compare.sh 同套视觉：CSS 变量双主题，自动跟随系统暗色） ----------
if [ "$GEN_HTML" = "1" ]; then
  HF="$OUT_DIR/report.html"
  {
    echo "<!DOCTYPE html>"
    echo "<html lang='zh'><head><meta charset='utf-8'>"
    echo "<meta name='viewport' content='width=device-width,initial-scale=1'>"
    echo "<meta name='color-scheme' content='light dark'>"
    echo "<title>DNS趋势报告</title>"
    echo "<style>"
    echo ":root{--bg:#f5f7fa;--card:#fff;--tx:#333;--sub:#888;--th-bg:#fafbfc;--th-tx:#666;--line:#eee;--gtx:#16a34a;--rtx:#dc2626;--mono:ui-monospace,SFMono-Regular,Menlo,Consolas,'Courier New',monospace}"
    echo "@media(prefers-color-scheme:dark){:root{--bg:#0f172a;--card:#1e293b;--tx:#e2e8f0;--sub:#94a3b8;--th-bg:#283548;--th-tx:#94a3b8;--line:#334155;--gtx:#4ade80;--rtx:#f87171}}"
    echo "body{font-family:-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;margin:0;background:var(--bg);color:var(--tx)}"
    echo ".wrap{max-width:920px;margin:24px auto;padding:0 16px}"
    echo ".card{background:var(--card);border-radius:12px;padding:20px 24px;margin:16px 0;box-shadow:0 2px 8px rgba(0,0,0,.06)}"
    echo "h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:14px 0 6px;color:var(--sub)}"
    echo ".meta{color:var(--sub);font-size:13px;margin-bottom:10px}"
    echo ".mono{font-family:var(--mono)}"
    echo "td.addr{font-family:var(--mono);font-size:13px}"
    echo ".pname{display:block;font-size:11px;color:var(--sub);font-family:inherit;margin-top:1px}"
    echo ".bdg{display:inline-block;min-width:52px;text-align:center;padding:2px 10px;border-radius:999px;font-size:12px;font-weight:600}"
    echo ".b-up{background:rgba(34,197,94,.14);color:var(--gtx)}.b-down{background:rgba(239,68,68,.14);color:var(--rtx)}.b-flat{background:rgba(127,127,127,.12);color:var(--sub)}"
    echo ".tbl-wrap{overflow-x:auto;-webkit-overflow-scrolling:touch}"
    echo "table{width:100%;border-collapse:collapse;font-size:14px;margin:10px 0}"
    echo "th,td{padding:8px 10px;text-align:left;border-bottom:1px solid var(--line);white-space:nowrap}"
    echo "th{background:var(--th-bg);color:var(--th-tx);font-weight:600}"
    echo "tbody tr:nth-child(even){background:rgba(127,127,127,.04)}"
    echo ".sc{overflow-x:auto}"
    echo ".ax{stroke:var(--line)}.ax-t{fill:var(--sub)}"
    echo ".legend{display:flex;flex-wrap:wrap;gap:6px 16px;margin-top:8px;font-size:12px;font-family:var(--mono)}"
    echo ".lg-i{display:inline-flex;align-items:center;gap:5px;color:var(--tx)}"
    echo ".lg-c{display:inline-block;width:14px;height:4px;border-radius:2px}"
    echo "@media(max-width:600px){.wrap{padding:0 8px}.card{padding:14px}table{font-size:12px}}"
    echo "@media print{body{background:#fff}.card{box-shadow:none;border:1px solid #ddd;break-inside:avoid}}"
    echo "</style></head><body>"
    echo "<div class='wrap'>"
    echo "<div class='card'><h1>📈 DNS 趋势报告</h1>"
    echo "<div class='meta'>${N_FILES}次采集（${T0_TS} ~ ${T1_TS}）｜ dns-test ${VERSION} ｜ 数据源 ${SRC_DIR}/compare-*.json</div>"
    echo "<div class='tbl-wrap'><table><thead><tr><th>DNS</th><th>样本</th><th>评分均值</th><th>评分趋势</th><th>延迟均值</th><th>延迟趋势</th><th>P95延迟</th></tr></thead><tbody>"
    echo "$HTML_ROWS"
    echo "</tbody></table></div></div>"
    # 多DNS同图对比总图（≥2个DNS且≥2轮才出；放在单DNS明细图之前，先总后分）
    echo "$(svg_multi_chart score)"
    echo "$(svg_multi_chart delay)"
    echo "$HTML_CHARTS"
    echo "</div></body></html>"
  } > "$HF"
  echo ""
  echo "  📄 HTML趋势报告已生成: $HF"
  # --open：生成后自动用系统浏览器打开（open_report_file 已下沉 lib/core.sh）
  if [ "${GEN_OPEN:-0}" = "1" ]; then
    open_report_file "$HF"
  fi
fi

exit 0
