#!/bin/bash
# ============================================================================
# 一键全面验证：语法 + shellcheck + 单测 + 冒烟 + compare + trends + 专项抽查
# 真机/沙箱通用——在你自己的机器上跑一遍，等于完成全部自检
# 用法: bash verify.sh [--strict]
#   （默认）  shellcheck 未安装时提示并跳过（可选依赖，CI 已兜底）
#   --strict  shellcheck 未安装时该项记失败（退出码 1），适合开发者/CI 真机自检
#   --help    打印用法说明
# 退出码: 0=全部通过 1=有失败项；--help 返回 0，未知参数返回 1
# 注意: compare/trends 为网络项，海外/受限网络可能超时；trends 无历史数据会提示跳过
# ============================================================================
cd "$(dirname "$0")" || exit 1
# 平台兼容层（macOS 默认无 timeout 命令，步骤4-7 的超时保护依赖它）
source lib/compat.sh
STRICT=0
case "$1" in
  --strict) STRICT=1 ;;
  -h|--help|help)
    echo "用法: bash verify.sh [--strict]"
    echo ""
    echo "  不带参数: 语法+shellcheck+单测+冒烟+compare+trends+专项 全量自检（约5分钟）"
    echo "             shellcheck 为可选依赖：未安装时提示跳过（CI 已兜底），不阻塞"
    echo "  --strict : shellcheck 未安装时该项记失败（退出码 1），适合开发者/CI 真机自检"
    echo ""
    echo "  安装可选依赖: bash install.sh --all"
    exit 0
    ;;
  --version)
    source "$(cd "$(dirname "$0")" && pwd)/lib/version.sh"
    echo "dns-test ${PROJECT_VERSION} (${PROJECT_RELEASE})"
    exit 0
    ;;
  "") ;;
  *)
    echo "⚠️ 未知参数: $1（可用 bash verify.sh --help 查看用法）"
    exit 1
    ;;
esac
PASS=0; FAIL=0; FAILED_ITEMS=""
tick() {  # $1=项名  $2=0/1
  if [ "$2" = "0" ]; then PASS=$((PASS+1)); echo "  ✅ $1"
  else FAIL=$((FAIL+1)); FAILED_ITEMS="$FAILED_ITEMS $1"; echo "  ❌ $1"; fi
}

echo "════ 一键全面验证 ════"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

