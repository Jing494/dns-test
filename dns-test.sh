#!/bin/bash
# shellcheck disable=SC2154  # 变量由 prompt() 内 read -t -p 动态赋值（跨函数，shellcheck 无法追踪）
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

# 帮助输出（与其余入口脚本一致）
if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
  echo "用法: bash dns-test.sh [DNS...] [专项选项...]"
  echo "  DNS列表: 一个或多个DNS地址（默认取默认运营商DNS组，v4/v6 各 2 个），支持v4/v6混合"
  echo "           传入后仍可在主菜单 3. DNS 管理 里追加/替换/删除；不传则从默认组开始"
  echo "  专项选项: 原样转发给选中的专项脚本（含带值的选项），由子脚本自校验——未知选项会报错退出"
  echo "            compare.sh → --html --md --json --open --no-save --rounds N ...（DNS 用当前列表）"
  echo "            trends.sh  → --html --md --json --csv --detail --since D --until D --cron ..."
  echo "                         显式给过 DNS 时当前列表作为过滤条件（--cron 必须有 DNS）；默认组不过滤"
  echo "            verify.sh  → --strict --ci"
  echo "            基础测试（精简版/完整版）与 1-10 号插件不接受命令行选项，传入会提示忽略"
  echo "            （插件自身的参数在插件提示符里输入，如路由器网关IP、目标IP 端口 协议）"
  echo "  交互: 测完自动返回主菜单，可继续测试或输入 0 退出；全程 30 秒输入超时保护"
  echo "  示例:"
  echo "    bash dns-test.sh                              # 默认DNS组（交互选版本/专项）"
  echo "    bash dns-test.sh 8.8.8.8                      # 自定义DNS"
  echo "    bash dns-test.sh 8.8.8.8 114.114.114.114      # 多个自定义DNS"
  echo "    bash dns-test.sh 223.5.5.5 119.29.29.29 --html   # 专项透传 --html 生成报告"
  echo "  环境变量: DEFAULT_DNS_CSV=... 自定义默认DNS组；SAVE_LOG=1 保存日志"
  exit 0
fi

# 处理参数：DNS 地址进 DNS_LIST，其余（选项及其取值）进 PASS_ARGS 原样转发给专项脚本
# 判定依据是项目自带的 valid_dns_addr —— 用"是不是合法DNS地址"来切分，
# 从而不必维护"哪些选项带值"的路由表（那种表会随子脚本演进而漂移）。
DNS_LIST=()
PASS_ARGS=()
DNS_FROM_ARG=0

# ---------------------------------------------------------------------------
# 会话 DNS 的展示与「是否显式指定」单点同步
#   DNS_FROM_ARG=1 = 用户显式给过 DNS（命令行 或 DNS 管理菜单），trends 才把它当过滤条件；
#   与默认组完全一致时按默认组对待（默认组的 4 个地址若当过滤条件，会把历史数据裁成只有它们）
# ---------------------------------------------------------------------------
sync_dns_display() {
  if [ ${#DNS_LIST[@]} -eq 0 ]; then
    DNS_DISPLAY="默认运营商DNS ${#DEFAULT_DNS_ADDR[@]}个（默认组）"
    DNS_FROM_ARG=0
  elif dns_list_is_default_group; then
    DNS_DISPLAY="默认运营商DNS ${#DNS_LIST[@]}个（默认组）"
    DNS_FROM_ARG=0
  else
    DNS_DISPLAY="${#DNS_LIST[@]} 个: ${DNS_LIST[*]}"
    DNS_FROM_ARG=1
  fi
}

# 预设组选择器：结果写入全局 DNS_PICK（bash 3.2 无法从函数返回数组）
# 返回 0=选到一组 1=取消/超时/非法
pick_preset_group() {
  echo "请选择预设组："
  echo "1. 默认运营商DNS（可配置）"
  echo "2. 阿里云公共DNS"
  echo "3. 腾讯DNSPod"
  echo "4. 全部（默认+阿里+腾讯）"
  echo "0. 返回"
  if ! prompt preset_choice "请输入选项(0-4): "; then
    echo ""
    echo "⏰ 等待输入超时，返回主菜单..."
    return 1
  fi
  echo ""
  DNS_PICK=()
  case $preset_choice in
    1) DNS_PICK=("${DEFAULT_DNS_ADDR[@]}") ;;
    2) DNS_PICK=("${ALI_DNS_ADDR[@]}") ;;
    3) DNS_PICK=("${TENCENT_DNS_ADDR[@]}") ;;
    4) DNS_PICK=("${DEFAULT_DNS_ADDR[@]}" "${ALI_DNS_ADDR[@]}" "${TENCENT_DNS_ADDR[@]}") ;;
    0) return 1 ;;
    *) echo "无效选项"; return 1 ;;
  esac
  return 0
}

