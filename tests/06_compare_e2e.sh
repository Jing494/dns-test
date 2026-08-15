#!/bin/bash
# ============================================================================
# 纯 bash 轻量断言单测：compare.sh 端到端 + trends --prune（离线，mock dig/ping）
# 覆盖: --watch 参数校验（缺值/非法值/0）、当前系统DNS检测与👤标记（头部/表格/推荐注记，
#       文本+HTML+MD 三出口）、环比 Δ 计算（fixture 对比）、提供商标签（三出口+抖动+JSON jitter_ms）、
#       预设组名展开（ali 含 IPv6）、未知词报错、trends --prune 保留/删除/校验
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
  rm -rf trends "$STUB"   # trends.sh 聚合时会 mkdir trends/（产物目录），测试不留痕
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

echo "═══ compare.sh e2e: 提供商标签 + 延迟抖动 ═══"
# 预设内 DNS（223.5.5.5=阿里）应带标签；自定义 DNS 不带
OUT4=$(bash compare.sh 223.5.5.5 --no-save 2>&1)
echo "$OUT4" | grep -q "223.5.5.5·阿里DNS-v4-1" && ok "文本结果表带提供商标签" || notok "文本结果表缺标签"
echo "$OUT4" | grep -q "抖动±" && ok "探测行带抖动" || notok "探测行缺抖动"
bash compare.sh 223.5.5.5 --md >/dev/null 2>&1
grep -q "223.5.5.5（阿里DNS-v4-1）" results/report.md && ok "MD 表带标签" || notok "MD 表缺标签"
grep -qE "ms±[0-9]+" results/report.md && ok "MD 延迟带抖动" || notok "MD 延迟缺抖动"
bash compare.sh 223.5.5.5 --html >/dev/null 2>&1
grep -q "class='pname'>阿里DNS-v4-1" results/report.html && ok "HTML addr 带标签副行" || notok "HTML 缺标签副行"
grep -q "jitter_ms" results/compare-*.json 2>/dev/null && ok "JSON 含 jitter_ms 字段" || notok "JSON 缺 jitter_ms"

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

echo "═══ compare.sh e2e: --rounds/--keep 校验 + --json stdout ═══"
bash compare.sh 223.5.5.5 --rounds 3 2>&1 | grep -q "\-\-rounds 仅与 --watch" && ok "--rounds 单独用报错" || notok "--rounds 单独用未报错"
bash compare.sh 223.5.5.5 --keep 5 2>&1 | grep -q "\-\-keep 仅与 --watch" && ok "--keep 单独用报错" || notok "--keep 单独用未报错"
bash compare.sh 223.5.5.5 --watch 1 --keep 0 2>&1 | grep -q "正整数" && ok "--keep 0 报错" || notok "--keep 0 未报错"
JOUT=$(bash compare.sh 223.5.5.5 --json 2>/dev/null)
echo "$JOUT" | grep -q '"tool": "dns-test/compare.sh"' && ok "--json 输出到 stdout" || notok "--json 未输出 stdout"
bash compare.sh 223.5.5.5 --json --no-save 2>&1 | grep -q "已忽略 --no-save" && ok "--json 冲突忽略 --no-save" || notok "--json/--no-save 冲突未处理"
bash compare.sh 223.5.5.5 --watch 1 --rounds 1 --json 2>&1 | grep -q "已忽略 --json" && ok "采集模式剔除 --json" || notok "采集模式未剔除 --json"

echo "═══ compare.sh e2e: --watch+--open 子轮HTML回归（修复：--open隐含的--html只在父进程生效） ═══"
rm -f results/report.html
bash compare.sh 223.5.5.5 --watch 1 --rounds 1 --open >/dev/null 2>&1
[ -f results/report.html ] && ok "--watch+--open(无--html) 子轮生成HTML" || notok "子轮丢HTML（回归）"

echo "═══ compare.sh e2e: --watch+--keep 自动清理 ═══"
rm -f results/compare-*.json
for ts in 20260810 20260811 20260812; do
  echo "{\"tool\":\"x\",\"timestamp\":\"${ts} 00:00:00 +0800\",\"dns\":[{\"addr\":\"223.5.5.5\",\"score\":\"90\",\"stab\":\"100\",\"delay_ms\":10}]}" > "results/compare-${ts}-000000.json"
done
KW=$(bash compare.sh 223.5.5.5 --watch 1 --rounds 1 --keep 2 2>&1)
echo "$KW" | grep -q "已清理 2 份旧JSON" && ok "--keep 清理判定(4→2,删2)" || notok "--keep 清理判定错误"
KNOW=$(ls results/compare-*.json 2>/dev/null | wc -l | tr -d ' ')
[ "$KNOW" = "2" ] && ok "--keep 后留存2份" || notok "--keep 后留存${KNOW}份(应2)"

echo "═══ trends.sh: 标签/P95/同图总图/时段分析/计数修复 ═══"
rm -rf results; mkdir -p results
# 2 DNS × 6 轮：3份20点档(延迟高) + 3份08点档(延迟低) → 时段分析可出、同图总图可出
for i in 1 2 3; do
  cat > "results/compare-2026081${i}-200000.json" <<EOF3
{"tool":"dns-test/compare.sh","version":"v2026.08.16","timestamp":"2026-08-1${i} 20:00:00 +0800","mode":"lite","cost_s":10,
 "dns":[{"addr":"223.5.5.5","score":"8${i}","stab":"100","delay_ms":$((80+i*5)),"reachable":true},
        {"addr":"119.29.29.29","score":"7${i}","stab":"95","delay_ms":$((90+i*5)),"reachable":true}]}
