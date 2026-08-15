#!/bin/bash
# ============================================================================
# 自动安装依赖脚本（缺失才装，自动检测 apt/yum/dnf/brew）
# 用法: bash install.sh [--smoke|--all|--completions|--help]
#   直接跑: 检测必需依赖 dig/perl/curl，缺失才安装，装完强制校验；校验时检测 dig 的 DoT 能力（bind 9.18+ 才支持 +tls）
#           末尾检测可选依赖 shellcheck——终端下会询问"是否现在一并安装？"（y/N 默认不装），非交互/管道自动跳过
#           依赖就绪后顺手安装 shell 补全（幂等，写 rc 文件带标记可重复运行）
#   --smoke: 校验通过后直接跑冒烟测试（24项自动化验证）
#   --all:   连同可选依赖 shellcheck 一起安装（verify.sh 的 shell 静态检查需要）
#   --completions: 只装 shell 补全（不动依赖；检测 ~/.bashrc/.zshrc 幂等写入）
#   --help:  打印用法说明；未知参数报错退出（退出码 1）
# 必需安装: dig(bind-utils/dnsutils/bind) + perl + curl
# 可选安装: shellcheck（shell 静态检查，verify.sh 使用；不装则 verify 跳过该项，CI 已兜底）
# ============================================================================

# shell 补全安装（幂等）：bash 写 ~/.bashrc（无则 ~/.bash_profile），zsh 装 ~/.zfunc/_dns-test 并在 zshrc 启用
# 标记行防重复写入；未发现任何 rc 文件时只提示手动方式
install_completions() {
  local DIR_C MARK RC DID
  DIR_C=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  MARK="# dns-test completions (added by install.sh)"
  DID=0
  echo "════ 安装 shell 补全 ════"
  # bash：~/.bashrc 优先，无则 ~/.bash_profile（macOS bash 默认读后者）
  for RC in "$HOME/.bashrc" "$HOME/.bash_profile"; do
    [ -f "$RC" ] || continue
    if grep -qF "$MARK" "$RC" 2>/dev/null; then
      echo "  ✅ bash 补全已配置过（$RC 含标记，跳过）"
    else
      {
        echo ""
        echo "$MARK"
        echo "[ -f \"$DIR_C/completions/dns-test.bash\" ] && source \"$DIR_C/completions/dns-test.bash\""
      } >> "$RC"
      echo "  ✅ bash 补全已写入 $RC（重开终端或 source $RC 生效）"
    fi
    DID=1
    break
  done
  # zsh：装到 ~/.zfunc/_dns-test + rc 里启用（oh-my-zsh 用户已有 compinit 也不冲突，重复 compinit 仅稍慢）
  if [ -f "$HOME/.zshrc" ]; then
    mkdir -p "$HOME/.zfunc"
    cp "$DIR_C/completions/dns-test.zsh" "$HOME/.zfunc/_dns-test" 2>/dev/null \
      && echo "  ✅ zsh 补全已装到 ~/.zfunc/_dns-test" || echo "  ⚠️  zsh 补全拷贝失败（检查 ~/.zfunc 可写）"
    if grep -qF "$MARK" "$HOME/.zshrc" 2>/dev/null; then
      echo "  ✅ zshrc 已配置过（含标记，跳过）"
    else
      {
        echo ""
        echo "$MARK"
        echo "fpath=(\$HOME/.zfunc \$fpath)"
        echo "autoload -Uz compinit && compinit"
      } >> "$HOME/.zshrc"
      echo "  ✅ zshrc 已启用（fpath+compinit，重开终端生效）"
    fi
    DID=1
  fi
  [ "$DID" = "0" ] && echo "  ℹ️  未发现 ~/.bashrc / ~/.bash_profile / ~/.zshrc——手动启用见 completions/ 文件头注释"
  echo "  （幂等，可重复运行；卸载=删 rc 内标记段与 ~/.zfunc/_dns-test）"
}

