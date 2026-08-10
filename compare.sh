#!/bin/bash
# ============================================================================
# 多DNS对比模式 + 可选HTML报告
# 用法: bash compare.sh DNS1 [DNS2] ... [--html]
#   例: bash compare.sh 223.5.5.5 119.29.29.29 222.172.200.68
#       bash compare.sh 223.5.5.5 119.29.29.29 --html   # 生成results/report.html
# ============================================================================
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"
source lib/core.sh

# 解析参数（--html 标记）
GEN_HTML=0
DNS_ARGS=()
for a in "$@"; do
  if [ "$a" = "--html" ]; then GEN_HTML=1; else DNS_ARGS+=("$a"); fi
done
if [ ${#DNS_ARGS[@]} -eq 0 ]; then
  echo "用法: bash compare.sh DNS1 [DNS2] ... [--html]"
  exit 1
fi
# 地址校验
for d in "${DNS_ARGS[@]}"; do
  valid_dns_addr "$d" || { echo "❌ 非法DNS地址: $d"; exit 1; }
done

echo "════ 多DNS对比测试 ════"
echo "测试: ${DNS_ARGS[*]}"
echo ""

declare -A SCORE DELAY STAB
for d in "${DNS_ARGS[@]}"; do
  printf "  ⏳ 测试 %s ...\n" "$d"
  out=$(bash lite.sh "$d" 0 2>&1)
  SCORE[$d]=$(echo "$out" | grep -oE "综合评分: [0-9]+" | grep -oE "[0-9]+")
  # lite版不输出平均延迟，单独dig测一次
  DELAY[$d]=$(dig @$d www.baidu.com A +time=3 +tries=1 2>/dev/null | sed -n 's/.*Query time: \([0-9]*\).*/\1/p' | head -1)
  STAB[$d]=$(echo "$out" | grep -oE "稳定性: [0-9]+%" | grep -oE "[0-9]+")
  [ -z "${SCORE[$d]}" ] && SCORE[$d]="不可达"
done

echo ""
echo "════ 对比结果 ════"
printf "  %-24s %-8s %-10s %-8s\n" "DNS" "评分" "延迟ms" "稳定性"
for d in "${DNS_ARGS[@]}"; do
  printf "  %-24s %-8s %-10s %-8s\n" "$d" "${SCORE[$d]}%" "${DELAY[$d]}" "${STAB[$d]}%"
done

# HTML 报告（CSS 柱状图）
if [ "$GEN_HTML" = "1" ]; then
  mkdir -p results
  HTML="results/report.html"
  {
    echo "<!DOCTYPE html><html><head><meta charset='utf-8'><title>DNS对比报告</title>"
    echo "<style>body{font-family:sans-serif;margin:40px}.bar{background:#4caf50;height:24px;margin:4px 0;border-radius:3px;min-width:2px}.wrap{display:flex;align-items:center;margin:6px 0}.name{width:260px}</style></head><body>"
    echo "<h2>DNS 对比报告</h2><p>$(date '+%Y-%m-%d %H:%M:%S') | 精简版测试</p>"
    echo "<h3>综合评分</h3>"
    for d in "${DNS_ARGS[@]}"; do
      s="${SCORE[$d]}"; [ "$s" = "不可达" ] && s=0
      echo "<div class='wrap'><span class='name'>$d</span><div class='bar' style='width:${s}%'></div><span style='margin-left:8px'>${SCORE[$d]}%</span></div>"
    done
    echo "<h3>平均延迟 (ms)</h3>"
    maxd=1; for d in "${DNS_ARGS[@]}"; do [ "${DELAY[$d]}" -gt "$maxd" ] 2>/dev/null && maxd="${DELAY[$d]}"; done
    for d in "${DNS_ARGS[@]}"; do
      dd="${DELAY[$d]:-0}"; w=$(( dd * 100 / maxd )); [ "$w" -gt 100 ] && w=100
      echo "<div class='wrap'><span class='name'>$d</span><div class='bar' style='width:${w}%;background:#2196f3'></div><span style='margin-left:8px'>${DELAY[$d]}ms</span></div>"
    done
    echo "</body></html>"
  } > "$HTML"
  echo ""
  echo "📄 HTML报告已生成: $HTML"
fi
