#!/bin/bash
# ============================================================================
# 纯 bash 轻量断言单测：lib/trends_lib.sh 纯函数（分位数/斜率趋势判定）
# 覆盖: trends_percentile（空/单值/偶数样本/奇数样本/P95 取位/边界 clamp）
#       trends_slope_judge（score/delay × 显著升/显著降/微升/微降/平稳 全 10 态）
#       + trends.sh 端到端等价冒烟（P50/P95/趋势箭头与口径一致）
# 用法: bash tests/08_trends_lib.sh   （退出码 0=全过 1=有失败）
# ============================================================================
cd "$(dirname "$0")/.." || exit 1
source lib/trends_lib.sh

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); echo "  ✅ $1"; }
notok() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }

echo "═══ trends_percentile：空/单值 ═══"
[ "$(trends_percentile "" 0.5)" = "-" ] && ok "空输入 → -" || notok "空输入异常"
V=$(printf '20\n')
[ "$(trends_percentile "$V" 0.5)" = "-" ] && ok "单值 → -" || notok "单值应输出 -"

echo "═══ trends_percentile：P50 取位 ═══"
V=$(printf '30\n10\n20\n')  # 排序后 10 20 30
[ "$(trends_percentile "$V" 0.5)" = "20" ] && ok "奇数3样本 P50=中位20" || notok "P50(3样本)异常"
V=$(printf '40\n10\n30\n20\n')  # 排序后 10 20 30 40
[ "$(trends_percentile "$V" 0.5)" = "20" ] && ok "偶数4样本 P50=第2位20" || notok "P50(4样本)异常"
V=$(printf '9\n1\n')
[ "$(trends_percentile "$V" 0.5)" = "1" ] && ok "2样本 P50=第1位" || notok "P50(2样本)异常"

echo "═══ trends_percentile：P95 取位（口径: int(NR*0.95+0.5)） ═══"
V=$(seq 1 20 | tr '\n' '\n')  # 1..20: int(20*0.95+0.5)=int(19.499..)=19
[ "$(trends_percentile "$V" 0.95)" = "19" ] && ok "20样本 P95=第19位" || notok "P95(20样本)异常: $(trends_percentile "$V" 0.95)"
V=$(seq 1 10)  # 10*0.95=9.5, int(9.5+0.5)=10 → 第10位（最大值）
[ "$(trends_percentile "$V" 0.95)" = "10" ] && ok "10样本 P95=第10位" || notok "P95(10样本)异常: $(trends_percentile "$V" 0.95)"
V=$(seq 1 100)
[ "$(trends_percentile "$V" 0.95)" = "95" ] && ok "100样本 P95=第95位" || notok "P95(100样本)异常"
V=$(seq 1 3)  # int(3*0.95+0.5)=int(3.35)=3 → clamp 上界=最大值
[ "$(trends_percentile "$V" 0.95)" = "3" ] && ok "3样本 P95=第3位(clamp)" || notok "P95(3样本)异常"

echo "═══ trends_slope_judge：score 全 5 态 ═══"
[ "$(trends_slope_judge 0.5 80 90 score)" = "↑ 变好" ] && ok "score 斜率显著升 → ↑ 变好" || notok "score 显著升异常"
[ "$(trends_slope_judge -0.5 90 80 score)" = "↓ 变差" ] && ok "score 斜率显著降 → ↓ 变差" || notok "score 显著降异常"
[ "$(trends_slope_judge 0 80 90 score)" = "↗ 微升" ] && ok "score 平稳档首尾升 → ↗ 微升" || notok "score 微升异常"
[ "$(trends_slope_judge 0 90 80 score)" = "↘ 微降" ] && ok "score 平稳档首尾降 → ↘ 微降" || notok "score 微降异常"
[ "$(trends_slope_judge 0 85 85 score)" = "→ 平稳" ] && ok "score 全等 → → 平稳" || notok "score 平稳异常"

echo "═══ trends_slope_judge：delay 全 5 态（好坏方向反转） ═══"
[ "$(trends_slope_judge 0.5 20 30 delay)" = "↓ 变差" ] && ok "delay 斜率显著升 → ↓ 变差" || notok "delay 显著升异常"
[ "$(trends_slope_judge -0.5 30 20 delay)" = "↑ 变好" ] && ok "delay 斜率显著降 → ↑ 变好" || notok "delay 显著降异常"
[ "$(trends_slope_judge 0 20 30 delay)" = "↘ 变差" ] && ok "delay 平稳档首尾升 → ↘ 变差" || notok "delay 微升异常"
[ "$(trends_slope_judge 0 30 20 delay)" = "↗ 变好" ] && ok "delay 平稳档首尾降 → ↗ 变好" || notok "delay 微降异常"
[ "$(trends_slope_judge 0 25 25 delay)" = "→ 平稳" ] && ok "delay 全等 → → 平稳" || notok "delay 平稳异常"

echo "═══ trends.sh 端到端等价冒烟（lib 函数接入主链路） ═══"
TRD=$(mktemp -d); TOUT=$(mktemp -d)
printf '{"tool":"x","timestamp":"2026-08-13 08:00:00 +0800","mode":"lite","dns":[{"addr":"223.5.5.5","score":"80","stab":"100","delay_ms":10,"reachable":true}]}\n' > "$TRD/compare-20260813-080000.json"
printf '{"tool":"x","timestamp":"2026-08-14 08:00:00 +0800","mode":"lite","dns":[{"addr":"223.5.5.5","score":"90","stab":"100","delay_ms":20,"reachable":true}]}\n' > "$TRD/compare-20260814-080000.json"
J=$(COMPARE_RESULTS_DIR="$TRD" TRENDS_DIR="$TOUT" bash trends.sh --json 2>/dev/null)
echo "$J" | grep -q '"score_trend": "↗ 微升"' && ok "2样本 score ↗ 微升(首尾判定)" || notok "score_trend 异常"
echo "$J" | grep -q '"delay_trend": "↘ 变差"' && ok "2样本 delay ↘ 变差(首尾判定)" || notok "delay_trend 异常"
echo "$J" | grep -q '"delay_p50_ms": 10' && ok "2样本 P50=10" || notok "P50 异常"
echo "$J" | grep -q '"delay_p95_ms": 20' && ok "2样本 P95=20(int(2*0.95+0.5)=1? 应=第2位20)" || notok "P95 异常"
rm -rf "$TRD" "$TOUT"

echo ""
echo "════════ tests/08 结果: ✅$PASS 通过  ❌$FAIL 失败 ════════"
[ "$FAIL" = "0" ]
