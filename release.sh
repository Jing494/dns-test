#!/bin/bash
# ============================================================================
# 打包发布脚本（防止手动打包遗漏新文件）
# 用法: bash release.sh [版本号]    默认 v2026.08
# 自动: 排除 .git / results内容 / 其他tar.gz，保留 results 空目录
# 提示: 上传 Release 的命令会打印出来（需 GitHub 令牌）
# ============================================================================
VERSION="${1:-v2026.08}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

OUT="dns-test-${VERSION}.tar.gz"
rm -f "$OUT"

tar czf "$OUT" --exclude='.git' --exclude='results/*' --exclude='*.tar.gz' . 2>/dev/null

echo "════ 打包完成 ════"
echo "  文件: $OUT ($(du -h "$OUT" | cut -f1))"
echo "  条目: $(tar tzf "$OUT" | wc -l) 个"
echo "  日志/报告: $(tar tzf "$OUT" | grep -cE '\.log|报告') 处（应为0）"
echo "  results目录: $(tar tzf "$OUT" | grep -c 'results/$') 个（应为1，防脚本找不到目录）"
echo ""
echo "上传到 GitHub Release（需令牌）:"
echo "  curl -X POST -H \"Authorization: Bearer <TOKEN>\" -H \"Content-Type: application/gzip\" \\"
echo "    --data-binary @$OUT \\"
echo "    \"https://uploads.github.com/repos/Jing494/dns-test/releases/<RELEASE_ID>/assets?name=$OUT\""
