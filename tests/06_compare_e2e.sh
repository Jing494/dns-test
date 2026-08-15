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

# --- mock 系统DNS检测源（scutil/resolvectl）：双平台统一到 10.99.99.99 ---
# compare.sh 检测优先级 scutil(macOS) > resolvectl(systemd) > resolv.conf；
# CI 的 ubuntu runner 有 resolvectl（resolv.conf=127.0.0.53 stub）、macOS 有 scutil，
# 不 mock 时"当前系统DNS"随 runner 环境漂移，与断言期望地址对不上。mock 后全平台恒定。
printf '#!/bin/bash\necho "  nameserver[0] : 10.99.99.99"\n' > "$STUB/scutil"
chmod +x "$STUB/scutil"
printf '#!/bin/bash\necho "Global: 10.99.99.99"\n' > "$STUB/resolvectl"
chmod +x "$STUB/resolvectl"
MOCK_CUR_DNS="10.99.99.99"

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
# 当前系统DNS来自上方 mock 的 scutil/resolvectl（恒定 10.99.99.99，不随 runner 环境漂移；
# mock dig 对任意 @server 均可达 → 必入推荐对比）
CUR="$MOCK_CUR_DNS"
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

echo "═══ compare.sh e2e: 趋势报告互链（无→引导 / 有→链接） ═══"
T_BAK=0; [ -f trends/report.html ] && { mv trends/report.html /tmp/t06-tr-bak.html; T_BAK=1; }
bash compare.sh 223.5.5.5 --html >/dev/null 2>&1
grep -q "积累多轮数据后可看趋势" results/report.html && ok "HTML 无趋势报告时显示引导" || notok "无趋势引导缺失"
mkdir -p trends && echo '<html>fake</html>' > trends/report.html   # mkdir：上一轮 trap 会清掉 trends/，目录缺失则重定向失败致互链断言误红
DBG_OUT=$(bash compare.sh 223.5.5.5 --html 2>&1); DBG_RC=$?
[ -n "$DNS_TEST_DEBUG" ] && { echo "DBG rc=$DBG_RC"; echo "$DBG_OUT" | tail -5; ls -la trends/report.html 2>&1; }
grep -q "href='../trends/report.html'" results/report.html && ok "HTML 有趋势报告时带互链" || notok "趋势互链缺失"
rm -f trends/report.html
[ "$T_BAK" = "1" ] && mv /tmp/t06-tr-bak.html trends/report.html
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
echo "$TT" | grep -q "~ 2026-08-13 20:00" && ok "期间终点正常显示" || notok "期间终点为空"
echo "$TT" | grep -q "最新采集:" && ok "数据新鲜度显示(最新采集: N天前)" || notok "缺数据新鲜度"
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

echo "═══ compare.sh e2e: --watch --rounds 预计完成时间 ETA ═══"
printf 'watch=1|rounds=3|dns=223.5.5.5\n2\n' > results/.compare-watch-state
ET=$(bash compare.sh 223.5.5.5 --watch 1 --rounds 3 2>&1)
echo "$ET" | grep -q "预计完成 ≈" && ok "ETA 输出预计完成时间" || notok "ETA 缺失"
echo "$ET" | grep -q "剩 1 轮 × 1 分钟" && ok "ETA 断点续采后剩余轮数正确" || notok "ETA 剩余轮数错误"
rm -f results/.compare-watch-state

echo "═══ trends.sh: --until 窗口 + --alert 值守 + 混采警告 + 数据新鲜度 ═══"
# 用独立数据目录（前面 --watch/断点续采等 mock 采集轮已向默认 results/ 写入今天的 JSON，
# 会污染窗口/均值断言；这里重建确定性夹具 08-11/12/13 各2份共6份）
TRD=/tmp/t06-trends; rm -rf "$TRD" /tmp/t06-trends-out; mkdir -p "$TRD"
for i in 1 2 3; do
  cat > "$TRD/compare-2026081${i}-200000.json" <<EOF4
{"tool":"dns-test/compare.sh","version":"t","timestamp":"2026-08-1${i} 20:0${i}:00 +0800","mode":"lite",
 "dns":[{"addr":"223.5.5.5","score":"8${i}","stab":"100","delay_ms":$((80+i*5)),"reachable":true},
        {"addr":"119.29.29.29","score":"7${i}","stab":"95","delay_ms":$((90+i*5)),"reachable":true}]}