# DNS 管理子菜单（主菜单 3）：追加 / 替换 / 删除 / 清空 / 恢复默认
# 命令行传没传 DNS 都可用 —— 之前带参数时该项被隐藏，会话内完全无法改 DNS（割裂点之一）
manage_dns() {
  local added skipped cnt i addr idx
  while true; do
    echo ""
    echo "──────── DNS 管理 ────────"
    if [ ${#DNS_LIST[@]} -ge 1 ]; then
      echo "  当前列表（${#DNS_LIST[@]} 个）:"
      i=0
      for addr in "${DNS_LIST[@]}"; do
        i=$((i+1))
        printf "    [%d] %s\n" "$i" "$addr"
      done
    else
      echo "  当前列表为空，使用默认组 ${#DEFAULT_DNS_ADDR[@]} 个（追加任意 DNS 即脱离默认组）"
    fi
    echo "  ── 操作 ──"
    echo "1. 追加 DNS（手工输入，逗号/空格分隔）"
    echo "2. 追加预设组（保留现有 DNS）"
    echo "3. 替换为预设组（覆盖现有 DNS）"
    echo "4. 删除某个 DNS（按上方 [编号]）"
    echo "5. 清空列表（回到默认组）"
    echo "6. 恢复默认组"
    echo "0. 返回主菜单"
    if ! prompt dns_mgr "请输入选项(0-6): "; then
      echo ""
      echo "⏰ 等待输入超时，返回主菜单..."
      return 0
    fi
    echo ""
    case $dns_mgr in
      0) return 0 ;;
      1)
        if ! prompt dns_add "请输入要追加的DNS（多个用逗号或空格分隔）: "; then
          echo ""
          echo "⏰ 等待输入超时，返回主菜单..."
          return 0
        fi
        if [ -z "$dns_add" ]; then
          echo "未输入，未改动"
        else
          added=0; skipped=0
          local -a _new
          IFS=$' \t,' read -r -a _new <<< "$dns_add"   # 逗号/空格/制表都当分隔符
          for addr in "${_new[@]}"; do
            if dns_list_add "$addr"; then added=$((added+1)); else skipped=$((skipped+1)); fi
          done
          if [ "$skipped" -gt 0 ]; then
            echo "已追加 ${added} 个；跳过 ${skipped} 个（重复或非合法地址）"
          else
            echo "已追加 ${added} 个"
          fi
          if [ ${#DNS_LIST[@]} -gt 4 ]; then
            echo "💡 当前 ${#DNS_LIST[@]} 个DNS：基础测试/专项逐个跑，耗时随数量线性增长"
          fi
        fi
        ;;
      2)
        if pick_preset_group; then
          added=0; skipped=0
          for addr in "${DNS_PICK[@]}"; do
            if dns_list_add "$addr"; then added=$((added+1)); else skipped=$((skipped+1)); fi
          done
          if [ "$skipped" -gt 0 ]; then
            echo "已追加预设组 ${added} 个；跳过 ${skipped} 个（已存在）"
          else
            echo "已追加预设组 ${added} 个"
          fi
        fi
        ;;
      3)
        if pick_preset_group; then
          DNS_LIST=("${DNS_PICK[@]}")
          echo "已替换为预设组：${#DNS_LIST[@]} 个"
        fi
        ;;
      4)
        if [ ${#DNS_LIST[@]} -eq 0 ]; then
          echo "当前列表为空（使用默认组），无需删除"
        elif ! prompt dns_del "请输入要删除的编号（见上方 [n]，1-${#DNS_LIST[@]}）: "; then
          echo ""
          echo "⏰ 等待输入超时，返回主菜单..."
          return 0
        elif [[ "$dns_del" =~ ^[1-9][0-9]*$ ]] && [ "$dns_del" -le "${#DNS_LIST[@]}" ]; then
          cnt=$((dns_del-1))
          addr="${DNS_LIST[$cnt]}"
          dns_list_remove "$addr" && echo "已删除: $addr"
        else
          echo "无效编号，未改动"
        fi
        ;;
      5) DNS_LIST=(); echo "已清空（回到默认组）" ;;
      6) DNS_LIST=("${DEFAULT_DNS_ADDR[@]}"); echo "已恢复默认组：${#DNS_LIST[@]} 个" ;;
      *) echo "无效选项" ;;
    esac
    sync_dns_display
  done
}

