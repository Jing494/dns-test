#!/bin/bash
# ============================================================================
# 自动安装依赖脚本（缺失才装，自动检测 apt/yum/dnf/brew）
# 用法: bash install.sh [--smoke]
#   直接跑: 检测 dig/perl/curl，缺失才安装，装完强制校验，通过后给下一步指引
#   --smoke: 校验通过后直接跑冒烟测试（23项自动化验证）
# 安装: dig(bind-utils/dnsutils/bind) + perl + curl
# ============================================================================
echo "════ 依赖检测 ════"

# 先检测包管理器，决定 dig 的包名
PM=""
if command -v apt-get >/dev/null 2>&1; then
  PM="apt"; PKG_DIG="dnsutils"
elif command -v dnf >/dev/null 2>&1; then
  PM="dnf"; PKG_DIG="bind-utils"
elif command -v yum >/dev/null 2>&1; then
  PM="yum"; PKG_DIG="bind-utils"
elif command -v brew >/dev/null 2>&1; then
  PM="brew"; PKG_DIG="bind"
fi

# 检测缺失项
NEED=()
command -v dig >/dev/null 2>&1   || NEED+=("$PKG_DIG")
command -v perl >/dev/null 2>&1  || NEED+=("perl")
command -v curl >/dev/null 2>&1  || NEED+=("curl")

if [ ${#NEED[@]} -eq 0 ]; then
  echo "  ✅ dig / perl / curl 已全部齐全，无需安装（跳过 sudo）"
elif [ -z "$PM" ]; then
  echo "  ❌ 未检测到 apt/yum/dnf/brew，且缺少: dig perl curl"
  echo ""
  echo "════ 手动安装指引（按你的系统选一条） ════"
  echo "  Debian/Ubuntu/WSL:   sudo apt-get install -y dnsutils perl curl"
  echo "  RHEL/CentOS/Fedora:  sudo dnf install -y bind-utils perl curl   (或 sudo yum ...)"
  echo "  macOS (Homebrew):    brew install bind perl curl"
  echo "  Alpine:              apk add bind-tools perl curl"
  echo "  Arch Linux:          sudo pacman -S bind perl curl"
  echo "  openSUSE:            sudo zypper install -y bind-utils perl curl"
  echo "  静态二进制(无包管理器): 从 https://github.com/ 搜索 dig/perl 静态包，或改用系统包管理"
  echo ""
  echo "  💡 极简/精简环境（busybox 等）建议：改用 WSL(Ubuntu) 或完整发行版——"
  echo "     本工具集依赖 dig + perl + curl，busybox 的替代命令不完整"
  echo "  📌 装好后重新运行: bash install.sh"
  exit 1
else
  echo "  缺失: ${NEED[*]}"
  echo "  包管理器: $PM"
  case "$PM" in
    apt)
      echo "════ 安装（apt-get） ════"
      sudo apt-get update && sudo apt-get install -y "${NEED[@]}" || { echo "❌ 安装失败（可能需 sudo 权限或网络问题）"; exit 1; }
      ;;
    dnf)
      echo "════ 安装（dnf） ════"
      sudo dnf install -y "${NEED[@]}" || { echo "❌ 安装失败"; exit 1; }
      ;;
    yum)
      echo "════ 安装（yum） ════"
      sudo yum install -y "${NEED[@]}" || { echo "❌ 安装失败"; exit 1; }
      ;;
    brew)
      echo "════ 安装（brew） ════"
      brew install "${NEED[@]}" || { echo "❌ 安装失败"; exit 1; }
      ;;
  esac
fi

echo ""
echo "════ 验证安装（强制校验） ════"
FAIL=0
if command -v dig >/dev/null 2>&1; then echo "  ✅ dig: $(dig -v 2>&1 | head -1)"; else echo "  ❌ dig 未安装"; FAIL=1; fi
if command -v perl >/dev/null 2>&1; then echo "  ✅ perl: $(perl -v 2>/dev/null | sed -n '2p')"; else echo "  ❌ perl 未安装"; FAIL=1; fi
if command -v curl >/dev/null 2>&1; then echo "  ✅ curl: $(curl --version | head -1)"; else echo "  ⚠️  curl 未安装（DoH检测降级为端口级，不影响主功能）"; fi

if [ "$FAIL" = "1" ]; then
  echo ""
  echo "  ❌ 依赖安装不完整，请检查网络/权限后重试，或手动安装"
  exit 1
fi

echo ""
if [ "$1" = "--smoke" ]; then
  echo "════ 依赖就绪，运行冒烟测试 ════"
  bash smoke_test.sh
else
  echo "✅ 依赖就绪！下一步（任选）:"
  echo "  bash install.sh --smoke            # 一键验证环境（23项自动化）"
  echo "  bash smoke_test.sh                 # 验证环境（23项自动化）"
  echo "  bash dns-test.sh                   # 交互引导测试（选DNS/版本/专项）"
  echo "  bash lite.sh 223.5.5.5 0           # 快速测一个DNS"
  echo "  bash compare.sh 223.5.5.5 119.29.29.29  # 多DNS横向对比"
  echo "  bash trends.sh --html              # 趋势洞察（积累compare数据后）"
fi