MODE="${1:-}"
case "$MODE" in
  -h|--help|help)
    echo "用法: bash install.sh [--smoke|--all|--completions]"
    echo ""
    echo "  直接跑: 检测必需依赖 dig/perl/curl，缺失才安装（自动检测包管理器），装完强制校验"
    echo "           校验时检测 dig 的 DoT 能力（bind 9.18+ 才支持 +tls）"
    echo "           末尾检测可选依赖 shellcheck——终端下会询问是否一并安装（y/N 默认不装）"
    echo "           依赖就绪后顺手安装 shell 补全（幂等）"
    echo "  --smoke      : 校验通过后直接跑冒烟测试（24项自动化验证）"
    echo "  --all        : 连同可选依赖 shellcheck 一起安装（verify.sh 的 shell 静态检查用）"
    echo "  --completions: 只装 shell 补全（不动依赖；bash 写 ~/.bashrc，zsh 装 ~/.zfunc 并启用）"
    echo ""
    echo "  手动安装（无包管理器时按系统选一条）:"
    echo "    Debian/Ubuntu/WSL:  sudo apt-get install -y dnsutils perl curl"
    echo "    RHEL/CentOS/Fedora: sudo dnf install -y bind-utils perl curl"
    echo "    macOS (Homebrew):   brew install bind perl curl"
    echo "    可选 shellcheck: sudo apt-get install -y shellcheck / brew install shellcheck"
    exit 0
    ;;
  --version)
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/version.sh"
    echo "dns-test ${PROJECT_VERSION} (${PROJECT_RELEASE})"
    exit 0
    ;;
  --completions)
    # 独立补全安装：不动依赖，装完即退（幂等，可重复运行）
    install_completions
    exit 0
    ;;
  "") ;;
  --smoke|--all) ;;
  *)
    echo "⚠️ 未知参数: $MODE（可用 bash install.sh --help 查看用法）"
    exit 1
    ;;
esac
MODE_ALL=0
[ "$MODE" = "--all" ] && MODE_ALL=1
# root/容器无需 sudo；非 root 用 sudo 前缀（避免 root 环境因无 sudo 命令而安装失败）
SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"
echo "════ 依赖检测 ════"

# 先检测包管理器，决定 dig / shellcheck 的包名
# 默认通用名（无包管理器场景下 NEED 数组/提示不出现空包名，检测到包管理器后按发行版覆盖）
PM=""
PKG_DIG="dig"; PKG_SC="shellcheck"
if command -v apt-get >/dev/null 2>&1; then
  PM="apt"; PKG_DIG="dnsutils"; PKG_SC="shellcheck"
elif command -v dnf >/dev/null 2>&1; then
  PM="dnf"; PKG_DIG="bind-utils"; PKG_SC="shellcheck"
elif command -v yum >/dev/null 2>&1; then
  PM="yum"; PKG_DIG="bind-utils"; PKG_SC="shellcheck"
elif command -v brew >/dev/null 2>&1; then
  PM="brew"; PKG_DIG="bind"; PKG_SC="shellcheck"
elif command -v apk >/dev/null 2>&1; then
  PM="apk"; PKG_DIG="bind-tools"; PKG_SC="shellcheck"
elif command -v pacman >/dev/null 2>&1; then
  PM="pacman"; PKG_DIG="bind"; PKG_SC="shellcheck"
elif command -v zypper >/dev/null 2>&1; then
  PM="zypper"; PKG_DIG="bind-utils"; PKG_SC="ShellCheck"
fi

# 检测缺失项（必需：dig/perl/curl；可选：shellcheck，仅 --all 时并入安装）
NEED=()
NEED_SC=()
command -v dig >/dev/null 2>&1   || NEED+=("$PKG_DIG")
command -v perl >/dev/null 2>&1  || NEED+=("perl")
command -v curl >/dev/null 2>&1  || NEED+=("curl")
if [ "$MODE_ALL" = "1" ] && ! command -v shellcheck >/dev/null 2>&1; then
  NEED_SC+=("$PKG_SC")
fi

