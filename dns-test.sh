#!/bin/bash
# ============================================================================
# DNS测试统一入口脚本
# 功能：智能引导用户选择测试类型，支持自定义DNS参数
# 用法：
#   bash dns-test.sh                     # 默认测试云南电信DNS
#   bash dns-test.sh 8.8.8.8             # 测试自定义DNS
#   bash dns-test.sh 8.8.8.8 114.114.114.114  # 测试多个自定义DNS
# ============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"
# 引入核心库（获取默认DNS等公共变量）
source "${SCRIPT_DIR}/lib/core.sh"

# 处理DNS参数
DNS_LIST=()
if [ $# -ge 1 ]; then
  DNS_LIST=("$@")
  DNS_DISPLAY="自定义DNS: $*"
else
  DNS_LIST=()
  DNS_DISPLAY="默认云南电信4个DNS"
fi

# 检查是否支持终端交互
if [ -t 0 ]; then
  echo "========================================"
  echo "  🌐 DNS测试工具集"
  echo "========================================"

  # 无参数时先选择DNS组
  if [ $# -lt 1 ]; then
    echo "请选择测试DNS组："
    echo "1. 云南电信（默认）"
    echo "2. 阿里云公共DNS"
    echo "3. 腾讯DNSPod"
    echo "4. 全部（云南电信+阿里+腾讯，串行会很久，建议配合索引参数）"
    read -t 30 -p "请输入选项(1-4): " dns_group
    echo ""
    case $dns_group in
      2) DNS_LIST=("${ALI_DNS_ADDR[@]}"); DNS_DISPLAY="阿里云公共DNS（4个）" ;;
      3) DNS_LIST=("${TENCENT_DNS_ADDR[@]}"); DNS_DISPLAY="腾讯DNSPod（3个）" ;;
      4) DNS_LIST=("${DEFAULT_DNS_ADDR[@]}" "${ALI_DNS_ADDR[@]}" "${TENCENT_DNS_ADDR[@]}"); DNS_DISPLAY="全部（11个DNS）" ;;
      *) DNS_LIST=(); DNS_DISPLAY="默认云南电信4个DNS" ;;
    esac
  fi

  echo "待测DNS: $DNS_DISPLAY"
  [ ${#DNS_LIST[@]} -ge 1 ] && echo "数量: ${#DNS_LIST[@]} 个"
  echo ""

  # 选择测试类型
  echo "请选择测试类型："
  echo "1. 基础测试（完整版/精简版，覆盖通用DNS功能）"
  echo "2. 专项测试（VoWiFi/端口连通性/反向解析等专业测试）"
  read -t 30 -p "请输入选项(1/2): " test_type
  echo ""

  case $test_type in
    1)
      # 基础测试：直接问完整版还是精简版
      echo "请选择基础测试版本："
      echo "1. 精简版（9项基础测试，约3-5分钟）"
      echo "2. 完整版（15项全面测试，约8-10分钟）"
      read -t 30 -p "请输入选项(1/2): " version
      echo ""

      # 判断DNS数量，超过1个询问是否指定索引
      if [ ${#DNS_LIST[@]} -gt 1 ]; then
        echo "检测到你要测试 ${#DNS_LIST[@]} 个DNS，完整跑完所有DNS可能会超时"
        echo "1. 测试所有DNS（可能会超时）"
        echo "2. 指定测试某一个DNS（推荐）"
        read -t 30 -p "请选择(1/2): " dns_select
        echo ""
        if [ "$dns_select" = "2" ]; then
          echo "可测试的DNS列表："
          for idx in "${!DNS_LIST[@]}"; do
            printf "  %d. %s\n" $((idx+1)) "${DNS_LIST[$idx]}"
          done
          read -t 30 -p "请输入要测试的DNS编号(1-${#DNS_LIST[@]}): " dns_idx
          echo ""
          # 转换为从0开始的索引
          dns_idx=$((dns_idx-1))
          if [ $dns_idx -ge 0 ] && [ $dns_idx -lt ${#DNS_LIST[@]} ]; then
            DNS_LIST=("${DNS_LIST[$dns_idx]}")
          else
            echo "无效编号，默认测试第一个DNS"
            DNS_LIST=("${DNS_LIST[0]}")
          fi
        fi
      fi

      case $version in
        1)
          echo "开始精简版测试..."
          if [ ${#DNS_LIST[@]} -gt 4 ]; then
            echo "⚠️  ${#DNS_LIST[@]}个DNS跑精简版也会超时，本次只测第1个: ${DNS_LIST[0]}"
            bash lite.sh "${DNS_LIST[0]}" 0
          elif [ ${#DNS_LIST[@]} -ge 1 ]; then
            bash lite.sh "${DNS_LIST[@]}"
          else
            bash lite.sh
          fi
          ;;
        2)
          echo "开始完整版测试..."
          if [ ${#DNS_LIST[@]} -gt 4 ]; then
            echo "⚠️  完整版测试 ${#DNS_LIST[@]} 个DNS必然超时，本次只测第1个: ${DNS_LIST[0]}"
            bash full.sh "${DNS_LIST[0]}" 0
          elif [ ${#DNS_LIST[@]} -ge 1 ]; then
            bash full.sh "${DNS_LIST[@]}"
          else
            bash full.sh
          fi
          ;;
        *)
          echo "无效选项，为避免超时，默认运行精简版测试（仅第1个DNS）..."
          bash lite.sh "${DNS_LIST[0]:-${DEFAULT_DNS_ADDR[0]}}"
          ;;
      esac
      ;;
    2)
      # 专项测试：列出选项让用户选
      echo "可选专项测试："
      echo "1. VoWiFi域名全解析测试（默认测试云南电信/联通等公共DNS，或传入自定义DNS）"
      echo "2. VoWiFi多DNS交叉验证（对比多个DNS的VoWiFi解析结果）"
      echo "3. 路由器DNS转发测试（测试路由器DNS是否转发到指定DNS）"
      echo "4. 端口连通性测试（测试ePDG/VoWiFi相关端口是否开放）"
      echo "5. 通用示例脚本（基础查询/多DNS对比/DNS64检测/反向解析）"
      read -t 30 -p "请输入选项(1-5): " professional_test
      echo ""
      case $professional_test in
        1)
          echo "开始VoWiFi域名全解析测试..."
          if [ $# -ge 1 ]; then
            perl tools/vowifi/01_resolve_vowifi.pl "${DNS_LIST[@]}"
          else
            perl tools/vowifi/01_resolve_vowifi.pl
          fi
          ;;
        2)
          echo "开始VoWiFi多DNS交叉验证..."
          if [ $# -ge 1 ]; then
            perl tools/vowifi/02_vowifi_verify.pl "${DNS_LIST[@]}"
          else
            perl tools/vowifi/02_vowifi_verify.pl
          fi
          ;;
        3)
          echo "开始路由器DNS转发测试（对比云南电信省级DNS）..."
          echo "提示: 传入的参数是【路由器网关IP】（如 192.168.1.1），不是DNS服务器地址"
          if [ $# -ge 1 ]; then
            perl tools/vowifi/03_test_router_dns.pl "${DNS_LIST[@]}"
          else
            perl tools/vowifi/03_test_router_dns.pl
          fi
          ;;
        4)
          echo "开始端口连通性测试（使用默认ePDG目标）..."
          echo "提示: 自定义目标请直接运行: perl tools/network/01_port_test.pl <IP> <端口> <tcp|udp>"
          perl tools/network/01_port_test.pl
          ;;
        5)
          echo "开始通用示例脚本演示..."
          echo "1. 基础DNS查询"
          echo "2. 多DNS对比测试"
          echo "3. DNS64支持检测"
          echo "4. 反向DNS解析"
          read -t 30 -p "请输入要运行的示例编号(1-4): " example_id
          echo ""
          case $example_id in
            1)
              if [ $# -ge 1 ]; then
                perl examples/01_dns_query.pl "${DNS_LIST[@]}"
              else
                perl examples/01_dns_query.pl
              fi
              ;;
            2)
              if [ $# -ge 1 ]; then
                perl examples/02_multi_dns_compare.pl "${DNS_LIST[@]}"
              else
                perl examples/02_multi_dns_compare.pl
              fi
              ;;
            3)
              if [ $# -ge 1 ]; then
                perl examples/03_dns64_check.pl "${DNS_LIST[@]}"
              else
                perl examples/03_dns64_check.pl
              fi
              ;;
            4)
              if [ $# -ge 1 ]; then
                perl examples/04_reverse_dns.pl "${DNS_LIST[@]}"
              else
                perl examples/04_reverse_dns.pl
              fi
              ;;
            *)
              echo "无效选项，运行所有示例..."
              echo ""
              echo "=== 1. 基础DNS查询 ==="
              if [ $# -ge 1 ]; then perl examples/01_dns_query.pl "${DNS_LIST[@]}"; else perl examples/01_dns_query.pl; fi
              echo ""
              echo "=== 2. 多DNS对比测试 ==="
              if [ $# -ge 1 ]; then perl examples/02_multi_dns_compare.pl "${DNS_LIST[@]}"; else perl examples/02_multi_dns_compare.pl; fi
              echo ""
              echo "=== 3. DNS64支持检测 ==="
              if [ $# -ge 1 ]; then perl examples/03_dns64_check.pl "${DNS_LIST[@]}"; else perl examples/03_dns64_check.pl; fi
              echo ""
              echo "=== 4. 反向DNS解析 ==="
              if [ $# -ge 1 ]; then perl examples/04_reverse_dns.pl "${DNS_LIST[@]}"; else perl examples/04_reverse_dns.pl; fi
              ;;
          esac
          ;;
        *)
          echo "无效选项，返回主菜单..."
          ;;
      esac
      ;;
    *)
      echo "无效选项，为避免超时，默认运行精简版基础测试（仅第1个DNS）..."
      bash lite.sh "${DNS_LIST[0]:-${DEFAULT_DNS_ADDR[0]}}"
      ;;
  esac
else
  # 非交互模式：为避免超时，默认只跑精简版+第1个DNS
  echo "非交互模式，为避免超时，默认运行精简版测试（仅第1个DNS）..."
  source "${SCRIPT_DIR}/lib/core.sh"
  local_dns="${DNS_LIST[0]:-${DEFAULT_DNS_ADDR[0]}}"
  bash lite.sh "$local_dns"
fi
