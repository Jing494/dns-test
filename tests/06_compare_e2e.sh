#!/bin/bash
# ============================================================================
# 纯 bash 轻量断言单测：compare.sh 端到端 + trends --prune（离线，mock dig/ping）
# 覆盖: --watch 参数校验（缺值/非法值/0）、当前系统DNS检测与👤标记（头部/表格/推荐注记，
#       文本+HTML+MD 三出口）、环比 Δ 计算（fixture 对比）、预设组名展开（ali 含 IPv6）、
#       未知词报错、trends --prune 保留/删除/校验
# 用法: bash tests/06_compare_e2e.sh   （退出码 0=全过 1=有失败）
# 说明: 不发起任何真实网络请求；compare.sh 硬编码 results/ 落盘，
#       测试前备份用户 results/ 到沙目录，结束时 trap 原样恢复（防误删历史数据）
# ============================================================================
cd "$(dirname "$0")/.." || exit 1

STUB=$(mktemp -d)

# --- mock dig：延迟探测（Query time）+ lite 全部查询形态 ---
cat > "$STUB/dig" <<'EOF'
#!/bin/bash
args=("$@")
name="" type="A" short=0 at=""
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
[ -n "$at" ] || { echo "MOCK-ERR: dig 缺少 @server" >&2; exit 1; }
[ "$type" = "AAAA" ] && { echo ""; exit 0; }
if [ "$type" != "A" ]; then
  case "$name" in
    qq.com)     echo "mx.example.com" ;;
    baidu.com)  echo "ns.example.com" ;;
    google.com) echo '"v=spf1 include:example.com ~all"' ;;
    *)          echo "txt.example.com" ;;
  esac
  exit 0
fi
if [ "$short" = "0" ]; then
  echo ";; flags: qr rd ra; QUERY: 1, ANSWER: 1"
  echo ""
  echo ";; ANSWER SECTION:"
  echo "${name}.	300	IN	A	1.2.3.4"
  echo ""
  echo ";; Query time: 10 msec"
  exit 0
fi
echo "1.2.3.4"
EOF
chmod +x "$STUB/dig"

# --- mock ping：输出 min/avg 行，避免真实网络调用 ---
printf '#!/bin/bash\necho "rtt min/avg/max/mdev = 1.1/2.2/3.3/0.1 ms"\n' > "$STUB/ping"
chmod +x "$STUB/ping"

# --- 用户 results/ 备份（compare.sh 硬编码 results/ 落盘，测完原样恢复） ---
RESULTS_BAKED=0
if [ -d results ]; then
  mv results "$STUB/results-backup" && RESULTS_BAKED=1
fi
restore_results() {
  if [ "$RESULTS_BAKED" = "1" ]; then
    rm -rf results
    mv "$STUB/results-backup" results
  else
    rm -rf results
  fi
  rm -rf "$STUB"
}
trap restore_results EXIT INT TERM

export PATH="$STUB:$PATH" TMPDIR="$STUB"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
notok(){ FAIL=$((FAIL+1)); echo "  ❌ $1"; }

echo "═══ compare.sh e2e: --watch 参数校验 ═══"
bash compare.sh 223.5.5.5 --watch 2>&1 | grep -q "缺少分钟数值" && ok "--watch 缺值报错" || notok "--watch 缺值未报错"
bash compare.sh 223.5.5.5 --watch abc 2>&1 | grep -q "正整数" && ok "--watch 非法值报错" || notok "--watch 非法值未报错"
bash compare.sh 223.5.5.5 --watch=0 2>&1 | grep -q "正整数" && ok "--watch=0 报错" || notok "--watch=0 未报错"

