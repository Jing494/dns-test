#!/bin/bash
# ============================================================================
# 平台兼容层（纯函数文件，无 dig/perl 前置检查，任何脚本可安全 source）
# 目前包含:
#   timeout 兼容函数 —— macOS 默认无 timeout 命令（coreutils 才有 gtimeout）
#   date_plus_minutes —— 跨平台"当前时间+N分钟"（BSD date -v / GNU date -d）
#   ts_to_epoch       —— 跨平台"YYYY-MM-DD HH:MM"转 epoch（BSD -j -f / GNU -d）
#   save_log_init     —— SAVE_LOG=1 时把脚本输出落盘到 results/（各入口统一调用）
# 用法: source lib/compat.sh （或按 BASH_SOURCE/相对路径定位）
# ============================================================================

# 当前时间 + N 分钟，输出 HH:MM（compare --watch 预计完成时间用）
# 先试 BSD 语法（macOS），失败回落 GNU 语法（Linux）；两者都不可用输出空串（调用方自行省略）
date_plus_minutes() {
  local m="$1" out
  out=$(date -v+"${m}"M +%H:%M 2>/dev/null) || out=""
  [ -z "$out" ] && out=$(date -d "+${m} minutes" +%H:%M 2>/dev/null)
  printf '%s' "$out"
}

# "YYYY-MM-DD HH:MM" → epoch 秒（trends 数据新鲜度用）；解析失败输出空串
ts_to_epoch() {
  local s="$1" e
  e=$(date -j -f "%Y-%m-%d %H:%M" "$s" +%s 2>/dev/null) || e=""
  [ -z "$e" ] && e=$(date -d "$s" +%s 2>/dev/null)
  printf '%s' "$e"
}

# N 天前的日期，输出 YYYY-MM-DD（trends 周对比窗口切分用）；失败输出空串（调用方跳过该节）
date_days_ago() {
  local n="$1" out
  out=$(date -v-"${n}"d +%F 2>/dev/null) || out=""
  [ -z "$out" ] && out=$(date -d "-${n} days" +%F 2>/dev/null)
  printf '%s' "$out"
}

# macOS 默认无 timeout 命令，提供兼容实现：
# 后台运行 + sleep 到期 kill（返回码：超时被kill≈137/143，GNU timeout为124，调用方按非0处理即可）
if ! command -v timeout >/dev/null 2>&1; then
  timeout() {
    local sec="$1"; shift
    "$@" &
    local pid=$!
    ( sleep "$sec"; kill "$pid" 2>/dev/null ) &
    local wp=$!
    wait "$pid" 2>/dev/null
    local rc=$?
    kill "$wp" 2>/dev/null
    wait "$wp" 2>/dev/null
    return $rc
  }
  export -f timeout 2>/dev/null
fi


# ----------------------------------------------------------------------------
# save_log_init —— SAVE_LOG 统一的日志落盘实现（全项目单一份）
#
# 用法: save_log_init "$0"   各入口脚本在早期调用一次；$0 用于生成日志文件名
# 行为: SAVE_LOG 非空时，把本脚本 stdout/stderr 一并写入
#       results/<脚本名>-<YYYYmmdd-HHMMSS>.log（目录不存在则自动建）
#
# 为什么落在 compat.sh 而不是 core.sh：
#   doctor.sh 刻意【不】source core.sh —— core.sh 缺 dig/perl 会直接 exit 1，
#   而那正是 doctor 要诊断并报告的场景。compat.sh 是无 dig/perl 前置检查的
#   纯函数文件，且 core.sh 自身也 source 它；因此只有放这里，全部入口脚本
#   （含 doctor / verify / smoke_test）才能统一获得该能力。
#
# 注意: 该实现会把 stderr 并入 stdout，故 stdout 为机器可读契约的调用方
#       （如 trends.sh --json 供 jq 消费）需自行跳过调用。
# ----------------------------------------------------------------------------
save_log_init() {
  [ -n "$SAVE_LOG" ] || return 0
  local _self="${1:-$0}"
  local _dir="${SCRIPT_DIR:-$(cd "$(dirname "$_self")" && pwd)}"
  mkdir -p "$_dir/results" 2>/dev/null || return 1
  local _log="$_dir/results/$(basename "$_self" .sh)-$(date +%Y%m%d-%H%M%S).log"
  if [ "$(uname)" = "Darwin" ]; then
    exec > "$_log" 2>&1
  else
    exec > >(tee "$_log") 2>&1
  fi
  echo "📄 日志保存: $_log"
  return 0
}
