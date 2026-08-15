#!/bin/bash
# ============================================================================
# DNS测试统一入口脚本
# 功能：智能引导用户选择测试类型，支持自定义DNS参数；交互模式带主菜单循环
# 用法：
#   bash dns-test.sh                     # 默认测试运营商DNS
#   bash dns-test.sh 8.8.8.8             # 测试自定义DNS
#   bash dns-test.sh 8.8.8.8 114.114.114.114  # 测试多个自定义DNS
# 交互说明：测完自动返回主菜单，可继续测试或输入 0 退出；全程 30 秒输入超时保护
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
DNS_FROM_ARG=0
if [ $# -ge 1 ]; then
  DNS_LIST=("$@")
  DNS_DISPLAY="自定义DNS: $*"
  DNS_FROM_ARG=1
else
  DNS_LIST=()
  DNS_DISPLAY="默认运营商DNS 4个"
fi

# 非交互模式（无终端）：为避免超时，默认只跑精简版+第1个DNS，一次跑完退出
if [ ! -t 0 ]; then
  echo "非交互模式，为避免超时，默认运行精简版测试（仅第1个DNS）..."
  if [ ${#DNS_LIST[@]} -ge 2 ]; then
    echo "  💡 检测到 ${#DNS_LIST[@]} 个DNS：横向对比可用 bash compare.sh ${DNS_LIST[*]}"
  fi
  local_dns="${DNS_LIST[0]:-${DEFAULT_DNS_ADDR[0]}}"
  bash lite.sh "$local_dns"
  exit $?
fi

# ============================ 交互模式（主菜单循环） ============================

# 读取用户输入；返回 read 退出码（超时/EOF 非0，由调用方决定后续）
prompt() {
  read -r -t 30 -p "$2" "$1"
}

# 选择DNS组（无命令行参数时可用；0 返回主菜单不改动当前DNS）
select_dns_group() {
  echo "请选择测试DNS组："
  echo "1. 默认运营商DNS（可配置）"
  echo "2. 阿里云公共DNS"
  echo "3. 腾讯DNSPod"
  echo "4. 全部（默认+阿里+腾讯）"
  echo "0. 返回主菜单（不改动当前DNS）"
  if ! prompt dns_group "请输入选项(0-4): "; then
    echo ""
    echo "⏰ 等待输入超时，返回主菜单..."
    return 0
  fi
  echo ""
  case $dns_group in
    0) return 0 ;;
    2) DNS_LIST=("${ALI_DNS_ADDR[@]}"); DNS_DISPLAY="阿里云公共DNS（4个）" ;;
    3) DNS_LIST=("${TENCENT_DNS_ADDR[@]}"); DNS_DISPLAY="腾讯DNSPod（3个）" ;;
    4) DNS_LIST=("${DEFAULT_DNS_ADDR[@]}" "${ALI_DNS_ADDR[@]}" "${TENCENT_DNS_ADDR[@]}"); DNS_DISPLAY="全部（11个DNS）" ;;
    *) DNS_LIST=(); DNS_DISPLAY="默认运营商DNS 4个" ;;
  esac
  echo "已切换 DNS 组: $DNS_DISPLAY"
}

