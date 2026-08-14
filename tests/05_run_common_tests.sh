#!/bin/bash
# ============================================================================
# 纯 bash 轻量断言单测：run_common_tests（lite 计分口径离线回归）
# 用 mock dig/ping 固定响应，验证 lite 版各测试项计分与总分口径（含稳定性降轮），
# 并回归 CONFIG_DOMAINS 安全解析（不 source、注入不执行）
# 用法: bash tests/05_run_common_tests.sh   （退出码 0=全过 1=有失败）
# 说明: 不发起任何真实网络请求；mock dig 按查询域名/类型/+short 返回固定响应
# ============================================================================
cd "$(dirname "$0")/.." || exit 1

STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT

# --- mock dig：覆盖 run_common_tests lite 全部查询形态 ---
cat > "$STUB/dig" <<'EOF'
#!/bin/bash
args=("$@")
name="" type="A" short=0
for a in "${args[@]}"; do
  case "$a" in
    +short) short=1 ;;
    -x) ;;
    AAAA) type=AAAA ;;
    MX) type=MX ;;
    NS) type=NS ;;
    TXT) type=TXT ;;
    @*|+*) ;;
    *) [ -z "$name" ] && name="$a" ;;
  esac
done
[ "$type" = "AAAA" ] && { echo ""; exit 0; }
if [ "$type" != "A" ]; then
  # MX/NS/TXT +short 固定响应
  case "$name" in
    qq.com)     echo "mx.example.com" ;;
    baidu.com)  echo "ns.example.com" ;;
    google.com) echo '"v=spf1 include:example.com ~all"' ;;
    *)          echo "txt.example.com" ;;
  esac
  exit 0
fi
if [ "$short" = "0" ]; then
  # A 完整输出（含 Query time，供延迟/稳定性解析）
  if [ "$name" = "this-domain-does-not-exist-12345.com" ]; then
    echo ";; status: NXDOMAIN"
  else
    echo ";; flags: qr rd ra; QUERY: 1, ANSWER: 1"
    echo ""
    echo ";; ANSWER SECTION:"
    echo "${name}.	300	IN	A	1.2.3.4"
    echo ""
    echo ";; Query time: 10 msec"
  fi
  exit 0
fi
# A +short：一律返回固定 IP
echo "1.2.3.4"
EOF
chmod +x "$STUB/dig"

# --- mock ping：输出 min/avg 行，避免真实网络调用 ---
cat > "$STUB/ping" <<'EOF'
#!/bin/bash
echo "rtt min/avg/max/mdev = 1.1/2.2/3.3/0.1 ms"
EOF
chmod +x "$STUB/ping"

# 无 perl 的环境也兼容（stub 兜底，与 tests/03 一致）；dig 已在 $STUB 内
for c in perl; do
  command -v "$c" >/dev/null 2>&1 || { printf '#!/bin/bash\nexit 0\n' > "$STUB/$c"; chmod +x "$STUB/$c"; }
done

export TMPDIR="$STUB"
PATH="$STUB:$PATH" source lib/core.sh

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
notok(){ FAIL=$((FAIL+1)); echo "  ❌ $1"; }

echo "═══ run_common_tests(lite) 计分口径 + CONFIG_DOMAINS 安全解析 ═══"

# 1. STAB_ROUNDS 未显式设置：默认 20，lite 将减半为 10
if [ "$STAB_ROUNDS_USER" = "0" ] && [ "$STAB_ROUNDS" = "20" ]; then
  ok "STAB_ROUNDS 默认20，lite 减半为10"
else
  notok "STAB_ROUNDS 默认20 (got user=$STAB_ROUNDS_USER rounds=$STAB_ROUNDS)"
fi

# 2. 执行 lite 全流程（离线，无真实网络），退出码应为 0
OUT=$(PATH="$STUB:$PATH" run_common_tests 8.8.8.8 "mockDNS" lite)
RC=$?
[ "$RC" = "0" ] && ok "run_common_tests(lite) 退出码0" || notok "run_common_tests(lite) 退出码0 (got $RC)"

# 3. 稳定性标题显示 10 次（lite 降轮生效）
if echo "$OUT" | grep -q "稳定性压力测试 (10 次连续查询)"; then
  ok "lite 稳定性降为 10 轮"
else
  notok "lite 稳定性降为 10 轮"
fi

# 4. 确定性计分：AAAA 空响应 → 0/8
if echo "$OUT" | grep -q "AAAA记录: 有记录 0/8 (0%)"; then
  ok "AAAA 空响应 0/8（确定性）"
else
  notok "AAAA 空响应 0/8"
fi

# 5. 综合评分口径 45/53（稳定性 10 轮后 lite 总分 53）
if echo "$OUT" | grep -q "综合评分: 84% (45/53 项通过)"; then
  ok "综合评分口径 45/53"
else
  notok "综合评分口径 45/53"
fi

# 6. DNS 可达（未被预检跳过）
if echo "$OUT" | grep -q "已跳过"; then
  notok "DNS 未被预检跳过"
else
  ok "DNS 可达（未跳过）"
fi

# 7. CONFIG_DOMAINS 安全解析：合法配置覆盖数组，且注入行不执行
CFG="$STUB/domains.conf"
printf 'DOMAINS_MAIN=("a.com" "b.com")\n$(touch "%s/pwned") >/dev/null\n' "$STUB" > "$CFG"
R=$(CONFIG_DOMAINS="$CFG" PATH="$STUB:$PATH" bash -c 'source lib/core.sh; printf "%d:%s" "${#DOMAINS_MAIN[@]}" "${DOMAINS_MAIN[0]}"')
if [ "$R" = "2:a.com" ] && [ ! -f "$STUB/pwned" ]; then
  ok "CONFIG_DOMAINS 合法覆盖 + 注入不执行"
else
  notok "CONFIG_DOMAINS 安全解析 (got $R pwned=$([ -f "$STUB/pwned" ] && echo yes || echo no))"
fi

# 8. CONFIG_DOMAINS 非法 token 行被忽略（不覆盖数组）
CFG2="$STUB/domains2.conf"
printf 'DOMAINS_MAIN=("x.com" "y.com;id")\n' > "$CFG2"
R2=$(CONFIG_DOMAINS="$CFG2" PATH="$STUB:$PATH" bash -c 'source lib/core.sh; printf "%s" "${DOMAINS_MAIN[0]}"')
if [ "$R2" = "www.baidu.com" ]; then
  ok "CONFIG_DOMAINS 非法 token 忽略"
else
  notok "CONFIG_DOMAINS 非法 token 忽略 (got $R2)"
fi

echo ""
echo "════ 结果: $PASS 通过 / $FAIL 失败 ════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