if [ ${#NEED[@]} -eq 0 ] && [ ${#NEED_SC[@]} -eq 0 ]; then
  echo "  ✅ dig / perl / curl 已全部齐全，无需安装（跳过 sudo）"
  [ "$MODE_ALL" = "1" ] && echo "  ✅ shellcheck 已安装（--all 模式，可选依赖就绪）"
elif [ -z "$PM" ]; then
  echo "  ❌ 未检测到 apt/yum/dnf/brew，且缺少: dig perl curl${MODE_ALL:+ / $PKG_SC}"
  echo ""
  echo "════ 手动安装指引（按你的系统选一条） ════"
  echo "  Debian/Ubuntu/WSL:   sudo apt-get install -y dnsutils perl curl"
  echo "  RHEL/CentOS/Fedora:  sudo dnf install -y bind-utils perl curl   (或 sudo yum ...)"
  echo "  macOS (Homebrew):    brew install bind perl curl"
  echo "  Alpine:              apk add bind-tools perl curl"
  echo "  Arch Linux:          sudo pacman -S bind perl curl"
  echo "  openSUSE:            sudo zypper install -y bind-utils perl curl"
  echo "  静态二进制(无包管理器): 从 https://github.com/ 搜索 dig/perl 静态包，或改用系统包管理"
  [ "$MODE_ALL" = "1" ] && echo ""
  [ "$MODE_ALL" = "1" ] && echo "  可选依赖 shellcheck（--all 模式需要）:"
  [ "$MODE_ALL" = "1" ] && echo "    Debian/Ubuntu: sudo apt-get install -y shellcheck | macOS: brew install shellcheck | Arch: sudo pacman -S shellcheck | openSUSE: sudo zypper install -y ShellCheck"
  echo ""
  echo "  💡 极简/精简环境（busybox 等）建议：改用 WSL(Ubuntu) 或完整发行版——"
  echo "     本工具集依赖 dig + perl + curl，busybox 的替代命令不完整"
  echo "  📌 装好后重新运行: bash install.sh"
  exit 1
else
  if [ ${#NEED[@]} -gt 0 ]; then
    echo "  必需缺失: ${NEED[*]}"
  fi
  if [ ${#NEED_SC[@]} -gt 0 ]; then
    echo "  可选缺失(--all): ${NEED_SC[*]}（shellcheck）"
  fi
  [ ${#NEED[@]} -eq 0 ] && [ ${#NEED_SC[@]} -gt 0 ] && echo "  必需依赖已齐，仅补装可选依赖 shellcheck"
  echo "  包管理器: $PM"
  case "$PM" in
    apt)
      echo "════ 安装（apt-get） ════"
      if $SUDO apt-get update && $SUDO apt-get install -y "${NEED[@]}" "${NEED_SC[@]}"; then
        :
      else
        echo "❌ 安装失败（可能需 sudo 权限或网络问题）"
        exit 1
      fi
      ;;
    dnf)
      echo "════ 安装（dnf） ════"
      if $SUDO dnf install -y "${NEED[@]}" "${NEED_SC[@]}"; then
        :
      else
        echo "❌ 安装失败"
        exit 1
      fi
      ;;
    yum)
      echo "════ 安装（yum） ════"
      if $SUDO yum install -y "${NEED[@]}" "${NEED_SC[@]}"; then
        :
      else
        echo "❌ 安装失败"
        exit 1
      fi
      ;;
    brew)
      echo "════ 安装（brew） ════"
      if brew install "${NEED[@]}" "${NEED_SC[@]}"; then
        :
      else
        echo "❌ 安装失败"
        exit 1
      fi
      ;;
    apk|pacman|zypper)
      # 无自动分支的包管理器：必需项给出对应命令，可选项单独提示
      case "$PM" in
        apk)    CMD="$SUDO apk add ${NEED[*]}" ;;
        pacman) CMD="$SUDO pacman -S ${NEED[*]}" ;;
        zypper) CMD="$SUDO zypper install -y ${NEED[*]}" ;;
      esac
      echo "  ⚠️ $PM 暂未内置自动安装分支，请手动执行:"
      echo "    $CMD"
      [ ${#NEED_SC[@]} -gt 0 ] && echo "    可选 shellcheck: ${PKG_SC}（Debian 系 sudo apt-get install -y shellcheck / macOS brew install shellcheck）"
      echo "  📌 装好后重新运行: bash install.sh"
      exit 1
      ;;
  esac
fi

echo ""
echo "════ 验证安装（强制校验） ════"
FAIL=0
if command -v dig >/dev/null 2>&1; then
  echo "  ✅ dig: $(dig -v 2>&1 | head -1)"
  if dig -h 2>&1 | grep -q '+\[no\]tls'; then
    echo "       DoT 检测: 支持（dig +tls 可用）"
  else
    echo "  ⚠️  DoT 检测: 当前 dig 不支持 +tls（bind < 9.18）——DoT 检测降级为端口级，其余功能不受影响"
  fi
else echo "  ❌ dig 未安装"; FAIL=1; fi
if command -v perl >/dev/null 2>&1; then echo "  ✅ perl: $(perl -v 2>/dev/null | sed -n '2p')"; else echo "  ❌ perl 未安装"; FAIL=1; fi
if command -v curl >/dev/null 2>&1; then echo "  ✅ curl: $(curl --version | head -1)"; else echo "  ⚠️  curl 未安装（DoH检测降级为端口级，不影响主功能）"; fi
if [ "$MODE_ALL" = "1" ]; then
  if command -v shellcheck >/dev/null 2>&1; then
    echo "  ✅ shellcheck: $(shellcheck --version 2>/dev/null | grep -m1 '^version:')"
  else
    echo "  ❌ shellcheck 未安装（--all 模式要求）"; FAIL=1
  fi
fi

if [ "$FAIL" = "1" ]; then
  echo ""
  echo "  ❌ 依赖安装不完整，请检查网络/权限后重试，或手动安装"
  exit 1
fi

echo ""
echo "════ 可选依赖检测 ════"
if command -v shellcheck >/dev/null 2>&1; then
  echo "  ✅ shellcheck: $(shellcheck --version 2>/dev/null | grep -m1 '^version:')"
else
  echo "  ⚠️  shellcheck 未安装（可选，不影响主功能）——verify.sh 的 shell 静态检查会跳过该项"
  if [ -t 0 ] && [ -n "$PM" ]; then
    read -r -p "  是否现在一并安装？(y/N): " ANS
    if [ "$ANS" = "y" ] || [ "$ANS" = "Y" ]; then
      echo "════ 安装 shellcheck（可选依赖） ════"
      case "$PM" in
        apt) if $SUDO apt-get update >/dev/null 2>&1 && $SUDO apt-get install -y "$PKG_SC" >/dev/null 2>&1; then echo "  ✅ 安装成功"; else echo "  ❌ 安装失败（可能需 sudo 权限或网络问题）"; fi ;;
        dnf) if $SUDO dnf install -y "$PKG_SC" >/dev/null 2>&1; then echo "  ✅ 安装成功"; else echo "  ❌ 安装失败"; fi ;;
        yum) if $SUDO yum install -y "$PKG_SC" >/dev/null 2>&1; then echo "  ✅ 安装成功"; else echo "  ❌ 安装失败"; fi ;;
        brew) if brew install "$PKG_SC" >/dev/null 2>&1; then echo "  ✅ 安装成功"; else echo "  ❌ 安装失败"; fi ;;
        apk|pacman|zypper) echo "  ⚠️ $PM 暂无自动分支，请手动: ${PKG_SC}（Debian 系 sudo apt-get install -y shellcheck / macOS brew install shellcheck）" ;;
      esac
      if command -v shellcheck >/dev/null 2>&1; then
        echo "  ✅ shellcheck 就绪: $(shellcheck --version 2>/dev/null | grep -m1 '^version:')"
      else
        echo "  ⚠️ 未安装成功，可稍后重试: bash install.sh --all"
      fi
    else
      echo "  好的，跳过（想装随时: bash install.sh --all；代码质量已由 CI 兜底）"
    fi
  else
    echo "     · 想装: bash install.sh --all   或手动: sudo apt-get install -y shellcheck / brew install shellcheck"
    echo "     · 不装也行：代码质量已由 CI 兜底（GitHub Actions 每轮自动 shellcheck）"
  fi
fi

echo ""
# 依赖就绪后顺手装 shell 补全（幂等；不想装可忽略，或跑 bash install.sh --completions 单独补装）
install_completions

echo ""
if [ "$MODE" = "--smoke" ]; then
  echo "════ 依赖就绪，运行冒烟测试 ════"
  bash smoke_test.sh
else
  echo "✅ 依赖就绪！下一步（任选）:"
  echo "  bash install.sh --smoke            # 一键验证环境（24项自动化）"
  echo "  bash smoke_test.sh                 # 验证环境（24项自动化）"
  echo "  bash verify.sh                     # 一键全量深度自检（含单测/compare/trends，约5分钟）"
  echo "  bash verify.sh --strict            # 严格模式（shellcheck 未装算失败，开发者用）"
  echo "  bash dns-test.sh                   # 交互引导测试（选DNS/版本/专项）"
  echo "  bash lite.sh 223.5.5.5 0           # 快速测一个DNS"
  echo "  bash compare.sh 223.5.5.5 119.29.29.29  # 多DNS横向对比"
  echo "  bash trends.sh --html              # 趋势洞察（积累compare数据后）"
fi
