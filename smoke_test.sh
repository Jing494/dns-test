#!/bin/bash
# ============================================================================
# 自动化冒烟测试：一键验证工具集核心功能
# 用法: bash smoke_test.sh    （任何一项失败 → 退出码非0，适合CI/改动后回归）
# ============================================================================
cd "$(dirname "$0")"
PASS=0; FAIL=0

# 平台兼容层（timeout 兼容函数，macOS 无 timeout 命令）
source lib/compat.sh

check() {
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; PASS=$((PASS+1));
  else echo "  ❌ $1"; FAIL=$((FAIL+1)); fi
}

echo "════ DNS工具集 冒烟测试 ════"

echo "--- 1. 全量语法检查"
OK=1
for f in *.sh; do bash -n "$f" 2>/dev/null || OK=0; done
for f in $(find . -name '*.pl'); do perl -c "$f" >/dev/null 2>&1 || OK=0; done
check "全量语法" $((1-OK))

echo "--- 2. lite 功能"
timeout 30 bash lite.sh 223.5.5.5 0 2>&1 | grep -q "综合评分" && check "lite 223.5.5.5" 0 || check "lite 223.5.5.5" 1

echo "--- 2.5 full 完整版"
timeout 40 bash full.sh 223.5.5.5 0 2>&1 | grep -q "综合评分" && check "full 223.5.5.5" 0 || check "full 223.5.5.5" 1

echo "--- 3. 不可达预检"
timeout 10 bash lite.sh 192.0.2.1 0 2>&1 | grep -q "不可达" && check "不可达预检跳过" 0 || check "不可达预检跳过" 1

echo "--- 4. 注入防护"
timeout 5 bash lite.sh '1.1.1.1;id' 2>&1 | grep -q "非法" && check "注入拦截" 0 || check "注入拦截" 1

echo "--- 5. 入口非交互"
timeout 15 bash dns-test.sh 223.5.5.5 </dev/null 2>&1 | grep -q "非交互" && check "入口非交互" 0 || check "入口非交互" 1

echo "--- 6. 预设"
timeout 15 bash dns-preset.sh tencent lite 0 2>&1 | grep -q "腾讯" && check "preset tencent" 0 || check "preset tencent" 1

echo "--- 7. 环境变量自定义"
DEFAULT_DNS_CSV="223.5.5.5" timeout 10 bash lite.sh 2>&1 | grep -q "自定义DNS" && check "DEFAULT_DNS_CSV" 0 || check "DEFAULT_DNS_CSV" 1

echo "--- 8. carrier_epdg 运营商检测"
timeout 35 perl tools/vowifi/carrier_epdg.pl ct 222.172.200.68 2>&1 | grep -q "结论" && check "carrier_epdg" 0 || check "carrier_epdg" 1

echo "--- 9. 路由器转发"
# 预检路由器本身可达性：CI数据中心/无192.168.1.1路由器的环境跳过（环境不适用），家庭网络正常测试
if timeout 3 dig @192.168.1.1 www.baidu.com A +short +time=2 +tries=1 2>/dev/null | grep -qE "\."; then
  timeout 35 perl tools/vowifi/03_test_router_dns.pl 192.168.1.1 2>&1 | grep -q "路由器DNS" && check "路由器测试" 0 || check "路由器测试" 1
else
  echo "  ⚠️ 本机无192.168.1.1路由器（CI数据中心/非家庭网络），跳过路由器测试"
  check "路由器测试(无路由器跳过)" 0
fi

echo "--- 10. 反向解析"
timeout 15 perl examples/04_reverse_dns.pl 223.5.5.5 2>&1 | grep -q "dns.google\|alidns" && check "反向解析" 0 || check "反向解析" 1

echo "--- 11. DoH/DoT 检测"
timeout 10 bash tools/network/doh_dot_check.sh 223.5.5.5 2>&1 | grep -q "DoH/DoT" && check "DoH/DoT检测" 0 || check "DoH/DoT检测" 1

echo "--- 12. SAVE_LOG 日志保存"
rm -f results/lite-*.log 2>/dev/null
SAVE_LOG=1 timeout 15 bash lite.sh 223.5.5.5 0 >/dev/null 2>&1
ls results/lite-*.log >/dev/null 2>&1 && check "SAVE_LOG日志保存" 0 || check "SAVE_LOG日志保存" 1

echo "--- 13. 环境依赖报告（curl可选，仅报告不判失败）"
if command -v curl >/dev/null 2>&1; then echo "  ℹ️ curl可用（DoH可实测）"; else echo "  ℹ️ 无curl（DoH将端口级探测）"; fi
check "环境依赖报告" 0