EOF4
  cat > "$TRD/compare-2026081${i}-080000.json" <<EOF4
{"tool":"dns-test/compare.sh","version":"t","timestamp":"2026-08-1${i} 08:0${i}:00 +0800","mode":"lite",
 "dns":[{"addr":"223.5.5.5","score":"9${i}","stab":"100","delay_ms":$((10+i)),"reachable":true},
        {"addr":"119.29.29.29","score":"8${i}","stab":"95","delay_ms":$((15+i)),"reachable":true}]}
EOF4
done
tr() { COMPARE_RESULTS_DIR="$TRD" TRENDS_DIR=/tmp/t06-trends-out bash trends.sh "$@"; }
# --until 08-12（含当日）→ 4次采集；期间改为入选数据口径（非全量文件名范围）
UT=$(tr --until 2026-08-12 2>&1)
echo "$UT" | grep -q "4次采集" && ok "--until 窗口过滤(含当日)" || notok "--until 过滤计数错误"
echo "$UT" | grep -q "期间: 2026-08-11 08:01 ~ 2026-08-12 20:02" && ok "期间改为入选数据口径" || notok "期间口径未随过滤更新"
tr --until 2026/08/12 2>&1 | grep -q "YYYY-MM-DD" && ok "--until 非法格式报错" || notok "--until 未校验格式"
tr --since 2026-08-13 --until 2026-08-11 2>&1 | grep -q "倒挂" && ok "窗口倒挂报错" || notok "倒挂未报错"
# --alert 值守：夹具 223 均值87.0 / 119 均值77.0（80阈值→119命中 exit 3；50阈值→全过 exit 0）
tr --alert 80 >/tmp/t06a.out 2>&1; ARC=$?
[ "$ARC" = "3" ] && ok "--alert 80 命中退出码3" || notok "--alert 80 退出码=$ARC(应3)"
grep -q "评分均值 77.0% 低于阈值 80%" /tmp/t06a.out && ok "告警列出低阈值DNS" || notok "告警未列出DNS"
tr --alert 50 >/dev/null 2>&1; ARC2=$?
[ "$ARC2" = "0" ] && ok "--alert 50 全过退出码0" || notok "--alert 50 退出码=$ARC2(应0)"
tr --alert 0 2>&1 | grep -q "1-100" && ok "--alert 0 报错" || notok "--alert 0 未报错"
# lite/full 混采警告（改一份为 full → 警告；sed -i.bak 兼容 BSD/GNU）
sed -i.bak 's/"mode":"lite"/"mode":"full"/' "$TRD/compare-20260812-200000.json" && rm -f "$TRD/compare-20260812-200000.json.bak"
tr 2>&1 | grep -q "lite 与 full 两种采集模式混合" && ok "混采口径警告" || notok "混采未警告"
sed -i.bak 's/"mode":"full"/"mode":"lite"/' "$TRD/compare-20260812-200000.json" && rm -f "$TRD/compare-20260812-200000.json.bak"
# 数据新鲜度（夹具最新为 2026-08-13 → 应显示"最新采集: N.N天前"）
tr 2>&1 | grep -qE "最新采集: [0-9]+\.[0-9]天前" && ok "数据新鲜度显示" || notok "新鲜度缺失"
rm -rf "$TRD" /tmp/t06-trends-out

