#!/bin/bash
# ============================================================================
# 纯 bash 轻量断言单测：run_common_tests（lite 计分口径 + full @server 回归，离线）
# 用 mock dig/ping 固定响应，验证 lite 版各测试项计分与总分口径（含稳定性降轮），
# 并回归 CONFIG_DOMAINS 安全解析（不 source、注入不执行）、dig @server 前缀（漏 @ 会走本地解析器）、
# full 模式 @server 恒为被测地址（for t 遮蔽防护）、ECS_SUBNET 注入拦截、par_run 元字符禁令
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
name="" type="A" short=0 at=""
# 记录被调用的完整参数（MOCK_DIG_LOG 设置时才写），供回归断言检查是否带 @server
[ -n "$MOCK_DIG_LOG" ] && echo "$*" >> "$MOCK_DIG_LOG"
for a in "${args[@]}"; do
  case "$a" in
    +short) short=1 ;;
    -x) ;;
    AAAA) type=AAAA ;;
    MX) type=MX ;;
    NS) type=NS ;;
    TXT) type=TXT ;;
    @*) at=1 ;;
    +*) ;;
    *) [ -z "$name" ] && name="$a" ;;
  esac
done
# 回归断言：run_common_tests 每次 dig 必须带 @server（漏 @ 会走本地解析器，见 core.sh dns_health_check/A记录循环）
[ -n "$at" ] || { echo "MOCK-ERR: dig 缺少 @server（漏 @ 回归）" >&2; exit 1; }
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
# shellcheck disable=SC2043  # 单元素兜底清单，保留 for 形态便于以后追加依赖
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

# 1b. STAB_ROUNDS 空串应视为未设置（lite 才减半；修复前 ${STAB_ROUNDS+x} 把空串当显式设置）
U=$(STAB_ROUNDS="" bash -c 'source lib/core.sh >/dev/null 2>&1; echo "${STAB_ROUNDS_USER:-unset}"' 2>/dev/null)
[ "$U" = "0" ] && ok "STAB_ROUNDS 空串视为未设置(lite减半)" || notok "STAB_ROUNDS 空串被误判为显式设置 (user=$U)"

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
R=$(CONFIG_DOMAINS="$CFG" PATH="$STUB:$PATH" bash -c 'source lib/core.sh; printf "%d:%s" "${#DOMAINS_MAIN[@]}" "${DOMAINS_MAIN[0]}"' 2>/dev/null)
if [ "$R" = "2:a.com" ] && [ ! -f "$STUB/pwned" ]; then
  ok "CONFIG_DOMAINS 合法覆盖 + 注入不执行"
else
  notok "CONFIG_DOMAINS 安全解析 (got $R pwned=$([ -f "$STUB/pwned" ] && echo yes || echo no))"
fi

# 8. CONFIG_DOMAINS 非法 token 行被忽略（不覆盖数组）
CFG2="$STUB/domains2.conf"
printf 'DOMAINS_MAIN=("x.com" "y.com;id")\n' > "$CFG2"
R2=$(CONFIG_DOMAINS="$CFG2" PATH="$STUB:$PATH" bash -c 'source lib/core.sh; printf "%s" "${DOMAINS_MAIN[0]}"' 2>/dev/null)
if [ "$R2" = "www.baidu.com" ]; then
  ok "CONFIG_DOMAINS 非法 token 忽略"
else
  notok "CONFIG_DOMAINS 非法 token 忽略 (got $R2)"
fi

# 9. 回归：dig 必须带 @server（漏 @ 会走本地默认解析器而非目标 DNS，见 core.sh 注释）
rm -f "$STUB/args.log"
MOCK_DIG_LOG="$STUB/args.log" PATH="$STUB:$PATH" dns_health_check 8.8.8.8 >/dev/null 2>&1
sleep 0.2   # 等后台 dig 写日志
if [ -s "$STUB/args.log" ] && ! grep -q '^[^@]' "$STUB/args.log"; then
  ok "dig 均带 @server（漏 @ 回归防护）"
else
  notok "dig 均带 @server（漏 @ 回归防护）"
fi

# 10. full 模式 @server 回归：所有 dig 的 @ 目标只能是 被测DNS/劫持对比基准（防循环变量遮蔽 $t）
# 修复前 full 专有分支的 for t 循环（稳定性延迟/DNSSEC类型/TTL值）会把 $t 遮蔽成
# "10"/"DNSKEY"/"300" 等，导致第 6~15 项全部 dig @错误目标（见 core.sh 审阅#11）
rm -f "$STUB/full.log"
MOCK_DIG_LOG="$STUB/full.log" PATH="$STUB:$PATH" run_common_tests 8.8.8.8 "mockDNS" full >/dev/null 2>&1
# 白名单：@8.8.8.8=被测地址；@[2400:3200::1]/@223.5.5.5=[14]劫持对比基准（mock 下基准可达不降级，降级也放行）
bad_at=$(grep -oE '@[^ ]+' "$STUB/full.log" 2>/dev/null | grep -vxF -e '@8.8.8.8' -e '@[2400:3200::1]' -e '@223.5.5.5' | head -3)
if [ -s "$STUB/full.log" ] && [ -z "$bad_at" ]; then
  ok "full 模式 @server 恒为被测地址/对比基准（for t 遮蔽回归）"
else
  notok "full 模式 @server 出现非白名单目标: ${bad_at:-无日志}"
fi

# 11. ECS_SUBNET 注入回归：非法值（含命令分隔符）加载即回退默认，不得进入 par_run 的 eval
R3=$(ECS_SUBNET='1.2.3.4/24; touch '"$STUB"'/pwned' PATH="$STUB:$PATH" bash -c 'source lib/core.sh; printf "%s" "$ECS_SUBNET"' 2>/dev/null)
if [ "$R3" = "240e:52:4800::/48" ] && [ ! -f "$STUB/pwned" ]; then
  ok "ECS_SUBNET 非法值回退默认（注入拦截）"
else
  notok "ECS_SUBNET 非法值回退默认 (got $R3 pwned=$([ -f "$STUB/pwned" ] && echo yes || echo no))"
fi

# 12. par_run 元字符禁令：命令含 ; & $ ` 时整体拒绝（不执行任何一条）
rm -f "$STUB/inj.out"
# shellcheck disable=SC2034  # P4 只为承接子进程输出防止混入测试输出，值本身不使用
P4=$(PATH="$STUB:$PATH" TMPDIR="$STUB" bash -c 'source lib/core.sh; PARR_CMDS=("dig @8.8.8.8 a.com A +short; touch '"$STUB"'/inj.out"); par_run >/dev/null 2>&1; echo done' 2>/dev/null)
if [ ! -f "$STUB/inj.out" ]; then
  ok "par_run 元字符命令被拒（; 注入不执行）"
else
  notok "par_run 元字符命令被拒（inj.out 出现=未拦截）"
fi

echo ""
echo "════ 结果: $PASS 通过 / $FAIL 失败 ════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
