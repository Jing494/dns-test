#!/bin/bash
# ============================================================================
# DNS精简版测试脚本
# 功能：10项基础DNS测试，支持自定义DNS参数，默认使用云南电信DNS
# 用法：同full.sh
# ============================================================================

case "$1" in
  -h|--help|help)
    echo "用法: bash lite.sh [DNS...] [索引]"
    echo "  DNS列表: 一个或多个DNS地址（默认云南电信 4 个 DNS，v4/v6 各 2 个），支持v4/v6混合"
    echo "  索引:    只测第N个DNS（0=第1个），避免多DNS时超时"
    echo "  示例:"
    echo "    bash lite.sh                          # 默认DNS精简测试"
    echo "    bash lite.sh 223.5.5.5 0              # 只测阿里云第1个DNS"
    echo "    bash lite.sh 240e:52:4800::8888 8.8.8.8  # 混合v4/v6"
    echo "  环境变量: SAVE_LOG=1 保存日志到 results/；DEFAULT_DNS_CSV=... 自定义默认DNS组"
    exit 0
    ;;
esac

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/lib/core.sh"
# 异常退出时统一清理：并行临时目录 + 各测试函数注册的临时目录（TMPDIR_LIST 由 core.sh 维护）
trap 'rm -rf "$PARR_TMPDIR" "${TMPDIR_LIST[@]}"' EXIT INT TERM

# 自动保存日志（SAVE_LOG=1 时写入 results/，Linux tee到终端+文件 / macOS写文件）
if [ -n "$SAVE_LOG" ]; then
  mkdir -p "${SCRIPT_DIR}/results"
  LOG_FILE="${SCRIPT_DIR}/results/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S).log"
  if [ "$(uname)" = "Darwin" ]; then
    exec > "$LOG_FILE" 2>&1
  else
    exec > >(tee "$LOG_FILE") 2>&1
  fi
  echo "📄 日志保存: $LOG_FILE"
fi

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
    # 索引越界校验：超出范围则忽略索引，改为测试全部
    if [ "$IDX" -ge "${#DNS_ADDR[@]}" ]; then
      echo "⚠️  索引 $IDX 超出范围（共 ${#DNS_ADDR[@]} 个DNS），已忽略索引"
      IDX=-1
    fi
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

# DNS地址格式校验（防命令注入/误传）
for _a in "${DNS_ADDR[@]}"; do
  valid_dns_addr "$_a" || { echo "❌ 非法DNS地址: $_a（仅支持IPv4/IPv6格式）"; exit 1; }
done

print_header "DNS 基础测试 (精简版 ${PROJECT_VERSION})"
START_TIME=$(date +%s)
print_env_info
echo "待测DNS数量: ${#DNS_ADDR[@]} 个"
echo "DNS列表:"
for idx in "${!DNS_ADDR[@]}"; do
  printf "  %d. %s [%s]\n" $((idx+1)) "${DNS_NAME[$idx]}" "${DNS_ADDR[$idx]}"
done
echo ""

tested=0
if [ $IDX -ge 0 ]; then
  # 测试指定索引的DNS
  run_lite_test "${DNS_ADDR[$IDX]}" "${DNS_NAME[$IDX]}" && tested=1
else
  # 测试所有DNS
  for idx in "${!DNS_ADDR[@]}"; do
    if run_lite_test "${DNS_ADDR[$idx]}" "${DNS_NAME[$idx]}"; then
      tested=$((tested + 1))
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

# 退出码约定：0=测试完成(至少1个DNS测过)；2=所有DNS不可达
[ "$tested" -gt 0 ] && { echo ""
  echo "  💡 想对比多个DNS？ → bash compare.sh DNS1 DNS2   （横向对比评分/延迟，可生成HTML报告）"
  echo "  💡 想看历史趋势？   → bash trends.sh --html      （先积累 compare 数据，长期观察）"
  exit 0; } || exit 2
