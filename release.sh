#!/bin/bash
# ============================================================================
# 打包发布脚本（防止手动打包遗漏新文件）
# 用法: bash release.sh [版本号]    默认 v2026.08.8
# 自动: 排除 .git / results内容 / 其他tar.gz，保留 results 空目录
# 提示: 上传 Release 的命令会打印出来（需 GitHub 令牌）
# ============================================================================
VERSION="${1:-v2026.08.8}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 1
cd "$SCRIPT_DIR" || exit 1

OUT="dns-test-${VERSION}.tar.gz"
rm -f "$OUT"

tar czf "$OUT" --exclude='.git' --exclude='results/*' --exclude='trends' --exclude='*.tar.gz' . 2>/dev/null

echo "════ 打包完成 ════"
echo "  文件: $OUT ($(du -h "$OUT" | cut -f1))"
echo "  条目: $(tar tzf "$OUT" | wc -l) 个"
echo "  日志/报告: $(tar tzf "$OUT" | grep -cE '\.log|报告') 处（应为0）"
echo "  results目录: $(tar tzf "$OUT" | grep -c 'results/$') 个（应为1，防脚本找不到目录）"
echo ""

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