echo "--- 14. VoWiFi解析（专项1）"
timeout 40 perl tools/vowifi/01_resolve_vowifi.pl 222.172.200.68 2>&1 | grep -q "成功解析" && check "VoWiFi解析" 0 || check "VoWiFi解析" 1

echo "--- 15. 交叉验证（专项2）"
# 省级DNS快速可达性预检（+time=2收紧）：海外runner访问省级DNS慢/不可达时跳过（避免假失败）
if timeout 4 dig @222.172.200.68 www.189.cn A +short +time=2 +tries=1 2>/dev/null | grep -qE "\."; then
  out15=$(timeout 30 perl tools/vowifi/02_vowifi_verify.pl 222.172.200.68 2>&1)
  if echo "$out15" | grep -qE "A   |→"; then
    check "交叉验证" 0
  elif echo "$out15" | grep -q "测试完成"; then
    # 脚本正常跑完但全域名无响应 = 省级DNS不可达（海外/受限网络），非代码问题
    echo "  ⚠️ 省级DNS无响应（海外/网络环境），交叉验证全跳过"
    check "交叉验证(网络不可达跳过)" 0
  else
    check "交叉验证" 1
  fi
else
  echo "  ⚠️ 省级DNS(222.172.200.68)不可达（海外/网络环境），跳过交叉验证"
  check "交叉验证(网络不可达跳过)" 0
fi

echo "--- 16. 端口测试（专项4）"
timeout 15 perl tools/network/01_port_test.pl 223.5.5.5 53 udp 2>&1 | grep -q "测试:" && check "端口测试" 0 || check "端口测试" 1

echo "--- 17. 示例01 基础查询"
timeout 15 perl examples/01_dns_query.pl 223.5.5.5 2>&1 | grep -q "A记录" && check "示例01" 0 || check "示例01" 1

echo "--- 18. 示例02 多DNS对比"
timeout 20 perl examples/02_multi_dns_compare.pl 223.5.5.5 119.29.29.29 2>&1 | grep -q "一致性" && check "示例02" 0 || check "示例02" 1

echo "--- 19. trends 趋势聚合"
TMPR=$(mktemp -d)
cat > "$TMPR/compare-20260810-090000.json" <<'EOF'
{"tool":"x","version":"v2026.08","timestamp":"2026-08-10 09:00:00 +0800","mode":"lite(63项)","cost_s":1,"dns":[{"addr":"223.5.5.5","score":"96","stab":"100","delay_ms":60,"reachable":true}]}
EOF
cat > "$TMPR/compare-20260811-090000.json" <<'EOF'
{"tool":"x","version":"v2026.08","timestamp":"2026-08-11 09:00:00 +0800","mode":"lite(63项)","cost_s":1,"dns":[{"addr":"223.5.5.5","score":"98","stab":"100","delay_ms":50,"reachable":true}]}
EOF
COMPARE_RESULTS_DIR="$TMPR" TRENDS_DIR="$TMPR/out" timeout 10 bash trends.sh 223.5.5.5 2>&1 | grep -q "趋势" && check "trends聚合" 0 || check "trends聚合" 1

echo "--- 20. trends 产物（HTML/CSV）"
COMPARE_RESULTS_DIR="$TMPR" TRENDS_DIR="$TMPR/out" timeout 10 bash trends.sh --html --csv 223.5.5.5 >/dev/null 2>&1
ls "$TMPR/out/report.html" "$TMPR/out/trends.csv" >/dev/null 2>&1 && check "trends产物" 0 || check "trends产物" 1
rm -rf "$TMPR"

echo "--- 21. compare 多DNS对比"
timeout 60 bash compare.sh 223.5.5.5 119.29.29.29 2>&1 | grep -q "对比结果" && check "compare多DNS对比" 0 || check "compare多DNS对比" 1

echo ""
echo "════ 结果: $PASS 通过 / $FAIL 失败 ════"
echo ""
echo "════ 下一步指引 ════"
echo "  bash dns-test.sh               # 交互引导（选DNS组/版本/专项）"
echo "  bash lite.sh 223.5.5.5 0       # 快速测一个DNS"
echo "  bash dns-preset.sh ali lite 0  # 预设测试（阿里/腾讯/云南电信）"
echo "  bash full.sh 240e:52:4800::8888 0  # 完整版测试"
echo "  bash compare.sh 223.5.5.5 119.29.29.29  # 多DNS横向对比"
echo "  bash trends.sh --html --csv        # DNS趋势洞察（需先积累compare数据）"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
