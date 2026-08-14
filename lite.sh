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
  --version)
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/version.sh"
    echo "dns-test ${PROJECT_VERSION} (${PROJECT_RELEASE})"
    exit 0
    ;;
esac

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/lib/core.sh"
# 异常退出时统一清理：并行临时目录 + 各测试函数注册的临时目录（TMPDIR_LIST 由 core.sh 维护）
# ${VAR:+...} 空值时展开为空串参数仍会让 macOS 的 rm 报错，改用条件判断（审阅#1）
trap '[ -n "${PARR_TMPDIR:-}" ] && rm -rf "$PARR_TMPDIR"; [ "${#TMPDIR_LIST[@]}" -gt 0 ] && rm -rf "${TMPDIR_LIST[@]}"' EXIT INT TERM

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

# 处理参数 + 打印列表 + 逐个测试（公共逻辑在 core.sh：parse_dns_args/print_dns_list/run_all_dns_tests/finish_dns_tests）
# 支持 [DNS...] [索引]，索引越界自动忽略改测全部；DNS 地址格式校验在 print_dns_list 内
parse_dns_args "$@"
print_dns_list "DNS 基础测试 (精简版 ${PROJECT_VERSION})"

run_all_dns_tests run_lite_test

finish_dns_tests
