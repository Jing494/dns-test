#!/bin/bash
# ============================================================================
# 纯 bash 轻量断言单测：测 lib/core.sh 的 dig_target（IPv6 地址加方括号）
# 用法: bash tests/03_dig_target.sh    （退出码 0=全过 1=有失败）
# 说明: dig_target 为纯函数，不发起任何网络查询。core.sh 加载时会做
#       dig/perl 前置检查（command -v），本测试在临时目录放最小 stub 仅用于
#       通过该检查（真实 dig/perl 存在时也兼容），保证可在无 dig 的 CI 环境跑
# ============================================================================
cd "$(dirname "$0")/.." || exit 1

STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
for c in dig perl; do
  if ! command -v "$c" >/dev/null 2>&1; then
    printf '#!/bin/bash\nexit 0\n' > "$STUB/$c"
    chmod +x "$STUB/$c"
  fi
done
[ -d "$STUB" ] && PATH="$STUB:$PATH"

source lib/core.sh

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
notok(){ FAIL=$((FAIL+1)); echo "  ❌ $1"; }

echo "═══ dig_target 单测 ═══"

# 1. IPv4 原样返回（不加方括号，行为与之前完全一致）
if [ "$(dig_target 8.8.8.8)" = "8.8.8.8" ]; then
  ok "IPv4 原样返回"
else
  notok "IPv4 原样返回 (got: $(dig_target 8.8.8.8))"
fi

# 2. IPv6 加方括号（避免 dig 解析歧义）
if [ "$(dig_target 240e:52:4800::8888)" = "[240e:52:4800::8888]" ]; then
  ok "IPv6 加方括号"
else
  notok "IPv6 加方括号 (got: $(dig_target 240e:52:4800::8888))"
fi

# 3. 特殊 IPv6（loopback / 压缩全零）
if [ "$(dig_target ::1)" = "[::1]" ] && [ "$(dig_target 2001:db8::1)" = "[2001:db8::1]" ]; then
  ok "特殊IPv6加方括号"
else
  notok "特殊IPv6加方括号"
fi

# 4. 空输入返回空（不产生脏输出）
if [ "$(dig_target "")" = "" ]; then
  ok "空输入返回空"
else
  notok "空输入返回空 (got: $(dig_target ""))"
fi

echo ""
echo "════ 结果: $PASS 通过 / $FAIL 失败 ════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