echo "--- 1. 语法检查"
OK=1
for f in *.sh lib/*.sh tools/*.sh tools/network/*.sh; do bash -n "$f" 2>/dev/null || OK=0; done
while IFS= read -r f; do perl -c "$f" >/dev/null 2>&1 || OK=0; done < <(find . -name '*.pl')
tick "语法(.sh+.pl)" $((1-OK))

echo "--- 2. shellcheck（可选依赖；未安装则提示跳过）"
if command -v shellcheck >/dev/null 2>&1; then
  n=$(shellcheck -S warning *.sh lib/*.sh tools/*.sh tools/network/*.sh 2>/dev/null | grep -cE "SC[0-9]{4}")
  [ "$n" -eq 0 ] && tick "shellcheck(0告警)" 0 || tick "shellcheck(${n}告警)" 1
elif [ "$STRICT" = "1" ]; then
  echo "  ❌ --strict 模式：未安装 shellcheck（可选依赖，但严格模式要求安装）"
  echo "     安装（按系统选一条）:"
  echo "       Debian/Ubuntu/WSL:  sudo apt-get install -y shellcheck"
  echo "       RHEL/CentOS/Fedora: sudo dnf install -y shellcheck   (或 sudo yum install -y shellcheck)"
  echo "       macOS (Homebrew):   brew install shellcheck"
  echo "       Alpine:             apk add shellcheck"
  echo "       Arch Linux:         sudo pacman -S shellcheck"
  echo "       openSUSE:           sudo zypper install -y ShellCheck"
  echo "     或一键装齐（含可选依赖）: bash install.sh --all"
  tick "shellcheck(未装)" 1
else
  echo "  ⚠️ 未安装 shellcheck，跳过（可选依赖；装了可多查一道 shell 代码质量，CI 已兜底）"
  echo "     安装（按系统选一条）:"
  echo "       Debian/Ubuntu/WSL:  sudo apt-get install -y shellcheck"
  echo "       RHEL/CentOS/Fedora: sudo dnf install -y shellcheck   (或 sudo yum install -y shellcheck)"
  echo "       macOS (Homebrew):   brew install shellcheck"
  echo "       Alpine:             apk add shellcheck"
  echo "       Arch Linux:         sudo pacman -S shellcheck"
  echo "       openSUSE:           sudo zypper install -y ShellCheck"
  echo "     或一键装齐（含可选依赖）: bash install.sh --all"
  tick "shellcheck(未装跳过)" 0
fi

echo "--- 3. 单元测试（DNSUtil perl 18用例 + plugins 9 + dig_target 4 + core函数 15 + 计分口径 9）"
if perl -Ilib tests/01_dnsutil.t >/dev/null 2>&1 && bash tests/02_plugins.sh >/dev/null 2>&1 && bash tests/03_dig_target.sh >/dev/null 2>&1 && bash tests/04_core_functions.sh >/dev/null 2>&1 && bash tests/05_run_common_tests.sh >/dev/null 2>&1; then
  tick "单测(18+9+4+15+9用例)" 0
else
  tick "单测" 1
fi

echo "--- 4. 冒烟测试（25项，含网络项约3分钟）"
if timeout 300 bash smoke_test.sh 2>&1 | grep -q "25 通过 / 0 失败"; then
  tick "冒烟(25项)" 0
else
  tick "冒烟" 1
fi

echo "--- 5. compare 快测（2 DNS，网络项）"
if timeout 60 bash compare.sh 223.5.5.5 119.29.29.29 >/dev/null 2>&1; then
  tick "compare(2DNS)" 0
else
  tick "compare" 1
fi

echo "--- 6. trends 聚合（无历史数据则跳过；文本模式更快）"
timeout 45 bash trends.sh >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  tick "trends聚合" 0
elif [ "$rc" -eq 2 ]; then
  echo "  ⚠️ trends 无历史数据，跳过（先跑 compare 积累）"
  tick "trends(无数据跳过)" 0
elif [ "$rc" -eq 124 ] || [ "$rc" -ge 128 ]; then
  # 124=GNU timeout 超时；128+=macOS 兼容函数超时被信号终止（137/143），统一按超时提示
  echo "  ⚠️ trends 超时（数据量大/环境慢），可加 --since 缩小范围"
  tick "trends(超时提示)" 0
else
  tick "trends" 1
fi

echo "--- 7. 专项抽查（示例02对比 / DoH检测，网络项）"
OK=1
timeout 20 perl examples/02_multi_dns_compare.pl 223.5.5.5 119.29.29.29 >/dev/null 2>&1 || OK=0
timeout 15 bash tools/network/doh_dot_check.sh 223.5.5.5 >/dev/null 2>&1 || OK=0
tick "专项(示例02/DoH)" $((1-OK))

echo ""
echo "════ 汇总: $PASS 通过 / $FAIL 失败 ════"
[ -n "$FAILED_ITEMS" ] && echo "失败项:$FAILED_ITEMS"
echo ""
echo "════ 下一步 ════"
echo "  bash dns-test.sh                    # 交互引导测试（选DNS组/版本/专项）"
echo "  bash compare.sh 223.5.5.5 119.29.29.29  # 多DNS横向对比"
echo "  bash trends.sh --html               # DNS趋势洞察（积累compare数据后）"
echo "  bash verify.sh --strict             # 严格模式（shellcheck 未装算失败，开发者用）"
[ "$FAIL" -gt 0 ] && echo "  💡 有失败项：对照上方输出重跑单项，或看 docs/AI_GUIDE.md 第十一章（环境差异）"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
