#!/bin/bash
# shellcheck disable=SC1090  # 注册表路径可被 PLUGIN_MANIFEST 覆盖（非固定 source，与 core.sh 同策略）
# ============================================================================
# 专项插件加载器（纯函数文件，无副作用，任何脚本可安全 source）
# 依赖: tools/manifest.sh（注册表，可用 PLUGIN_MANIFEST 环境变量覆盖路径）
# 提供:
#   plugin_list                      -> 打印 "编号. 名称"（供菜单展示）
#   plugin_run <编号> [DNS列表...]   -> 按编号执行插件脚本（退出码: 0=成功 1=失败）
# 设计原则:
#   - 轻量: 只 source 一个注册表文件 + 数组遍历，字段拆分用 bash 内置（无 fork）
#   - 不侵入: 执行时从项目根拼接 dir/script 调用，与命令行直跑完全一致
#   - 引导: 注册表第5字段非空时，执行前 read -t 30 一次，输入作为脚本首参（可空）
# ============================================================================

# 项目根（本文件在 lib/ 下，上一级才是根；不依赖调用方 CWD——任何脚本可安全 source）
_PLUGIN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || exit 1

# 加载注册表（幂等）
_plugins_loaded=0
_plugins_load() {
  [ "$_plugins_loaded" = "1" ] && return 0
  local mf="${PLUGIN_MANIFEST:-$_PLUGIN_ROOT/tools/manifest.sh}"
  if [ -f "$mf" ]; then
    source "$mf"
    _plugins_loaded=1
  else
    echo "⚠️ 插件注册表不存在: $mf（专项菜单不可用，可手动直跑 tools/ 脚本）" >&2
  fi
}
_plugins_load

# 拆分注册表行（| 分隔，纯内置）: $1=行  ->  全局 P_ID/P_SCRIPT/P_NAME/P_EXEC/P_PROMPT/P_FWD
_plugin_split() {
  local line="$1"
  P_ID=""; P_SCRIPT=""; P_NAME=""; P_EXEC=""; P_PROMPT=""; P_FWD=1
  IFS='|' read -r P_ID P_SCRIPT P_NAME P_EXEC P_PROMPT P_FWD <<< "$line"
  [ -z "$P_FWD" ] && P_FWD=1
}

# 打印所有菜单项: "编号. 名称"
plugin_list() {
  local i=1 item
  for item in "${PLUGIN_ITEMS[@]}"; do
    _plugin_split "$item"
    echo "$i. $P_NAME"
    i=$((i+1))
  done
}

# 执行第 n 个菜单项；剩余参数原样传给脚本（如 DNS 列表）
# 返回: 脚本退出码透传；编号无效/插件缺失返回 1
plugin_run() {
  local n="$1"; shift
  [ -z "$n" ] && return 1
  local i=1 item dir path args pval
  for item in "${PLUGIN_ITEMS[@]}"; do
    if [ "$i" = "$n" ]; then
      _plugin_split "$item"
      dir="PLUGIN_DIR_$P_ID"
      dir="${!dir}"
      [ -z "$dir" ] && { echo "❌ 插件目录未注册: $P_ID" >&2; return 1; }
      # 绝对路径拼接（项目根 + 目录映射 + 脚本名），与调用方 CWD 无关
      path="${_PLUGIN_ROOT}/${dir}/${P_SCRIPT}"
      [ -f "$path" ] || { echo "❌ 插件脚本不存在: $path" >&2; return 1; }
      echo "开始${P_NAME}..."
      args=""
      if [ -n "$P_PROMPT" ]; then
        read -r -t 30 -p "${P_PROMPT}: " pval 2>/dev/null || true
        [ -n "$pval" ] && args="$pval"
      fi
      # 校验执行器（perl/bash 白名单，防 manifest 误填执行任意命令）
      if [ "$P_EXEC" != "perl" ] && [ "$P_EXEC" != "bash" ]; then
        echo "❌ 未知执行器: $P_EXEC（仅支持 perl/bash）" >&2
        return 1
      fi
      # 参数策略三态（防 DNS 被误当插件参数）:
      #   1) 引导输入非空 → 独占参数（用户明确给了目标）
      #   2) 引导为空 + P_FWD=1 → 透传 DNS_LIST（如 DoH"回车用当前组"）
      #   3) 引导为空 + P_FWD=0 → 无参数执行（如 carrier_epdg/端口测试，用脚本默认/内置）
      if [ -n "$args" ]; then
        # read -a 按 IFS 分词为字面值数组（不触发 glob），防通配符/特殊字符被误展开
        local -a args_arr
        read -r -a args_arr <<< "$args"
        "$P_EXEC" "$path" "${args_arr[@]}"
      elif [ "$P_FWD" = "1" ]; then
        "$P_EXEC" "$path" "$@"
      else
        "$P_EXEC" "$path"
      fi
      return $?
    fi
    i=$((i+1))
  done
  echo "❌ 无效选项: $n" >&2
  return 1
}
