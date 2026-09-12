#!/bin/bash
# ============================================================================
# 纯 bash 轻量断言单测：CLI 契约 + 前几轮修复的行为级回归（离线优先）
#
# 为什么要这个文件：v2026.08.30 修了一批 CLI 缺陷（release.sh 参数校验、
# dns-test.sh 选项透传、dns-preset 优先级、SAVE_LOG 统一），但当时没有加任何
# 行为级断言 —— 改动只靠人工验证，回退或再改都无人拦。本文件把这些契约固化。
#
# 覆盖：
#   A. bash 入口 CLI 契约：--help/--version 退出码 0、未知选项退出码 1
#   B. perl 脚本 CLI 契约：同上（tools/ + examples/）
#   C. 行为级回归：
#      - release.sh：--help 不产出垃圾包；非法版本/参数过多 退出码 1
#      - dns-preset.sh：显式预设组必须胜过 PRESET_DNS_CSV（mock dig，离线）
#      - SAVE_LOG：compare/trends/doctor/verify/lite 均落盘；trends --json 跳过
#      - dns-test.sh：--strict 不再被当 DNS 地址
# 用法: bash tests/09_cli_contract.sh   （退出码 0=全过 1=有失败）
# ============================================================================
cd "$(dirname "$0")/.." || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
notok(){ FAIL=$((FAIL+1)); echo "  ❌ $1"; }

TMP=${TMPDIR:-/tmp}/t09-cli
rm -rf "$TMP"; mkdir -p "$TMP"

# ---------- A. bash 入口 CLI 契约 ----------
echo "═══ A. bash 入口：--help / --version / 未知选项 ═══"
# 注：dns-test.sh 不在此列 —— 它的契约是"选项原样透传给专项脚本、由子脚本校验"，
#     非交互模式下未知选项被忽略并继续（见 C4 单独断言），不返回 1。
for S in compare.sh dns-preset.sh doctor.sh full.sh install.sh lite.sh release.sh trends.sh verify.sh; do
  timeout 20 bash "$S" --help >/dev/null 2>&1
  [ $? -eq 0 ] && ok "$S --help rc=0" || notok "$S --help 非 0"
  timeout 20 bash "$S" --version >/dev/null 2>&1
  [ $? -eq 0 ] && ok "$S --version rc=0" || notok "$S --version 非 0"
  out=$(timeout 20 bash "$S" --zzz-bogus 2>&1); rc=$?
  [ "$rc" -eq 1 ] && ok "$S 未知选项 rc=1" || notok "$S 未知选项 rc=$rc"
  echo "$out" | grep -q "非法DNS地址" && notok "$S 把未知选项误报成非法DNS地址" \
    || ok "$S 未知选项未误报为非法地址"
done

# ---------- B. perl 脚本 CLI 契约 ----------
echo "═══ B. perl 脚本：--help / 未知选项 ═══"
for P in examples/01_dns_query.pl examples/02_multi_dns_compare.pl \
         examples/03_dns64_check.pl examples/04_reverse_dns.pl \
         tools/vowifi/01_resolve_vowifi.pl tools/vowifi/02_vowifi_verify.pl \
         tools/vowifi/03_test_router_dns.pl tools/vowifi/carrier_epdg.pl \
         tools/network/01_port_test.pl; do
  timeout 20 perl "$P" --help >/dev/null 2>&1
  [ $? -eq 0 ] && ok "$(basename "$P") --help rc=0" || notok "$(basename "$P") --help 非 0"
  out=$(timeout 20 perl "$P" --zzz 2>&1); rc=$?
  [ "$rc" -eq 1 ] && ok "$(basename "$P") 未知选项 rc=1" || notok "$(basename "$P") 未知选项 rc=$rc"
  echo "$out" | grep -q "未知选项" && ok "$(basename "$P") 明确报未知选项" \
    || notok "$(basename "$P") 未明确报未知选项"
done
# --help 出现在中间位置也要生效（examples 历史实现只看 $ARGV[0]）
timeout 20 perl examples/01_dns_query.pl 8.8.8.8 --help 2>&1 | grep -q "用法:" \
  && ok "examples 中间位置 --help 生效" || notok "examples 中间位置 --help 未生效"
# 03 的 '--' 是语义分隔符，不能被当成选项拒绝
out=$(timeout 20 perl tools/vowifi/03_test_router_dns.pl 192.0.2.1 -- 223.5.5.5 2>&1)
echo "$out" | grep -q "未知选项" && notok "03 把 '--' 误判为未知选项" \
  || ok "03 保留 '--' 分隔符语义"

# ---------- C1. release.sh ----------
echo "═══ C1. release.sh 参数校验 ═══"
rm -f dns-test-*.tar.gz
timeout 20 bash release.sh --help >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "release.sh --help rc=0" || notok "release.sh --help rc=$rc"
ls dns-test-*.tar.gz >/dev/null 2>&1 && notok "release.sh --help 产出了垃圾包" \
  || ok "release.sh --help 未产出任何包"
