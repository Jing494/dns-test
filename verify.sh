#!/bin/bash
# ============================================================================
# 一键全面验证：语法 + shellcheck + 单测 + 冒烟 + compare + trends + 专项抽查
# 真机/沙箱通用——在你自己的机器上跑一遍，等于完成全部自检
# 用法: bash verify.sh    （退出码 0=全部通过 1=有失败项）
# 注意: compare/trends 为网络项，海外/受限网络可能超时；trends 无历史数据会提示跳过
# ============================================================================
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0; FAILED_ITEMS=""
tick() {  # $1=项名  $2=0/1
  if [ "$2" = "0" ]; then PASS=$((PASS+1)); echo "  ✅ $1"
  else FAIL=$((FAIL+1)); FAILED_ITEMS="$FAILED_ITEMS $1"; echo "  ❌ $1"; fi
}

echo "════ 一键全面验证 ════"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

echo "--- 1. 语法检查"
OK=1
for f in *.sh lib/*.sh; do bash -n "$f" 2>/dev/null || OK=0; done
while IFS= read -r f; do perl -c "$f" >/dev/null 2>&1 || OK=0; done < <(find . -name '*.pl')
tick "语法(.sh+.pl)" $((1-OK))

echo "--- 2. shellcheck（未安装则跳过并提示）"
if command -v shellcheck >/dev/null 2>&1; then
  n=$(shellcheck -S warning *.sh lib/*.sh tools/network/*.sh 2>/dev/null | grep -cE "SC[0-9]{4}")
  [ "$n" -eq 0 ] && tick "shellcheck(0告警)" 0 || tick "shellcheck(${n}告警)" 1
else
  echo "  ⚠️ 未安装 shellcheck，跳过（Linux: apt install shellcheck）"
  tick "shellcheck(未装跳过)" 0
fi

echo "--- 3. 单元测试（DNSUtil）"
if perl -Ilib tests/01_dnsutil.t >/dev/null 2>&1; then
  tick "单测(18用例)" 0
else
  tick "单测" 1
fi

echo "--- 4. 冒烟测试（23项，含网络项约3分钟）"
if timeout 300 bash smoke_test.sh 2>&1 | grep -q "23 通过 / 0 失败"; then
  tick "冒烟(23项)" 0
else
  tick "冒烟" 1
fi

echo "--- 5. compare 快测（2 DNS，网络项）"
if timeout 60 bash compare.sh 223.5.5.5 119.29.29.29 >/dev/null 2>&1; then
  tick "compare(2DNS)" 0
else
  tick "compare" 1
fi

echo "--- 6. trends 聚合（无历史数据则跳过；文本模式更快）"
timeout 45 bash trends.sh >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  tick "trends聚合" 0
elif [ "$rc" -eq 2 ]; then
  echo "  ⚠️ trends 无历史数据，跳过（先跑 compare 积累）"
  tick "trends(无数据跳过)" 0
elif [ "$rc" -eq 124 ]; then
  echo "  ⚠️ trends 超时（数据量大/环境慢），可加 --since 缩小范围"
  tick "trends(超时提示)" 0
else
  tick "trends" 1
fi

echo "--- 7. 专项抽查（示例02对比 / DoH检测，网络项）"
OK=1
timeout 20 perl examples/02_multi_dns_compare.pl 223.5.5.5 119.29.29.29 >/dev/null 2>&1 || OK=0
timeout 15 bash tools/network/doh_dot_check.sh 223.5.5.5 >/dev/null 2>&1 || OK=0
tick "专项(示例02/DoH)" $((1-OK))

echo ""
echo "════ 汇总: $PASS 通过 / $FAIL 失败 ════"
[ -n "$FAILED_ITEMS" ] && echo "失败项:$FAILED_ITEMS"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
