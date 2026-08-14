#!/bin/bash
# ============================================================================
# 纯 bash 轻量断言单测：测 lib/core.sh 的纯逻辑函数
#   valid_dns_addr  — DNS 地址格式校验（IPv4/IPv6，防注入/误传）
#   is_valid_response — dig 响应有效性判断（过滤通信错误/无服务器/纯 OPT）
#   is_cdn_domain  — CDN 域名判定（结果对比时排除负载均衡差异）
# 用法: bash tests/04_core_functions.sh   （退出码 0=全过 1=有失败）
# 说明: 均为纯函数，不发起网络查询。core.sh 加载时做 dig/perl 前置检查，
#       与 03 同策略：无 dig/perl 时用最小 stub 通过检查（真实存在也兼容）
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

echo "═══ valid_dns_addr 单测 ═══"

# 1. 合法 IPv4
if valid_dns_addr 8.8.8.8 && valid_dns_addr 223.5.5.5 && valid_dns_addr 192.168.1.1; then
  ok "合法IPv4通过"
else
  notok "合法IPv4通过"
fi

# 2. 合法 IPv6（压缩/全展开/带段）
if valid_dns_addr 240e:52:4800::8888 && valid_dns_addr ::1 && valid_dns_addr 2001:db8::1; then
  ok "合法IPv6通过"
else
  notok "合法IPv6通过"
fi

# 3. 非法地址拒绝（注入/超范围/域名/空）
if valid_dns_addr '8.8.8.8;id' || valid_dns_addr '1.1.1.1$(id)' || valid_dns_addr 'www.example.com' || valid_dns_addr '999.999.999.999' || valid_dns_addr ''; then
  notok "非法地址被拒绝"
else
  ok "非法地址被拒绝"
fi

# 4. 非IPv6冒号内容拒绝（非hex字符）
if valid_dns_addr '2001:db8::gggg' || valid_dns_addr 'a:b:c:d:e:f:g:h'; then
  notok "含非法hex的IPv6被拒绝"
else
  ok "含非法hex的IPv6被拒绝"
fi

echo ""
echo "═══ is_valid_response 单测 ═══"

# 5. 空响应 → 无效
if is_valid_response ""; then
  notok "空响应判无效"
else
  ok "空响应判无效"
fi

# 6. 通信错误 → 无效
if is_valid_response "communications error to 223.5.5.5#53: timed out"; then
  notok "通信错误判无效"
else
  ok "通信错误判无效"
fi

# 7. no servers could be reached → 无效
if is_valid_response "no servers could be reached" ; then notok "无服务器判无效"; else ok "无服务器判无效"; fi

# 8. 有效 A 记录 → 有效
if is_valid_response "qq.com. 300 IN A 111.161.64.12"; then
  ok "有效A记录判有效"
else
  notok "有效A记录判有效"
fi

# 9. 纯 OPT（仅 EDNS 杂项段，无任何 IN 记录）→ 无效（真实 dig 输出格式）
if is_valid_response $';; OPT PSEUDOSECTION:\n; EDNS: version: 0, flags:; udp: 1232'; then
  notok "纯OPT判无效"
else
  ok "纯OPT判无效"
fi

# 10. OPT 与 IN 记录并存 → 有效
if is_valid_response ";; OPT PSEUDOSECTION
qq.com. 300 IN A 111.161.64.12"; then
  ok "OPT与IN并存判有效"
else
  notok "OPT与IN并存判有效"
fi

echo ""
echo "═══ is_cdn_domain 单测 ═══"

# 11. CDN 域名判定为真（含百度/腾讯等常见负载均衡域名）
if is_cdn_domain www.baidu.com && is_cdn_domain www.qq.com && is_cdn_domain www.bilibili.com; then
  ok "CDN域名判定正确"
else
  notok "CDN域名判定正确"
fi

# 12. 非 CDN 域名判定为假
if is_cdn_domain example.com || is_cdn_domain dns.google; then
  notok "非CDN域名判定为假"
else
  ok "非CDN域名判定为假"
fi

# 13. 空输入 → 假（不误判）
if is_cdn_domain ""; then
  notok "空输入判为假"
else
  ok "空输入判为假"
fi

echo ""
echo "════ 结果: $PASS 通过 / $FAIL 失败 ════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