for _arg in "$@"; do
  if valid_dns_addr "$_arg"; then
    DNS_LIST+=("$_arg")
  else
    PASS_ARGS+=("$_arg")
  fi
done
# 展示与「是否显式指定」统一口径（与 DNS 管理菜单共用 sync_dns_display）
sync_dns_display

# 非交互模式（无终端）：为避免超时，默认只跑精简版+第1个DNS，一次跑完退出
if [ ! -t 0 ]; then
  echo "非交互模式，为避免超时，默认运行精简版测试（仅第1个DNS）..."
  if [ ${#PASS_ARGS[@]} -gt 0 ]; then
    echo "  ⚠️  非交互模式只跑基础测试（lite），选项 ${PASS_ARGS[*]} 不适用已忽略"
    echo "      需要这些选项请直接调用 bash compare.sh / bash trends.sh / bash verify.sh"
  fi
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

# 说明：旧的 select_dns_group（只能整体替换某个预设组、且带命令行 DNS 时被整项隐藏）
# 已由上面的 manage_dns 取代 —— 追加/替换/删除都在同一个子菜单里，传没传 DNS 都能进。

# 基础测试（精简版/完整版）
run_basic() {
  # 本次运行的 DNS 快照：「指定测试某一个」只影响这一次，不改写会话级 DNS_LIST/DNS_DISPLAY
  # （否则用户回不到原来的列表——割裂点之三；与下面 >4 截断、插件截断的"仅本次"口径一致）
  local -a RUN_LIST
  RUN_LIST=("${DNS_LIST[@]}")
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

      # 基础测试（lite/full）不收选项：传入即明确提示忽略，避免"传了没生效"的静默困惑
      if [ ${#PASS_ARGS[@]} -gt 0 ]; then
        echo "⚠️  基础测试不接受选项，${PASS_ARGS[*]} 将被忽略"
        echo "    这些选项属于专项测试（主菜单 2），需要请走专项"
        echo ""
      fi

      # 多DNS时询问是否指定某一个（只改本次 RUN_LIST，不动会话 DNS_LIST）
      if [ ${#RUN_LIST[@]} -gt 1 ]; then
        echo "当前 ${#RUN_LIST[@]} 个DNS，全部跑完较耗时："
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
          1) : ;;  # 全部测试
          2)
            echo "可测试的DNS列表："
            for idx in "${!RUN_LIST[@]}"; do
              printf "  %d. %s\n" $((idx+1)) "${RUN_LIST[$idx]}"
            done
            if ! prompt dns_choice "请输入要测试的DNS编号(1-${#RUN_LIST[@]}): "; then
              echo ""
              echo "⏰ 等待输入超时，返回主菜单..."
              return 0
            fi
            echo ""
            # dns_choice 是用户输入的 1-based 编号：先校验纯数字再做 1→0 索引换算，避免非数字输入产生报错噪音；非法/越界回退第1个
            if [[ "$dns_choice" =~ ^[1-9][0-9]*$ ]] && [ "$dns_choice" -le "${#RUN_LIST[@]}" ]; then
              RUN_LIST=("${RUN_LIST[$((dns_choice-1))]}")
            else
              echo "无效编号，默认测试第一个DNS"
              RUN_LIST=("${RUN_LIST[0]}")
            fi
            echo "本次只测: ${RUN_LIST[0]}（会话 DNS 列表保持不变；要改动请用主菜单 3. DNS 管理）"
            ;;
          *) echo "无效选项，返回主菜单..."; return 0 ;;
        esac
      fi

      # 数量保护：>4 个只测第1个，防超时
      if [ ${#RUN_LIST[@]} -gt 4 ]; then
        echo "⚠️  ${#RUN_LIST[@]}个DNS跑测试会超时，本次只测第1个: ${RUN_LIST[0]}"
        bash "$script" "${RUN_LIST[0]}" 0
      elif [ ${#RUN_LIST[@]} -ge 1 ]; then
        bash "$script" "${RUN_LIST[@]}"
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
        # 插件分两类（注册表第 7 字段 P_OPTS 声明）：
        #   P_OPTS=1 → 接受命令行额外参数（如 carrier_epdg 的运营商代码），原样透传
        #   其余     → 不收命令行选项，明确提示忽略（避免"传了没生效"的静默困惑）
        if plugin_accepts_opts "$professional_test" && [ ${#PASS_ARGS[@]} -gt 0 ]; then
          echo "  透传插件参数: ${PASS_ARGS[*]}"
          plugin_run "$professional_test" "${PASS_ARGS[@]}"
        elif [ ${#PASS_ARGS[@]} -gt 0 ]; then
          echo "⚠️  专项插件不接受命令行选项，${PASS_ARGS[*]} 将被忽略"
          echo "    插件的参数由插件菜单内的引导输入决定"
          echo ""
        fi
        # 专项插件：DNS 数量保护（专项脚本收多 DNS 会慢/超时，最多4个）
        # 仅本次调用截断，不改动会话内 DNS_LIST/DNS_DISPLAY（避免副作用带到后续测试）
        if [ ${#DNS_LIST[@]} -gt 4 ]; then
          echo "⚠️  ${#DNS_LIST[@]}个DNS跑专项会慢，本次只取前4个"
          plugin_run "$professional_test" "${DNS_LIST[@]:0:4}"
        else
          plugin_run "$professional_test" "${DNS_LIST[@]}"
        fi
      elif [ "$professional_test" = "$cmp_n" ]; then
        echo "开始多DNS对比（compare.sh，lite精简版53项/DNS，并行）..."
        if [ ${#DNS_LIST[@]} -ge 2 ]; then
          echo "  使用当前DNS列表: ${DNS_LIST[*]}"
          [ ${#PASS_ARGS[@]} -gt 0 ] && echo "  透传选项: ${PASS_ARGS[*]}"
          bash compare.sh "${DNS_LIST[@]}" "${PASS_ARGS[@]}"
        else
          # 继承已传 DNS：用它占一个位、只让用户补对比对象；默认值含已传的那个
          # （否则回车会把它丢掉、去比两个用户从没提过的 DNS —— 割裂点之二）
          local cmp_base cmp_partner cmp_def
          cmp_base="${DNS_LIST[0]:-}"
          cmp_partner=$(dns_partner_default)
          if [ -n "$cmp_base" ]; then
            cmp_def="${cmp_base},${cmp_partner}"
          else
            cmp_def="223.5.5.5,119.29.29.29"
          fi
          echo "  对比至少需要2个DNS（当前: ${DNS_LIST[*]:-无}）"
          if ! prompt cmp_input "  请输入要对比的DNS（逗号分隔，回车默认 ${cmp_def}；也可输预设组名如 ali,tencent）: "; then
            echo ""
            echo "⏰ 等待输入超时，返回主菜单..."
            return 0
          fi
          if [ -n "$cmp_input" ]; then
            # 逗号/空格分隔都兼容（read -ra 防分词问题）
            IFS=", " read -ra cmp_list <<< "$cmp_input"
            bash compare.sh "${cmp_list[@]}" "${PASS_ARGS[@]}"
          else
            echo "  未输入，默认对比 ${cmp_def%%,*} 与 ${cmp_def##*,}"
            bash compare.sh "${cmp_def%%,*}" "${cmp_def##*,}" "${PASS_ARGS[@]}"
          fi
        fi
      elif [ "$professional_test" = "$trd_n" ]; then
        echo "开始DNS趋势洞察（trends.sh，聚合 results/compare-*.json）..."
        echo "  提示: 需先积累compare数据（跑过compare即自动保存）"
        # 继承已传 DNS 作为过滤：trends 的位置参数就是 DNS 过滤（--cron 也必须有 DNS）；
        # 默认组不当过滤，否则会把历史数据裁成只剩默认组那几个地址
        local -a targs
        targs=()
        if [ "$DNS_FROM_ARG" = "1" ] && [ ${#DNS_LIST[@]} -ge 1 ]; then
          targs=("${DNS_LIST[@]}")
          echo "  以当前DNS作为过滤条件: ${DNS_LIST[*]}"
        else
          echo "  当前为默认组，未作为过滤条件（统计全部历史数据）"
        fi
        if [ ${#PASS_ARGS[@]} -gt 0 ]; then
          echo "  透传选项: ${PASS_ARGS[*]}"
          bash trends.sh "${targs[@]}" "${PASS_ARGS[@]}"
        else
          echo "  未指定报告选项，默认 --html（可用 bash dns-test.sh --csv 等自定义）"
          bash trends.sh "${targs[@]}" --html
        fi
      elif [ "$professional_test" = "$ver_n" ]; then
        echo "开始一键全面验证（verify.sh，含语法/单测/冒烟/compare/trends/专项）..."
        echo "  提示: 网络项（compare/专项）在海外/受限网络可能超时，会友好提示"
        if [ ${#PASS_ARGS[@]} -gt 0 ]; then
          echo "  透传选项: ${PASS_ARGS[*]}"
          bash verify.sh "${PASS_ARGS[@]}"
        else
          bash verify.sh
        fi
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
  if [ ${#DNS_LIST[@]} -ge 1 ]; then
    echo "  数量: ${#DNS_LIST[@]} 个"
  else
    echo "  数量: ${#DEFAULT_DNS_ADDR[@]} 个（默认组）"
  fi
  echo "1. 基础测试（精简版/完整版）"
  echo "2. 专项测试（VoWiFi/端口/反向解析等）"
  # 第 3 项始终显示：带命令行 DNS 时它就是"修改已传入的 DNS"，不再被隐藏
  # （原先带参数时整项隐藏且提示仍写 (0-3)，输入 3 无任何反馈——割裂点之一）
  _src_note=""
  [ "$DNS_FROM_ARG" = "1" ] && _src_note=" · 已显式指定"
  if [ ${#DNS_LIST[@]} -eq 0 ]; then
    _n_note="当前使用默认组 ${#DEFAULT_DNS_ADDR[@]} 个"
  else
    _n_note="当前 ${#DNS_LIST[@]} 个${_src_note}"
  fi
  echo "3. DNS 管理（追加/替换/删除/清空；${_n_note}）"
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
    3) manage_dns ;;
    *) echo "无效选项，请重新选择" ;;
  esac
done
