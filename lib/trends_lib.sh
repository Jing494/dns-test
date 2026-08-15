#!/bin/bash
# ============================================================================
# trends 纯函数库：分位数计算 + 斜率趋势判定（无 IO/无全局状态，可独立单测）
# 供 trends.sh 的 trend_stats 调用；tests/08_trends_lib.sh 覆盖边界
# 兼容性: bash 3.2+（macOS 默认 bash 可直接 source）
# ============================================================================

# trends_percentile <每行一个数值的文本> <比例0-1，如0.5/0.95>
#   排序取位: a[int(NR*r+0.5)]（与 trend_stats 原内联式逐字符等价，浮点行为不变）
#   样本 <2 输出 "-"；例: printf '10\n20\n30\n' 经 trends_percentile 0.5 → 20
trends_percentile() {
  local vals="$1" r="$2"
  if [ -z "$(printf '%s' "$vals" | tr -d '[:space:]')" ]; then
    echo "-"; return
  fi
  printf '%s\n' "$vals" | sort -n | awk -v r="$r" '
    { a[NR] = $1 }
    END {
      if (NR < 2) { print "-"; exit }
      idx = int(NR * r + 0.5)
      if (idx < 1) idx = 1
      if (idx > NR) idx = NR
      print a[idx]
    }'
}

# trends_slope_judge <斜率> <首值> <末值> <kind: score|delay>
#   线性回归斜率为主（|slope|>0.05 显著），首尾差为辅；箭头=好坏方向（非数值方向）
#   score: 升=变好 ↓=变差；delay 反向：数值升=变差 ↓
#   平稳档内首尾仍有差 → 微升/微降（score）或 变差/变好（delay）
trends_slope_judge() {
  local slope="$1" first="$2" last="$3" kind="$4"
  local diff=$((last - first))
  if awk "BEGIN{exit !($slope > 0.05)}"; then
    if [ "$kind" = "delay" ]; then echo "↓ 变差"; else echo "↑ 变好"; fi
    return
  fi
  if awk "BEGIN{exit !($slope < -0.05)}"; then
    if [ "$kind" = "delay" ]; then echo "↑ 变好"; else echo "↓ 变差"; fi
    return
  fi
  # 斜率不显著：首尾对比（0 差值落 "→ 平稳"）
  if [ "$kind" = "delay" ]; then
    if   [ "$diff" -gt 0 ]; then echo "↘ 变差"
    elif [ "$diff" -lt 0 ]; then echo "↗ 变好"
    else echo "→ 平稳"; fi
  else
    if   [ "$diff" -gt 0 ]; then echo "↗ 微升"
    elif [ "$diff" -lt 0 ]; then echo "↘ 微降"
    else echo "→ 平稳"; fi
  fi
}
