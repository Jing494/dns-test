#!/bin/bash
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

# 加载注册表（幂等）
_plugins_loaded=0
_plugins_load() {
  [ "$_plugins_loaded" = "1" ] && return 0
  local mf="${PLUGIN_MANIFEST:-tools/manifest.sh}"
  if [ -f "$mf" ]; then
    source "$mf"
    _plugins_loaded=1
  else
    echo "⚠️ 插件注册表不存在: $mf（专项菜单不可用，可手动直跑 tools/ 脚本）" >&2
  fi
}
_plugins_load

# 拆分注册表行（| 分隔，纯内置）: $1=行  ->  全局 P_ID/P_SCRIPT/P_NAME/P_EXEC/P_PROMPT
_plugin_split() {
  local line="$1"
  P_ID=""; P_SCRIPT=""; P_NAME=""; P_EXEC=""; P_PROMPT=""
  IFS='|' read -r P_ID P_SCRIPT P_NAME P_EXEC P_PROMPT <<< "$line"
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
      path="${dir}/${P_SCRIPT}"
      [ -f "$path" ] || { echo "❌ 插件脚本不存在: $path" >&2; return 1; }
      echo "开始${P_NAME}..."
      args=""
      if [ -n "$P_PROMPT" ]; then
        read -r -t 30 -p "${P_PROMPT}: " pval 2>/dev/null || true
        [ -n "$pval" ] && args="$pval"
      fi
      # 与命令行直跑一致：从项目根调用 dir/script（不 cd，避免脚本内部相对路径失效）
      # 引导值(可选) + DNS列表(可空) 作为脚本参数
      case "$P_EXEC" in
        perl)
          if [ -n "$args" ]; then perl "$path" $args "$@"; else perl "$path" "$@"; fi
          ;;
        bash)
          if [ -n "$args" ]; then bash "$path" $args "$@"; else bash "$path" "$@"; fi
          ;;
        *)
          echo "❌ 未知执行器: $P_EXEC" >&2
          return 1
          ;;
      esac
      return $?
    fi
    i=$((i+1))
  done
  echo "❌ 无效选项: $n" >&2
  return 1
}
