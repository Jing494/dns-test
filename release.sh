#!/bin/bash
# ============================================================================
# 打包发布脚本（防止手动打包遗漏新文件）
# 用法: bash release.sh [版本号]    默认取 lib/version.sh 的 PROJECT_VERSION
# 自动: 排除 .git / results内容 / 其他tar.gz，保留 results 空目录
# 提示: 上传 Release 的命令会打印出来（需 GitHub 令牌）
# 退出码: 0=打包成功  1=参数错误或打包自检未达标
# ============================================================================
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 1
cd "$SCRIPT_DIR" || exit 1
# 版本号单一来源
source "$SCRIPT_DIR/lib/version.sh"

usage() {
  cat <<'EOF'
用法: bash release.sh [版本号]
  版本号       省略时取 lib/version.sh 的 PROJECT_VERSION
  合法格式     vYYYY.MM.N（日期式，如 v2026.08.30）或 vX.Y（语义式，如 v1.18）
  -h, --help   打印本说明
  --version    打印当前版本号
说明: 打包 tar.gz，排除 .git / results 内容 / 其他 tar.gz，保留 results 空目录；
      包内混入日志/报告或缺少 results 目录时拦截发布（退出码 1）。
EOF
}

# ---- 参数解析（先于一切副作用：未知参数不再被当版本号打出垃圾包）----
case "${1:-}" in
  -h|--help|help) usage; exit 0 ;;
  --version)      echo "dns-test ${PROJECT_VERSION} (${PROJECT_RELEASE})"; exit 0 ;;
esac

if [ $# -gt 1 ]; then
  echo "❌ 参数过多：只接受 1 个版本号，实际收到 $# 个：$*"
  echo ""
  usage
  exit 1
fi

VERSION="${1:-$PROJECT_VERSION}"

# 双轨制版本号白名单：vYYYY.MM.N 或 vX.Y（v 可省略）
# 不符合即退出——历史教训：曾把 --help 当版本号打包出 dns-test---help.tar.gz(0字节)
if ! printf '%s' "$VERSION" | grep -qE '^v?[0-9]{4}\.[0-9]{1,2}\.[0-9]+$|^v?[0-9]+\.[0-9]+$'; then
  echo "❌ 非法版本号: $VERSION"
  echo "  合法格式: vYYYY.MM.N（日期式，如 v2026.08.30）或 vX.Y（语义式，如 v1.18）"
  exit 1
fi

OUT="dns-test-${VERSION}.tar.gz"
rm -f "$OUT"

# env.sh 是设备专用本地环境脚本（已 gitignore），不该随发行版分发
tar czf "$OUT" --exclude='.git' --exclude='results/*' --exclude='trends' --exclude='*.tar.gz' \
  --exclude='.trae-html-share-packages' --exclude='./env.sh' . 2>/dev/null

echo "════ 打包完成 ════"
echo "  文件: $OUT ($(du -h "$OUT" | cut -f1))"
echo "  条目: $(tar tzf "$OUT" | wc -l) 个"
BAD=$(tar tzf "$OUT" | grep -cE '\.log|报告')
RSLT=$(tar tzf "$OUT" | grep -c 'results/$')
echo "  日志/报告: ${BAD} 处（应为0）"
echo "  results目录: ${RSLT} 个（应为1，防脚本找不到目录）"
echo ""
# 门禁：混入日志/报告或缺 results 目录 → 拦截发布（不打印上传命令，防止带垃圾出包）
if [ "$BAD" -ne 0 ] || [ "$RSLT" -ne 1 ]; then
  echo "❌ 打包自检未达标（日志/报告=${BAD}，results目录=${RSLT}），已拦截；包保留在 $OUT 供排查"
  exit 1
fi

# 自动获取 release id（需令牌 + 网络；失败则提示手动）
REPO="${REPO:-Jing494/dns-test}"
if [ -n "${GITHUB_TOKEN:-$GH_TOKEN}" ]; then
  TOK="${GITHUB_TOKEN:-$GH_TOKEN}"
  RID=$(curl -s -H "Authorization: Bearer $TOK" "https://api.github.com/repos/$REPO/releases/tags/$VERSION" | grep '"id"' | head -1 | grep -oE '[0-9]+')
  echo "  Release ID: ${RID:-未找到(需先创建tag $VERSION)}"
else
  echo "  Release ID: 未设置令牌，请手动查询或设 GITHUB_TOKEN"
fi
echo ""
echo "上传到 GitHub Release（需令牌）:"
echo "  curl -X POST -H \"Authorization: Bearer <TOKEN>\" -H \"Content-Type: application/gzip\" \\"
echo "    --data-binary @$OUT \\"
if [ -n "$RID" ]; then
  echo "    \"https://uploads.github.com/repos/$REPO/releases/$RID/assets?name=$OUT\""
else
  echo "    \"https://uploads.github.com/repos/$REPO/releases/<RELEASE_ID>/assets?name=$OUT\""
fi