# 基础测试（精简版/完整版）
run_basic() {
  echo "请选择基础测试版本："
  echo "1. 精简版（10项基础测试，约9秒/DNS）"
  echo "2. 完整版（16项全面测试，约10秒/DNS）"
  echo "0. 返回主菜单"
  if ! prompt version "请输入选项(0/1/2): "; then
    echo ""
    echo "⏰ 等待输入超时，返回主菜单..."
    return 0
  fi
  echo ""
  case $version in
    0) return 0 ;;
    1|2)
      local script=lite.sh
      if [ "$version" = "1" ]; then
        echo "开始精简版测试..."
      else
        script=full.sh
        echo "开始完整版测试..."
      fi

      # 多DNS时询问是否指定某一个
      if [ ${#DNS_LIST[@]} -gt 1 ]; then
        echo "当前 ${#DNS_LIST[@]} 个DNS，全部跑完较耗时："
        echo "1. 全部测试（超过4个则只测第1个，防超时）"
        echo "2. 指定测试某一个DNS（推荐）"
        echo "0. 返回主菜单"
        if ! prompt dns_select "请选择(0/1/2): "; then
          echo ""
          echo "⏰ 等待输入超时，返回主菜单..."
          return 0
        fi
        echo ""
        case $dns_select in
          0) return 0 ;;
          2)
            echo "可测试的DNS列表："
            for idx in "${!DNS_LIST[@]}"; do
              printf "  %d. %s\n" $((idx+1)) "${DNS_LIST[$idx]}"
            done
            if ! prompt dns_idx "请输入要测试的DNS编号(1-${#DNS_LIST[@]}): "; then
              echo ""
              echo "⏰ 等待输入超时，返回主菜单..."
              return 0
            fi
            echo ""
            # 转换为从0开始的索引
            dns_idx=$((dns_idx-1))
            if [ $dns_idx -ge 0 ] && [ $dns_idx -lt ${#DNS_LIST[@]} ]; then
              DNS_LIST=("${DNS_LIST[$dns_idx]}")
              DNS_DISPLAY="指定DNS: ${DNS_LIST[0]}"
            else
              echo "无效编号，默认测试第一个DNS"
              DNS_LIST=("${DNS_LIST[0]}")
              DNS_DISPLAY="指定DNS: ${DNS_LIST[0]}"
            fi
            ;;
          *) : ;;  # 1 或其它 → 全部
        esac
      fi

      # 数量保护：>4 个只测第1个，防超时
      if [ ${#DNS_LIST[@]} -gt 4 ]; then
        echo "⚠️  ${#DNS_LIST[@]}个DNS跑测试会超时，本次只测第1个: ${DNS_LIST[0]}"
        bash "$script" "${DNS_LIST[0]}" 0
      elif [ ${#DNS_LIST[@]} -ge 1 ]; then
        bash "$script" "${DNS_LIST[@]}"
      else
        bash "$script"
      fi
      ;;
    *)
      echo "无效选项，返回主菜单..."
      ;;
  esac
}

# 专项测试（插件注册表驱动）
run_prof() {
  source "${SCRIPT_DIR}/lib/plugins.sh"
  local n_plugin=${#PLUGIN_ITEMS[@]}
  local cmp_n=$((n_plugin+1)) trd_n=$((n_plugin+2)) ver_n=$((n_plugin+3))
  echo "可选专项测试（插件注册表驱动，新增专项自动出现）:"
  plugin_list
  echo "$cmp_n. 多DNS对比（compare.sh，横向对比评分/延迟，可生成HTML报告）"
  echo "$trd_n. DNS趋势洞察（trends.sh，聚合历史compare数据看趋势，需先积累）"
  echo "$ver_n. 一键全面验证（verify.sh，语法+单测+冒烟+对比+趋势全自检，约5分钟；--strict 强制 shellcheck）"
  echo "0. 返回主菜单"
  if ! prompt professional_test "请输入选项(0-$ver_n): "; then
    echo ""
    echo "⏰ 等待输入超时，返回主菜单..."
    return 0
  fi
  echo ""
  case $professional_test in
    0) return 0 ;;
    ""|*[!0-9]*) echo "无效选项，返回主菜单..." ;;
    *)
      if [ "$professional_test" -le "$n_plugin" ]; then
        # 专项插件：DNS 数量保护（专项脚本收多 DNS 会慢/超时，最多4个）
        if [ ${#DNS_LIST[@]} -gt 4 ]; then
          echo "⚠️  ${#DNS_LIST[@]}个DNS跑专项会慢，本次只取前4个"
          DNS_LIST=("${DNS_LIST[@]:0:4}")
          DNS_DISPLAY="${DNS_LIST[0]} 等${#DNS_LIST[@]}个（已截断）"
        fi
        plugin_run "$professional_test" "${DNS_LIST[@]}"
      elif [ "$professional_test" = "$cmp_n" ]; then
        echo "开始多DNS对比（compare.sh，lite精简版53项/DNS，并行）..."
        if [ ${#DNS_LIST[@]} -ge 2 ]; then
          echo "  使用当前DNS列表: ${DNS_LIST[*]}"
          bash compare.sh "${DNS_LIST[@]}"
        else
          echo "  对比至少需要2个DNS（当前: ${DNS_LIST[*]:-无}）"
          if ! prompt cmp_input "  请输入要对比的DNS（逗号分隔，回车默认 223.5.5.5,119.29.29.29）: "; then
            echo ""
            echo "⏰ 等待输入超时，返回主菜单..."
            return 0
          fi
          if [ -n "$cmp_input" ]; then
            # 逗号/空格分隔都兼容（read -ra 防分词问题）
            IFS=", " read -ra cmp_list <<< "$cmp_input"
            bash compare.sh "${cmp_list[@]}"
          else
            echo "  未输入，默认对比 223.5.5.5 与 119.29.29.29"
            bash compare.sh 223.5.5.5 119.29.29.29
          fi
        fi
      elif [ "$professional_test" = "$trd_n" ]; then
        echo "开始DNS趋势洞察（trends.sh，聚合 results/compare-*.json）..."
        echo "  提示: 需先积累compare数据（跑过compare即自动保存）"
        bash trends.sh --html
      elif [ "$professional_test" = "$ver_n" ]; then
        echo "开始一键全面验证（verify.sh，含语法/单测/冒烟/compare/trends/专项）..."
        echo "  提示: 网络项（compare/专项）在海外/受限网络可能超时，会友好提示"
        bash verify.sh
      else
        echo "无效选项，返回主菜单..."
      fi
      ;;
  esac
}

# ---- 主菜单循环 ----
echo "========================================"
echo "  🌐 DNS测试工具集"
echo "========================================"
print_env_info
echo ""
while true; do
  echo ""
  echo "──────── 主菜单 ────────"
  echo "  当前DNS: $DNS_DISPLAY"
  [ ${#DNS_LIST[@]} -ge 1 ] && echo "  数量: ${#DNS_LIST[@]} 个"
  echo "1. 基础测试（精简版/完整版）"
  echo "2. 专项测试（VoWiFi/端口/反向解析等）"
  if [ "$DNS_FROM_ARG" = "0" ]; then
    echo "3. 切换DNS组"
  fi
  echo "0. 退出"
  if ! prompt main_choice "请选择(0-3): "; then
    echo ""
    echo "⏰ 等待输入超时或结束，已退出。"
    exit 0
  fi
  echo ""
  case $main_choice in
    0) echo "👋 已退出，下次再见！"; exit 0 ;;
    1) run_basic ;;
    2) run_prof ;;
    3) [ "$DNS_FROM_ARG" = "0" ] && select_dns_group ;;
    *) echo "无效选项，请重新选择" ;;
  esac
done