echo "═══ trends.sh: 周对比 + 突变检测 + --vs 头对头 + --md 报告 ═══"
# 夹具用相对今天的动态日期（date_days_ago）保证周对比两窗恒有数据：前窗=10天前1轮，近窗=5天前2轮
source lib/compat.sh
D10=$(date_days_ago 10); D5=$(date_days_ago 5)
D10F=${D10//-/}; D5F=${D5//-/}   # 原生替换：tr 已被本文件前段的 tr() 辅助函数覆盖
TRD=/tmp/t06-trends2; rm -rf "$TRD" /tmp/t06-trends-out2; mkdir -p "$TRD"
# 前窗: 223=90分/20ms（该轮胜）；近窗r1: 223=72/22；近窗r2: 223=68/260（延迟突变，负）
cat > "$TRD/compare-${D10F}-080000.json" <<EOF5
{"tool":"x","timestamp":"$D10 08:00:00 +0800","mode":"lite","dns":[
 {"addr":"223.5.5.5","score":"90","stab":"100","delay_ms":20,"reachable":true},
 {"addr":"119.29.29.29","score":"80","stab":"95","delay_ms":30,"reachable":true}]}
EOF5
cat > "$TRD/compare-${D5F}-080000.json" <<EOF5
{"tool":"x","timestamp":"$D5 08:00:00 +0800","mode":"lite","dns":[
 {"addr":"223.5.5.5","score":"72","stab":"100","delay_ms":22,"reachable":true},
 {"addr":"119.29.29.29","score":"80","stab":"95","delay_ms":31,"reachable":true}]}
EOF5
cat > "$TRD/compare-${D5F}-090000.json" <<EOF5
{"tool":"x","timestamp":"$D5 09:00:00 +0800","mode":"lite","dns":[
 {"addr":"223.5.5.5","score":"68","stab":"90","delay_ms":260,"reachable":true},
 {"addr":"119.29.29.29","score":"80","stab":"95","delay_ms":29,"reachable":true}]}
EOF5
tr2() { COMPARE_RESULTS_DIR="$TRD" TRENDS_DIR=/tmp/t06-trends-out2 bash trends.sh "$@"; }
WV=$(tr2 2>&1)
echo "$WV" | grep -qF "评分 90.0%→70.0%（-20.0 ↓）" && ok "周对比Δ评分正确(90→70)" || notok "周对比Δ评分错误"
echo "$WV" | grep -qF "延迟 20.0ms→141.0ms（+121.0ms ↓）" && ok "周对比Δ延迟正确(20→141)" || notok "周对比Δ延迟错误"
echo "$WV" | grep -qF "22ms→260ms（+238ms" && ok "突变检测命中(22→260)" || notok "突变检测未命中"
echo "$WV" | grep -q "1次突增" && ok "突变计数=1" || notok "突变计数错误"
WVS=$(tr2 --vs 223.5.5.5,119.29.29.29 2>&1)
echo "$WVS" | grep -q "223.5.5.5·阿里DNS-v4-1 胜1 ｜ 119.29.29.29·腾讯DNSPod-v4 胜2 ｜ 平0" && ok "--vs 头对头胜负计数(1/2/0)" || notok "--vs 胜负计数错误"
echo "$WVS" | grep -q "同轮对决 3 局" && ok "--vs 对局数=3" || notok "--vs 对局数错误"
echo "$WVS" | grep -q "势均力敌" && ok "--vs 占优判定保守(2/3不触发)" || notok "--vs 判定异常"
# --vs 错误路径
tr2 --vs 2>&1 | grep -q "缺少值" && ok "--vs 缺值报错" || notok "--vs 缺值未报错"
tr2 --vs 223.5.5.5 2>&1 | grep -q "两个不同DNS" && ok "--vs 单值报错" || notok "--vs 单值未报错"
tr2 --vs 8.8.8.8,1.1.1.1 2>&1 | grep -q "不在数据集中" && ok "--vs 数据集外报错" || notok "--vs 越界未报错"
# --md 报告（表行 + 三小节 + 尾注）
MDO=$(tr2 --md --vs 223.5.5.5,119.29.29.29 2>&1)
echo "$MDO" | grep -q "Markdown趋势报告已生成" && ok "--md 生成提示" || notok "--md 无提示"
grep -q "| \`223.5.5.5·阿里DNS-v4-1\` | 3 | 76.7%" /tmp/t06-trends-out2/report.md && ok "--md 总览表行正确" || notok "--md 表行错误"
grep -q "## 周对比" /tmp/t06-trends-out2/report.md && ok "--md 含周对比小节" || notok "--md 缺周对比"
grep -q "## 突变检测" /tmp/t06-trends-out2/report.md && ok "--md 含突变小节" || notok "--md 缺突变"
grep -q "## 头对头" /tmp/t06-trends-out2/report.md && ok "--md 含头对头小节" || notok "--md 缺头对头"
grep -q "bash compare.sh DNS1 DNS2 --watch 30" /tmp/t06-trends-out2/report.md && ok "--md 尾注含采集指引" || notok "--md 缺尾注"

echo "═══ trends.sh: --json 机器可读输出 + --week 可配窗口 ═══"
# --json：stdout 应为纯 JSON（文本全部转 stderr），关键字段齐全且语法合法
JS=$(tr2 --json --alert 95 2>/dev/null)
echo "$JS" | grep -q '"tool": "dns-test/trends.sh"' && ok "--json 工具标识" || notok "--json 缺 tool 字段"
echo "$JS" | grep -q '"mutation_count": 1,' && ok "--json 突变计数=1" || notok "--json 突变计数错误"
echo "$JS" | grep -q '"delta_score": -20.0' && ok "--json 周对比Δ评分(无+号JSON数字)" || notok "--json Δ评分错误"
echo "$JS" | grep -q '"hit": true' && ok "--json 告警命中状态" || notok "--json 缺告警状态"
echo "$JS" | grep -q '"week_window_days": 7' && ok "--json 默认周窗口7天" || notok "--json 周窗口字段错误"
command -v python3 >/dev/null 2>&1 && echo "$JS" | python3 -m json.tool >/dev/null 2>&1 \
  && ok "--json 语法合法(json.tool)" || notok "--json 语法非法"
# --json 告警命中时仍 exit 3 且 JSON 已先吐完
tr2 --json --alert 95 >/dev/null 2>&1; [ $? = "3" ] && ok "--json+--alert 命中仍 exit 3" || notok "--json+--alert 退出码错误"
# --week 14：夹具再加 20 天前样本，前窗(14天前~8天前)与近窗(13天内)均有数据才出 Δ
source lib/compat.sh; D20=$(date_days_ago 20); D20F=${D20//-/}
cat > "$TRD/compare-${D20F}-080000.json" <<EOF5
{"tool":"x","timestamp":"$D20 08:00:00 +0800","mode":"lite","dns":[
 {"addr":"223.5.5.5","score":"90","stab":"100","delay_ms":20,"reachable":true},
 {"addr":"119.29.29.29","score":"80","stab":"95","delay_ms":30,"reachable":true}]}
EOF5
WV14=$(tr2 --week 14 2>&1)
echo "$WV14" | grep -q "近14天 vs 前14天" && ok "--week 14 标题正确" || notok "--week 14 标题错误"
# 近14窗含 D10/D5 三轮((90+72+68)/3=76.7)，前14窗含 D20(90)：D20 独享前窗=扩窗生效
echo "$WV14" | grep -qF "评分 90.0%→76.7%" && ok "--week 14 前窗样本入列(90→76.7)" || notok "--week 14 窗口切分错误"
# 默认 --week 7 时 20 天前样本不在任何窗 → 该 DNS 无周对比行（窗口语义边界）
WV7=$(tr2 2>&1)
echo "$WV7" | grep -qF "评分 90.0%→70.0%" && ok "默认7天窗仍按旧语义" || notok "默认窗口被改动"
rm -rf "$TRD" /tmp/t06-trends-out2

echo "═══ trends.sh: --webhook 告警推送（mock curl 抓 payload） ═══"
TRD=/tmp/t06-hook; rm -rf "$TRD" /tmp/t06-hook-out; mkdir -p "$TRD"
cat > "$TRD/compare-20260814-080000.json" <<'EOF6'
{"tool":"x","timestamp":"2026-08-14 08:00:00 +0800","mode":"lite","dns":[
 {"addr":"223.5.5.5","score":"50","stab":"100","delay_ms":20,"reachable":true}]}
EOF6
HOOKSTUB=$(mktemp -d)
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/hook.log"\necho "{\\\"ok\\\":true}"\n' "$HOOKSTUB" "$HOOKSTUB" > "$HOOKSTUB/curl"
chmod +x "$HOOKSTUB/curl"
HW=$(COMPARE_RESULTS_DIR="$TRD" TRENDS_DIR=/tmp/t06-hook-out PATH="$HOOKSTUB:$PATH" \
  bash trends.sh --alert 70 --webhook https://open.feishu.cn/open-apis/bot/v2/hook/TESTKEY 2>&1)
echo "$HW" | grep -q "📡 webhook 已推送" && ok "告警命中触发推送提示" || notok "推送提示缺失"
grep -q '"msg_type":"text"' "$HOOKSTUB/hook.log" && ok "飞书 payload 形态正确" || notok "飞书 payload 错误"
grep -q "TESTKEY" "$HOOKSTUB/hook.log" && ok "推送到指定 URL" || notok "URL 错误"
grep -q "低于阈值 70" "$HOOKSTUB/hook.log" && ok "payload 含告警详情" || notok "payload 缺详情"
# 告警未命中 → 不推送（hook.log 不新增）
BEFORE=$(wc -l < "$HOOKSTUB/hook.log")
COMPARE_RESULTS_DIR="$TRD" TRENDS_DIR=/tmp/t06-hook-out PATH="$HOOKSTUB:$PATH" \
  bash trends.sh --alert 40 --webhook https://open.feishu.cn/x >/dev/null 2>&1
[ "$(wc -l < "$HOOKSTUB/hook.log")" = "$BEFORE" ] && ok "未命中不推送" || notok "未命中误推送"
# 推送失败（连接拒绝）→ 仅提示不改变 exit 3
HW2=$(COMPARE_RESULTS_DIR="$TRD" TRENDS_DIR=/tmp/t06-hook-out bash trends.sh --alert 70 --webhook https://127.0.0.1:1/h 2>&1 | grep -c "webhook 未推送\|推送失败")
[ "$HW2" -ge 1 ] && ok "推送失败时降级提示" || notok "推送失败时静默"
rm -rf "$TRD" /tmp/t06-hook-out "$HOOKSTUB"

echo "═══ trends.sh: --archive 归档（全量打包 / prune 删前归档） ═══"
TRD=/tmp/t06-arch; rm -rf "$TRD" /tmp/t06-arch-out; mkdir -p "$TRD"
for i in 1 2 3; do
  printf '{"tool":"x","timestamp":"2026-08-1%s 08:00:00 +0800","mode":"lite","dns":[{"addr":"223.5.5.5","score":"90","stab":"100","delay_ms":20,"reachable":true}]}' "$i" \
    > "$TRD/compare-2026081$i-080000.json"
done
# 单独 --archive：全量打包且不删原文件
AR=$(COMPARE_RESULTS_DIR="$TRD" TRENDS_DIR=/tmp/t06-arch-out bash trends.sh --archive 2>&1)
echo "$AR" | grep -q "已全量归档 3 份" && ok "--archive 全量归档提示" || notok "全量归档提示缺失"
ls /tmp/t06-arch-out/archive/full-*.tar.gz >/dev/null 2>&1 && ok "full-*.tar.gz 生成" || notok "full 包未生成"
[ "$(ls "$TRD"/compare-*.json | wc -l | tr -d ' ')" = "3" ] && ok "全量归档不删原文件" || notok "全量归档误删原文件"
tar -tzf /tmp/t06-arch-out/archive/full-*.tar.gz | grep -q "compare-20260811" && ok "full 包内容正确" || notok "full 包内容异常"
# --prune N --archive：被删文件先打包再删
PR=$(COMPARE_RESULTS_DIR="$TRD" TRENDS_DIR=/tmp/t06-arch-out bash trends.sh --prune 1 --archive 2>&1)
echo "$PR" | grep -q "已归档待清理的 2 份" && ok "prune 删前归档提示" || notok "删前归档提示缺失"
tar -tzf /tmp/t06-arch-out/archive/prune-*.tar.gz | grep -q "compare-20260812" && ok "prune 包含被删文件" || notok "prune 包缺被删文件"
[ "$(ls "$TRD"/compare-*.json | wc -l | tr -d ' ')" = "1" ] && ok "prune 后仅存最近1份" || notok "prune 后留存数异常"
# 空数据 --archive：跳过归档不报错
rm -f "$TRD"/*.json
AR2=$(COMPARE_RESULTS_DIR="$TRD" TRENDS_DIR=/tmp/t06-arch-out bash trends.sh --archive 2>&1 | grep -c "暂无 compare")
[ "$AR2" = "1" ] && ok "空数据归档跳过提示" || notok "空数据归档异常"
rm -rf "$TRD" /tmp/t06-arch-out

echo "═══ trends.sh: --export 报障包（数据+报告+doctor）与 HTML 归档小节 ═══"
TRD=/tmp/t06-exp; rm -rf "$TRD" /tmp/t06-exp-out; mkdir -p "$TRD"
printf '{"tool":"x","timestamp":"2026-08-14 08:00:00 +0800","mode":"lite","dns":[{"addr":"223.5.5.5","score":"90","stab":"100","delay_ms":20,"reachable":true}]}' > "$TRD/compare-20260814-080000.json"
EX=$(COMPARE_RESULTS_DIR="$TRD" TRENDS_DIR=/tmp/t06-exp-out bash trends.sh --export --html --csv 2>&1)
echo "$EX" | grep -q "报障包已生成" && ok "--export 生成提示" || notok "--export 提示缺失"
ls /tmp/t06-exp-out/export/dns-test-export-*.tar.gz >/dev/null 2>&1 && ok "export tar 生成" || notok "export tar 未生成"
EXTAR=$(ls /tmp/t06-exp-out/export/dns-test-export-*.tar.gz 2>/dev/null | head -1)
tar -tzf "$EXTAR" | grep -q "results/compare-" && ok "包含数据JSON" || notok "缺数据JSON"
tar -tzf "$EXTAR" | grep -q "trends/report.html" && ok "包含HTML报告" || notok "缺HTML报告"
tar -tzf "$EXTAR" | grep -q "doctor.txt" && ok "包含doctor自检" || notok "缺doctor自检"
# HTML 归档小节：造一个归档包后重新生成 HTML 应列出
mkdir -p /tmp/t06-exp-out/archive
tar -czf /tmp/t06-exp-out/archive/full-20260814.tar.gz -C "$TRD" compare-20260814-080000.json
COMPARE_RESULTS_DIR="$TRD" TRENDS_DIR=/tmp/t06-exp-out bash trends.sh --html >/dev/null 2>&1
grep -q "归档包" /tmp/t06-exp-out/report.html && ok "HTML 含归档包小节" || notok "HTML 缺归档小节"
grep -q "full-20260814.tar.gz" /tmp/t06-exp-out/report.html && ok "HTML 列出归档文件" || notok "HTML 未列出归档文件"
rm -rf "$TRD" /tmp/t06-exp-out

echo ""
echo "═══ 结果: $PASS 通过 / $FAIL 失败 ═══"
[ "$FAIL" = "0" ]
