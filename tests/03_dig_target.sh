#!/bin/bash
# ============================================================================
# 纯 bash 轻量断言单测：测 lib/core.sh 的 dig_target（IPv4/IPv6 一律裸地址透传）
# 用法: bash tests/03_dig_target.sh    （退出码 0=全过 1=有失败）
# 说明: 前 4 条为纯函数断言，不发起任何网络查询。core.sh 加载时会做
#       dig/perl 前置检查（command -v），本测试在临时目录放最小 stub 仅用于
#       通过该检查（真实 dig/perl 存在时也兼容），保证可在无 dig 的 CI 环境跑。
#       第 5 条是 dig 语法自检：用**不可路由**的文档前缀 2001:db8::1 触发 dig 的
#       server 参数解析路径（不会真的查到结果，只验证 dig 没把目标当主机名），
#       本机无真实 dig（走了 stub）时自动跳过。
# ============================================================================
cd "$(dirname "$0")/.." || exit 1

STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
DIG_STUBBED=0
for c in dig perl; do
  if ! command -v "$c" >/dev/null 2>&1; then
    printf '#!/bin/bash\nexit 0\n' > "$STUB/$c"
    chmod +x "$STUB/$c"
    [ "$c" = "dig" ] && DIG_STUBBED=1
  fi
done
[ -d "$STUB" ] && PATH="$STUB:$PATH"

source lib/core.sh

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
notok(){ FAIL=$((FAIL+1)); echo "  ❌ $1"; }

echo "═══ dig_target 单测 ═══"

# 1. IPv4 原样返回
if [ "$(dig_target 8.8.8.8)" = "8.8.8.8" ]; then
  ok "IPv4 原样返回"
else
  notok "IPv4 原样返回 (got: $(dig_target 8.8.8.8))"
fi

# 2. IPv6 原样返回（**不加方括号**）
#    回归背景：dig_target 曾返回 "[240e:...]"，而 dig 的 @server 只接受裸地址/主机名，
#    方括号会被当成主机名解析 → `couldn't get address for '[240e:...]'`（rc=1），
#    于是 dns_health_check 把所有 IPv6 DNS 判为"不可达"，主入口/lite/full/compare 全跳过 v6。
if [ "$(dig_target 240e:52:4800::8888)" = "240e:52:4800::8888" ]; then
  ok "IPv6 原样返回（不加方括号）"
else
  notok "IPv6 原样返回 (got: $(dig_target 240e:52:4800::8888))"
fi

# 3. 特殊 IPv6（loopback / 文档前缀 / 全展开）
if [ "$(dig_target ::1)" = "::1" ] && [ "$(dig_target 2001:db8::1)" = "2001:db8::1" ] \
   && [ "$(dig_target 2001:0db8:0000:0000:0000:0000:0000:0001)" = "2001:0db8:0000:0000:0000:0000:0000:0001" ]; then
  ok "特殊 IPv6 原样返回"
else
  notok "特殊 IPv6 原样返回 (got: $(dig_target ::1) / $(dig_target 2001:db8::1))"
fi

# 4. 空输入返回空（不产生脏输出）
if [ "$(dig_target "")" = "" ]; then
  ok "空输入返回空"
else
  notok "空输入返回空 (got: $(dig_target ""))"
fi

# 5. dig 语法自检：@IPv6 必须被 dig 识别为地址而非主机名
#    判据只用 dig 自己的报错文案：裸地址最多"超时/网络不可达"，绝不会出现 couldn't get address；
#    带方括号则必然出现该报错。因此这条断言等价于"dig_target 不得加方括号"，且不需要 IPv6 连通性。
if [ "$DIG_STUBBED" = "1" ]; then
  echo "  ⏭️  跳过 dig 语法自检（本机无真实 dig，已用 stub）"
else
  _syntax_out=$(dig "@$(dig_target 2001:db8::1)" example.com A +short +time=1 +tries=1 2>&1)
  case "$_syntax_out" in
    *"couldn't get address"*)
      notok "dig 语法自检（@IPv6 被当主机名：dig_target 不得加方括号）" ;;
    *)
      ok "dig 语法自检（@IPv6 裸地址被 dig 识别）" ;;
  esac
fi

echo ""
echo "════ 结果: $PASS 通过 / $FAIL 失败 ════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
