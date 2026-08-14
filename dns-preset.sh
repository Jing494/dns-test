#!/bin/bash
# ============================================================================
# DNS预设快捷测试脚本
# 功能：一键测试指定预设DNS组（云南电信/阿里/腾讯/全部）
# 用法：
#   bash dns-preset.sh                     # 默认云南电信+lite
#   bash dns-preset.sh ali                 # 阿里云+lite
#   bash dns-preset.sh tencent             # 腾讯DNSPod+lite
#   bash dns-preset.sh yunnan full         # 云南电信+完整版
#   bash dns-preset.sh ali lite 0          # 阿里第1个DNS
#   bash dns-preset.sh all lite            # 全部预设（可能较慢）
# ============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
cd "$SCRIPT_DIR" || exit 1
source "${SCRIPT_DIR}/lib/core.sh"

case "$1" in
  -h|--help|help)
    echo "用法: bash dns-preset.sh [预设组] [lite|full] [索引]"
    echo "  预设组: yunnan(默认) / ali / tencent / all"
    echo "  版本:   lite(默认) / full"
    echo "  索引:   只测第N个DNS（0=第1个）"
    echo "  示例:"
    echo "    bash dns-preset.sh                     # 云南电信+lite"
    echo "    bash dns-preset.sh ali                 # 阿里云+lite"
    echo "    bash dns-preset.sh tencent             # 腾讯DNSPod+lite"
    echo "    bash dns-preset.sh yunnan full         # 云南电信+完整版"
    echo "    bash dns-preset.sh ali lite 0          # 阿里第1个DNS"
    echo "    bash dns-preset.sh all lite            # 全部预设（可能较慢）"
    exit 0
    ;;
  --version)
    source "${SCRIPT_DIR}/lib/version.sh"
    echo "dns-test ${PROJECT_VERSION} (${PROJECT_RELEASE})"
    exit 0
    ;;
esac

PRESET="${1:-yunnan}"
VERSION="${2:-lite}"
IDX="${3:--1}"

# 自定义预设优先（环境变量 PRESET_DNS_CSV，逗号分隔）
if [ -n "$PRESET_DNS_CSV" ]; then
  IFS=',' read -ra DNS_ADDR <<< "$PRESET_DNS_CSV"
  DNS_NAME=()
  for _a in "${DNS_ADDR[@]}"; do DNS_NAME+=("自定义DNS(${_a})"); done
  LABEL="自定义（${#DNS_ADDR[@]}个）"
else
# 解析预设
case $PRESET in
  yunnan|yn|1)
    DNS_ADDR=("${DEFAULT_DNS_ADDR[@]}")
    DNS_NAME=("${DEFAULT_DNS_NAME[@]}")
    LABEL="云南电信（${#DNS_ADDR[@]}个）"
    ;;
  ali|alibaba|2)
    DNS_ADDR=("${ALI_DNS_ADDR[@]}")
    DNS_NAME=("${ALI_DNS_NAME[@]}")
    LABEL="阿里云公共DNS（${#DNS_ADDR[@]}个）"
    ;;
  tencent|tx|dnspod|3)
    DNS_ADDR=("${TENCENT_DNS_ADDR[@]}")
    DNS_NAME=("${TENCENT_DNS_NAME[@]}")
    LABEL="腾讯DNSPod（${#DNS_ADDR[@]}个）"
    ;;
  all|4)
    DNS_ADDR=("${DEFAULT_DNS_ADDR[@]}" "${ALI_DNS_ADDR[@]}" "${TENCENT_DNS_ADDR[@]}")
    DNS_NAME=("${DEFAULT_DNS_NAME[@]}" "${ALI_DNS_NAME[@]}" "${TENCENT_DNS_NAME[@]}")
    LABEL="全部（${#DNS_ADDR[@]}个：云南电信+阿里+腾讯）"
    ;;
  *)
    echo "❌ 未知预设: $PRESET"
    echo "可选: yunnan(1) / ali(2) / tencent(3) / all(4)，或用环境变量 PRESET_DNS_CSV 自定义"
    exit 1
    ;;
esac
fi

if [ "$VERSION" != "lite" ] && [ "$VERSION" != "full" ]; then
  echo "❌ 未知版本: $VERSION (可选: lite / full)"
  exit 1
fi

# DNS地址格式校验（防命令注入/误传）
for _a in "${DNS_ADDR[@]}"; do
  valid_dns_addr "$_a" || { echo "❌ 非法DNS地址: $_a（仅支持IPv4/IPv6格式）"; exit 1; }
done

echo "🎯 预设: $LABEL | 版本: $VERSION"
print_env_info

# 指定索引则只测第N个（避免超时）
if [ "$IDX" -ge 0 ] 2>/dev/null && [ "$IDX" -lt "${#DNS_ADDR[@]}" ]; then
  echo "只测试第 $((IDX+1)) 个: ${DNS_NAME[$IDX]} [${DNS_ADDR[$IDX]}]"
  echo ""
  if [ "$VERSION" = "full" ]; then
    bash full.sh "${DNS_ADDR[$IDX]}" 0
  else
    bash lite.sh "${DNS_ADDR[$IDX]}" 0
  fi
elif [ ${#DNS_ADDR[@]} -gt 2 ]; then
  echo "⚠️  ${#DNS_ADDR[@]}个DNS串行跑可能较久，建议加索引参数：bash dns-preset.sh $PRESET $VERSION 0"
  echo ""
  if [ "$VERSION" = "full" ]; then
    bash full.sh "${DNS_ADDR[@]}"
  else
    bash lite.sh "${DNS_ADDR[@]}"
  fi
else
  echo ""
  if [ "$VERSION" = "full" ]; then
    bash full.sh "${DNS_ADDR[@]}"
  else
    bash lite.sh "${DNS_ADDR[@]}"
  fi
fi
