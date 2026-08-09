#!/bin/bash
# ============================================================================
# DNS精简版测试脚本
# 功能：9项基础DNS测试，支持自定义DNS参数，默认使用云南电信DNS
# 用法：同full.sh
# ============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/lib/core.sh"
# 异常退出时清理并行临时目录
trap 'rm -rf "$PARR_TMPDIR"' EXIT INT TERM

# 处理参数
# 支持传入索引参数指定测试第几个DNS，避免超时
# 用法：bash lite.sh [DNS1] [DNS2] ... [索引]
if [ $# -ge 1 ]; then
  # 检查最后一个参数是否是数字（索引），仅当参数≥2个时才判定，避免纯数字DNS被误判
  last_arg="${!#}"
  if [ $# -ge 2 ] && [[ "$last_arg" =~ ^[0-9]+$ ]]; then
    IDX=$last_arg
    # 去掉最后一个参数（索引）
    DNS_ADDR=("${@:1:$#-1}")
    [ ${#DNS_ADDR[@]} -eq 0 ] && DNS_ADDR=("${DEFAULT_DNS_ADDR[@]}")
  else
    DNS_ADDR=("$@")
    IDX=-1  # -1表示跑所有
  fi
  DNS_NAME=()
  for addr in "${DNS_ADDR[@]}"; do
    DNS_NAME+=("自定义DNS(${addr})")
  done
else
  DNS_ADDR=("${DEFAULT_DNS_ADDR[@]}")
  DNS_NAME=("${DEFAULT_DNS_NAME[@]}")
  IDX=-1
fi

print_header "DNS 基础测试 (精简版 v2026.08)"
START_TIME=$(date +%s)
echo "待测DNS数量: ${#DNS_ADDR[@]} 个"
echo "DNS列表:"
for idx in "${!DNS_ADDR[@]}"; do
  printf "  %d. %s [%s]\n" $((idx+1)) "${DNS_NAME[$idx]}" "${DNS_ADDR[$idx]}"
done
echo ""

if [ $IDX -ge 0 ]; then
  # 测试指定索引的DNS
  run_lite_test "${DNS_ADDR[$IDX]}" "${DNS_NAME[$IDX]}"
else
  # 测试所有DNS
  for idx in "${!DNS_ADDR[@]}"; do
    if run_lite_test "${DNS_ADDR[$idx]}" "${DNS_NAME[$idx]}"; then
      # 最后一个不休息
      [ $idx -lt $((${#DNS_ADDR[@]} - 1)) ] && sleep 3
    fi
  done
fi

echo ""
elapsed=$(( $(date +%s) - START_TIME ))
echo "  ⏱️  总耗时: $((elapsed / 60))分 $((elapsed % 60))秒"
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                       基础测试完成 ✓                                      ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
