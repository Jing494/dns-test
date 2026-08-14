#!/bin/bash
# ============================================================================
# DNS测试统一入口脚本
# 功能：智能引导用户选择测试类型，支持自定义DNS参数
# 用法：
#   bash dns-test.sh                     # 默认测试运营商DNS
#   bash dns-test.sh 8.8.8.8             # 测试自定义DNS
#   bash dns-test.sh 8.8.8.8 114.114.114.114  # 测试多个自定义DNS
# ============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
cd "$SCRIPT_DIR" || exit 1
# 引入核心库（获取默认DNS等公共变量）
source "${SCRIPT_DIR}/lib/core.sh"

# 版本号输出（统一入口约定）
if [ "$1" = "--version" ]; then
  echo "dns-test ${PROJECT_VERSION} (${PROJECT_RELEASE})"
  exit 0
fi

# 处理DNS参数
DNS_LIST=()
if [ $# -ge 1 ]; then
  DNS_LIST=("$@")
  DNS_DISPLAY="自定义DNS: $*"
else
  DNS_LIST=()
  DNS_DISPLAY="默认运营商DNS 4个"
fi

# 检查是否支持终端交互
if [ -t 0 ]; then
  echo "========================================"
  echo "  🌐 DNS测试工具集"
  echo "========================================"
  print_env_info
  echo ""

  # 无参数时先选择DNS组
  if [ $# -lt 1 ]; then
    echo "请选择测试DNS组："
    echo "1. 默认运营商DNS（可配置）"
    echo "2. 阿里云公共DNS"
    echo "3. 腾讯DNSPod"
    echo "4. 全部（默认+阿里+腾讯，串行会很久，建议配合索引参数）"
    read -r -t 30 -p "请输入选项(1-4): " dns_group
    echo ""
    case $dns_group in
      2) DNS_LIST=("${ALI_DNS_ADDR[@]}"); DNS_DISPLAY="阿里云公共DNS（4个）" ;;
      3) DNS_LIST=("${TENCENT_DNS_ADDR[@]}"); DNS_DISPLAY="腾讯DNSPod（3个）" ;;
      4) DNS_LIST=("${DEFAULT_DNS_ADDR[@]}" "${ALI_DNS_ADDR[@]}" "${TENCENT_DNS_ADDR[@]}"); DNS_DISPLAY="全部（11个DNS）" ;;
      *) DNS_LIST=(); DNS_DISPLAY="默认运营商DNS 4个" ;;
    esac
  fi

  echo "待测DNS: $DNS_DISPLAY"
  [ ${#DNS_LIST[@]} -ge 1 ] && echo "数量: ${#DNS_LIST[@]} 个"
  echo ""

  # 选择测试类型
  echo "请选择测试类型："
  echo "1. 基础测试（完整版/精简版，覆盖通用DNS功能）"
  echo "2. 专项测试（VoWiFi/端口连通性/反向解析等专业测试）"
  read -r -t 30 -p "请输入选项(1/2): " test_type
  echo ""

  case $test_type in
    1)
      # 基础测试：直接问完整版还是精简版
      echo "请选择基础测试版本："
      echo "1. 精简版（10项基础测试，约9秒/DNS）"
      echo "2. 完整版（16项全面测试，约10秒/DNS）"
      read -r -t 30 -p "请输入选项(1/2): " version
      echo ""

      # 判断DNS数量，超过1个询问是否指定索引
      if [ ${#DNS_LIST[@]} -gt 1 ]; then
        echo "检测到你要测试 ${#DNS_LIST[@]} 个DNS，完整跑完所有DNS可能会超时"
        echo "1. 测试所有DNS（可能会超时）"
        echo "2. 指定测试某一个DNS（推荐）"
        read -r -t 30 -p "请选择(1/2): " dns_select
        echo ""
        if [ "$dns_select" = "2" ]; then
          echo "可测试的DNS列表："
          for idx in "${!DNS_LIST[@]}"; do
            printf "  %d. %s\n" $((idx+1)) "${DNS_LIST[$idx]}"
          done
          read -r -t 30 -p "请输入要测试的DNS编号(1-${#DNS_LIST[@]}): " dns_idx
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
      # 专项测试：插件注册表驱动（lib/plugins.sh + tools/manifest.sh），新增专项自动出现
      source "${SCRIPT_DIR}/lib/plugins.sh"
      N_PLUGIN=${#PLUGIN_ITEMS[@]}
      CMP_N=$((N_PLUGIN+1)); TRD_N=$((N_PLUGIN+2)); VER_N=$((N_PLUGIN+3))
      echo "可选专项测试（插件注册表驱动，新增专项自动出现）:"
      plugin_list
      echo "$CMP_N. 多DNS对比（compare.sh，横向对比评分/延迟，可生成HTML报告）"
      echo "$TRD_N. DNS趋势洞察（trends.sh，聚合历史compare数据看趋势，需先积累）"
      echo "$VER_N. 一键全面验证（verify.sh，语法+单测+冒烟+对比+趋势全自检，约5分钟；--strict 强制 shellcheck）"
      read -r -t 30 -p "请输入选项(1-$VER_N): " professional_test
      echo ""
      case $professional_test in
        ""|*[!0-9]*)
          echo "无效选项，返回主菜单..."
          ;;
        *)
          if [ "$professional_test" -le "$N_PLUGIN" ]; then
            # 专项插件：DNS 数量保护（专项脚本收多 DNS 会慢/超时，最多4个）
            if [ ${#DNS_LIST[@]} -gt 4 ]; then
              echo "⚠️  ${#DNS_LIST[@]}个DNS跑专项会慢，本次只取前4个"
              DNS_LIST=("${DNS_LIST[@]:0:4}")
            fi
            plugin_run "$professional_test" "${DNS_LIST[@]}"
          elif [ "$professional_test" = "$CMP_N" ]; then
            echo "开始多DNS对比（compare.sh，lite精简版53项/DNS，并行）..."
            if [ ${#DNS_LIST[@]} -ge 2 ]; then
              echo "  使用当前DNS列表: ${DNS_LIST[*]}"
              bash compare.sh "${DNS_LIST[@]}"
            else
              echo "  对比至少需要2个DNS（当前: ${DNS_LIST[*]:-无}）"
              read -r -t 30 -p "  请输入要对比的DNS（逗号分隔，回车默认 223.5.5.5,119.29.29.29）: " cmp_input
              if [ -n "$cmp_input" ]; then
                # 逗号/空格分隔都兼容（read -ra 防分词问题）
                IFS=", " read -ra cmp_list <<< "$cmp_input"
                bash compare.sh "${cmp_list[@]}"
              else
                echo "  未输入，默认对比 223.5.5.5 与 119.29.29.29"
                bash compare.sh 223.5.5.5 119.29.29.29
              fi
            fi
          elif [ "$professional_test" = "$TRD_N" ]; then
            echo "开始DNS趋势洞察（trends.sh，聚合 results/compare-*.json）..."
            echo "  提示: 需先积累compare数据（跑过compare即自动保存）"
            bash trends.sh --html
          elif [ "$professional_test" = "$VER_N" ]; then
            echo "开始一键全面验证（verify.sh，含语法/单测/冒烟/compare/trends/专项）..."
            echo "  提示: 网络项（compare/专项）在海外/受限网络可能超时，会友好提示"
            bash verify.sh
          else
            echo "无效选项，返回主菜单..."
          fi
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
  if [ ${#DNS_LIST[@]} -ge 2 ]; then
    echo "  💡 检测到 ${#DNS_LIST[@]} 个DNS：横向对比可用 bash compare.sh ${DNS_LIST[*]}"
  fi
  local_dns="${DNS_LIST[0]:-${DEFAULT_DNS_ADDR[0]}}"
  bash lite.sh "$local_dns"
fi
