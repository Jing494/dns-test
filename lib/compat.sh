#!/bin/bash
# ============================================================================
# 平台兼容层（纯函数文件，无 dig/perl 前置检查，任何脚本可安全 source）
# 目前包含:
#   timeout 兼容函数 —— macOS 默认无 timeout 命令（coreutils 才有 gtimeout）
# 用法: source lib/compat.sh （或按 BASH_SOURCE/相对路径定位）
# ============================================================================

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