EOF3
  cat > "results/compare-2026081${i}-080000.json" <<EOF3
{"tool":"dns-test/compare.sh","version":"v2026.08.16","timestamp":"2026-08-1${i} 08:00:00 +0800","mode":"lite","cost_s":10,
 "dns":[{"addr":"223.5.5.5","score":"9${i}","stab":"100","delay_ms":$((10+i)),"reachable":true},
        {"addr":"119.29.29.29","score":"8${i}","stab":"95","delay_ms":$((15+i)),"reachable":true}]}
EOF3
done
TT=$(bash trends.sh --html 2>&1)
echo "$TT" | grep -q "6次采集" && ok "采集计数正确(6份=6次)" || notok "采集计数错误"
echo "$TT" | grep -q "2026-08-13 20:00$" && ok "期间终点正常显示" || notok "期间终点为空"
echo "$TT" | grep -q "223.5.5.5·阿里DNS-v4-1" && ok "文本表带提供商标签" || notok "文本表缺标签"
echo "$TT" | grep -q "P95延迟" && ok "文本表含P95列" || notok "文本表缺P95列"
echo "$TT" | grep -q "最差 20:00 均延90.0ms" && ok "时段分析标出最差时段" || notok "时段分析缺最差时段"
grep -q "综合评分对比（2个DNS × 6轮）" trends/report.html && ok "HTML 多DNS同图总图(评分)" || notok "HTML 缺评分总图"
grep -q "延迟对比 (ms) — 越低越好（2个DNS × 6轮）" trends/report.html && ok "HTML 多DNS同图总图(延迟)" || notok "HTML 缺延迟总图"
grep -q "class='legend'" trends/report.html && ok "总图图例存在" || notok "总图缺图例"
grep -q "class='pname'>阿里DNS-v4-1" trends/report.html && ok "HTML 总览表带标签副行" || notok "HTML 缺标签副行"
grep -q "P95延迟" trends/report.html && ok "HTML 表含P95列" || notok "HTML 缺P95列"
bash trends.sh --since 2026/08/01 2>&1 | grep -q "YYYY-MM-DD" && ok "--since 非法格式报错" || notok "--since 未校验格式"
bash trends.sh --open 2>&1 | grep -q "已在浏览器打开\|手动打开" && ok "--open 输出打开/降级提示" || notok "--open 无提示"

echo "═══ trends.sh: 日级分析 + 模板化图回归（chart_begin/chart_end 公共框架） ═══"
# 夹具跨 08-11/12/13 三天 → 日级分析应出；单图/总图经模板化后仍完整
TD=$(bash trends.sh 2>&1)
echo "$TD" | grep -q "日级分析（按天聚合，数据跨≥2天才显示）" && ok "文本日级分析小节" || notok "文本缺日级分析"
echo "$TD" | grep -q "08-12  均分" && ok "日级行(08-12均分)" || notok "日级行缺失"
echo "$TD" | grep -q "08-13  均分" && ok "日级行(08-13均分)" || notok "日级行缺失(末日)"
NP=$(grep -c "<polyline" trends/report.html)
[ "$NP" = "8" ] && ok "模板化后折线数=8(2总图×2DNS+4单图)" || notok "折线数=${NP}(应8)"
grep -q "综合评分趋势" trends/report.html && ok "单DNS图标题正常(模板化回归)" || notok "单DNS图标题丢失"
grep -q "class='insight'" trends/report.html && ok "HTML 洞察卡存在" || notok "HTML 缺洞察卡"
grep -q "日级分析（跨≥2天）" trends/report.html && ok "HTML 洞察卡含日级" || notok "HTML 洞察卡缺日级"

echo "═══ compare.sh e2e: --watch 断点续采 + 采集模式 HTML 自动刷新 ═══"
mkdir -p results
# 造同签名状态（watch=1|rounds=3|dns=223.5.5.5，已完成2轮）→ 应从第3轮继续，跑满后状态清除
printf 'watch=1|rounds=3|dns=223.5.5.5\n2\n' > results/.compare-watch-state
RS=$(bash compare.sh 223.5.5.5 --watch 1 --rounds 3 --html 2>&1)
echo "$RS" | grep -q "断点续采: 上次同参数采集已完成 2 轮，从第 3 轮继续" && ok "断点续采提示" || notok "断点续采提示缺失"
echo "$RS" | grep -q "第 3 轮采集" && ok "续采从第3轮开始" || notok "续采轮号错误"
[ ! -f results/.compare-watch-state ] && ok "跑满--rounds后状态清除" || notok "状态未清除"
grep -q "http-equiv='refresh' content='60'" results/report.html && ok "采集模式HTML自动刷新(watch 1→60s)" || notok "HTML缺自动刷新"
# 签名不匹配（DNS不同）→ 从第1轮重新开始
printf 'watch=1|rounds=3|dns=119.29.29.29\n2\n' > results/.compare-watch-state
RS2=$(bash compare.sh 223.5.5.5 --watch 1 --rounds 1 2>&1)
echo "$RS2" | grep -q "第 1 轮采集" && ok "签名不匹配从头开始" || notok "签名不匹配仍续采"
rm -f results/.compare-watch-state
# 非采集模式 HTML 不带自动刷新（回归：COMPARE_REFRESH_SEC 未设时不注入 meta）
bash compare.sh 223.5.5.5 --html >/dev/null 2>&1
grep -q "http-equiv='refresh'" results/report.html && notok "非采集模式误注入refresh" || ok "非采集模式无refresh"

echo ""
echo "═══ 结果: $PASS 通过 / $FAIL 失败 ═══"
[ "$FAIL" = "0" ]
