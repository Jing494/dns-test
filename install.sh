#!/bin/bash
# ============================================================================
# 自动安装依赖脚本（自动检测 apt/yum/dnf/brew）
# 用法: bash install.sh      （需要 sudo 权限；macOS 需先装 Homebrew）
# 安装: dig(bind-utils/dnsutils) + perl + curl
# ============================================================================
echo "════ 检测系统包管理器 ════"

if command -v apt-get >/dev/null 2>&1; then
  echo "  → apt-get (Debian/Ubuntu/WSL)"
  sudo apt-get update && sudo apt-get install -y dnsutils perl curl
elif command -v dnf >/dev/null 2>&1; then
  echo "  → dnf (Fedora/RHEL 9+)"
  sudo dnf install -y bind-utils perl curl
elif command -v yum >/dev/null 2>&1; then
  echo "  → yum (RHEL/CentOS)"
  sudo yum install -y bind-utils perl curl
elif command -v brew >/dev/null 2>&1; then
  echo "  → brew (macOS)"
  brew install bind perl curl
else
  echo "  ❌ 未检测到 apt/yum/dnf/brew"
  echo "    请手动安装: dig(bind-utils) + perl + curl"
  exit 1
fi

echo ""
echo "════ 验证安装 ════"
if command -v dig >/dev/null 2>&1; then echo "  ✅ dig: $(dig -v 2>&1 | head -1)"; else echo "  ❌ dig 未安装"; fi
if command -v perl >/dev/null 2>&1; then echo "  ✅ perl: $(perl -v 2>/dev/null | sed -n '2p')"; else echo "  ❌ perl 未安装"; fi
if command -v curl >/dev/null 2>&1; then echo "  ✅ curl: $(curl --version | head -1)"; else echo "  ⚠️  curl 未安装（DoH检测将降级为端口级，不影响主功能）"; fi

echo ""
if [ "$1" = "--smoke" ]; then
  echo "════ 运行冒烟测试 ════"
  bash smoke_test.sh
else
  echo "✅ 依赖安装完成！下一步（任选）:"
  echo "  bash smoke_test.sh               # 验证环境（19项自动化）"
  echo "  bash dns-test.sh                 # 交互引导测试（选DNS/版本/专项）"
  echo "  bash lite.sh 223.5.5.5 0         # 快速测一个DNS"
  echo "  bash install.sh --smoke          # 或装完直接跑冒烟"
fi