out=$(timeout 20 bash release.sh 8.8.8 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "release.sh 非法版本 rc=1" || notok "release.sh 非法版本 rc=$rc"
echo "$out" | grep -q "非法版本号" && ok "release.sh 非法版本给出明确提示" || notok "release.sh 非法版本提示缺失"
timeout 20 bash release.sh v1.18 extra >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "release.sh 参数过多 rc=1" || notok "release.sh 参数过多 rc=$rc"
timeout 20 bash release.sh --version >/dev/null 2>&1 && ok "release.sh --version rc=0" || notok "release.sh --version 非 0"
ls dns-test-*.tar.gz >/dev/null 2>&1 && notok "release.sh 校验失败仍产出包" || ok "release.sh 校验失败未产出包"

# ---------- C2. dns-preset.sh 优先级（mock dig，离线且快速） ----------
echo "═══ C2. dns-preset.sh：命令行参数 > 环境变量 ═══"
MOCK="$TMP/mock"; mkdir -p "$MOCK"
printf '#!/bin/sh\nexit 1\n' > "$MOCK/dig"; chmod +x "$MOCK/dig"   # 一切地址都"不可达"，保证离线且快
out=$(PATH="$MOCK:$PATH" PRESET_DNS_CSV="192.0.2.1" timeout 60 bash dns-preset.sh ali lite 0 2>&1)
echo "$out" | grep -q "阿里云公共DNS" && ok "显式预设组 ali 胜过 PRESET_DNS_CSV" \
  || notok "PRESET_DNS_CSV 仍压过命令行参数"
echo "$out" | grep -q "自定义（1个）" && notok "环境变量越权生效" || ok "环境变量未越权"
out=$(PATH="$MOCK:$PATH" PRESET_DNS_CSV="192.0.2.1" timeout 60 bash dns-preset.sh 2>&1)
echo "$out" | grep -q "自定义（1个）" && ok "无位置参数时环境变量正常生效" \
  || notok "未给位置参数时环境变量未生效"

# ---------- C3. SAVE_LOG 覆盖 ----------
echo "═══ C3. SAVE_LOG 覆盖全部入口 ═══"
rm -f results/compare-*.log results/trends-*.log results/doctor-*.log results/verify-*.log results/lite-*.log
for S in compare trends doctor verify; do
  SAVE_LOG=1 timeout 60 bash "$S.sh" --help >/dev/null 2>&1
  sleep 0.3   # tee 子进程异步落盘
  ls results/$S-*.log >/dev/null 2>&1 && ok "SAVE_LOG 覆盖 $S.sh" || notok "SAVE_LOG 未覆盖 $S.sh"
done
# lite/full 的 --help/--version 在 source core.sh 之前就早退，故用真实运行触发落盘
# （192.0.2.1 是 TEST-NET 保留地址，预检必然快速跳过，不依赖外网）
SAVE_LOG=1 timeout 60 bash lite.sh 192.0.2.1 0 >/dev/null 2>&1; sleep 0.3
ls results/lite-*.log >/dev/null 2>&1 && ok "SAVE_LOG 覆盖 lite.sh" || notok "SAVE_LOG 未覆盖 lite.sh"
# trends --json 必须跳过（stdout 是机器可读契约，被 tee 合并 stderr 会破坏它）
rm -f results/trends-*.log
SAVE_LOG=1 timeout 60 bash trends.sh --json >/dev/null 2>&1; sleep 0.3
ls results/trends-*.log >/dev/null 2>&1 && notok "trends --json 不应落盘却落盘" || ok "trends --json 正确跳过落盘"
# 清理本测试产生的日志（绝不动用户 results/ 下的 compare-*.json 历史数据）
rm -f results/compare-*.log results/trends-*.log results/doctor-*.log results/verify-*.log results/lite-*.log

# ---------- C4. dns-test.sh 未知 flag 不被当 DNS 地址 ----------
echo "═══ C4. dns-test.sh：选项不再被当 DNS 地址 ═══"
out=$(timeout 60 bash dns-test.sh --strict 2>&1)
echo "$out" | grep -q "非法DNS地址" && notok "dns-test.sh 仍把 --strict 当 DNS 地址" \
  || ok "dns-test.sh 未把 --strict 当 DNS 地址"
echo "$out" | grep -q "不适用" && ok "dns-test.sh 明确提示选项不适用" || notok "dns-test.sh 缺少选项忽略提示"

rm -rf "$TMP"
echo ""
echo "════════ tests/09 结果: ✅$PASS 通过  ❌$FAIL 失败 ════════"
[ "$FAIL" = "0" ]
