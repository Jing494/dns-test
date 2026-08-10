#!/bin/bash
# ============================================================================
# 自动化冒烟测试：一键验证工具集核心功能
# 用法: bash smoke_test.sh    （任何一项失败 → 退出码非0，适合CI/改动后回归）
# ============================================================================
cd "$(dirname "$0")"
PASS=0; FAIL=0
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
timeout 35 perl tools/vowifi/03_test_router_dns.pl 192.168.1.1 2>&1 | grep -q "路由器DNS" && check "路由器测试" 0 || check "路由器测试" 1

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

echo ""
echo "════ 结果: $PASS 通过 / $FAIL 失败 ════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
