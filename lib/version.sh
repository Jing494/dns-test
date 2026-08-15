#!/bin/bash
# shellcheck disable=SC2034
#   SC2034 (未使用变量)：PROJECT_VERSION/PROJECT_RELEASE 供其他脚本 source 后使用（跨文件），非本文件直接使用
# ============================================================================
# 版本号单一来源（双轨制）
#   PROJECT_VERSION = 日期式 vYYYY.MM.N（N=当月发布序号）
#   PROJECT_RELEASE = 语义式 vX.Y（X=主版本, Y=次版本）
# 各脚本（core.sh/release.sh 等）统一 source 本文件，改版本只需改这一处。
# ============================================================================
PROJECT_VERSION="v2026.08.18"
PROJECT_RELEASE="v1.11"