echo "═══ compare.sh e2e: 当前DNS标记 + 环比Δ + MD/HTML 出口 ═══"
mkdir -p results
cat > "results/compare-20260814-000000.json" <<'EOF'
{
  "tool": "dns-test/compare.sh", "version": "v2026.08.15",
  "timestamp": "2026-08-14 00:00:00 +0800", "mode": "lite", "cost_s": 42,
  "dns": [
    {"addr": "10.96.138.37", "score": "90", "stab": "100", "delay_ms": 20, "reachable": true},
    {"addr": "119.29.29.29", "score": "85", "stab": "90", "delay_ms": 50, "reachable": true}
  ]
}
EOF
# 当前系统DNS取自本机 resolv.conf（mock dig 对任意 @server 均可达 → 必入推荐对比）
CUR=$(sed -n 's/^nameserver \([0-9.]*\).*/\1/p' /etc/resolv.conf | head -1)
if [ -z "$CUR" ]; then
  CUR="10.96.138.37"
  echo "  ⚠️  本机 resolv.conf 无 nameserver，用固定地址替代"
fi
OUT=$(bash compare.sh "$CUR" 119.29.29.29 --md --html 2>&1)
echo "$OUT" | grep -q "👤 当前系统DNS:.*$CUR" && ok "头部列出当前系统DNS($CUR)" || notok "头部未列出当前DNS"
echo "$OUT" | grep -q "当前正在使用，无需切换" && ok "推荐=当前DNS时提示无需切换" || notok "推荐行未提示"
grep -q "👤当前" results/report.html && ok "HTML 含 👤当前 徽章" || notok "HTML 无 👤当前 徽章"
grep -q "当前正在使用" results/report.html && ok "HTML 推荐卡含注记" || notok "HTML 推荐卡无注记"
grep -q "\`$CUR\` 👤" results/report.md && ok "MD 含 👤 标记" || notok "MD 无 👤 标记"
grep -q "当前正在使用" results/report.md && ok "MD 推荐行含注记" || notok "MD 推荐行无注记"
echo "$OUT" | grep -q "环比上次采集" && ok "环比输出存在" || notok "环比输出缺失"
grep -q "Δ评分" results/report.html && ok "HTML Δ列存在" || notok "HTML Δ列缺失"

echo "═══ compare.sh e2e: 预设组名展开 ═══"
OUT2=$(bash compare.sh ali --no-save 2>&1)
echo "$OUT2" | grep -q "对比DNS: 223.5.5.5" && ok "ali 展开含 223.5.5.5" || notok "ali 未展开"
echo "$OUT2" | grep -qE "对比DNS: .*2400:3200" && ok "ali 展开含 IPv6 地址" || notok "ali 缺 IPv6"
OUT3=$(bash compare.sh bogus_name 2>&1)
echo "$OUT3" | grep -q "非法DNS地址: bogus_name" && ok "未知词报非法DNS" || notok "未知词未报错"

echo "═══ trends.sh: --prune 保留策略 ═══"
rm -rf results; mkdir -p results
for ts in 20260810 20260811 20260812 20260813 20260814; do
  cat > "results/compare-${ts}-000000.json" <<EOF2
{"tool":"dns-test/compare.sh","version":"v2026.08.15","timestamp":"${ts} 00:00:00 +0800","mode":"lite","cost_s":10,
 "dns":[{"addr":"223.5.5.5","score":"9${ts: -1}","stab":"100","delay_ms":1${ts: -1},"reachable":true}]}
EOF2
done
PT=$(bash trends.sh --prune 3 2>&1)
echo "$PT" | grep -q "保留最近 3 份，删除 2 份" && ok "prune 判定正确(5→3,删2)" || notok "prune 判定错误"
[ ! -e results/compare-20260810-000000.json ] && [ ! -e results/compare-20260811-000000.json ] && ok "最老2份已删" || notok "旧文件残留"
[ -e results/compare-20260814-000000.json ] && ok "最新份保留" || notok "最新份误删"
echo "$PT" | grep -q "223.5.5.5" && ok "prune 后聚合正常出数" || notok "prune 后聚合无数据"
bash trends.sh --prune 0 2>&1 | grep -q "正整数" && ok "--prune 0 报错" || notok "--prune 0 未报错"

echo ""
echo "═══ 结果: $PASS 通过 / $FAIL 失败 ═══"
[ "$FAIL" = "0" ]
