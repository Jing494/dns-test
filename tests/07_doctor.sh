#!/bin/bash
# ============================================================================
# 纯 bash 轻量断言单测：doctor.sh 自检 + shell 补全 + install 补全安装 + trends 新参数错误路径（离线）
# 覆盖: doctor 正常路径(exit 0/段落/汇总)、--help/坏参数、--cron 值守模板、缺 dig 时的 FAIL 路径(exit 1)、
#       补全 bash 语法+注册+模拟调用、zsh 文件内容、install --completions 幂等安装（假HOME）、
#       trends --json/--week/--webhook/--archive/--export 参数校验
# 用法: bash tests/07_doctor.sh   （退出码 0=全过 1=有失败）
# ============================================================================
cd "$(dirname "$0")/.." || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
notok(){ FAIL=$((FAIL+1)); echo "  ❌ $1"; }

echo "═══ doctor.sh: 正常自检 ═══"
DOC=$(bash doctor.sh 2>&1); DOC_RC=$?
[ "$DOC_RC" = "0" ] && ok "默认自检 exit 0" || notok "默认自检 exit=$DOC_RC"
echo "$DOC" | grep -q "平台与 shell" && ok "平台段落输出" || notok "缺平台段落"
echo "$DOC" | grep -q "必需: dig" && ok "依赖段落输出(dig)" || notok "缺依赖段落"
echo "$DOC" | grep -q "date_days_ago 正常" && ok "兼容层段落输出" || notok "缺兼容层段落"
echo "$DOC" | grep -q "工作目录可写" && ok "目录段落输出" || notok "缺目录段落"
echo "$DOC" | grep -qE "自检结果: ✅[0-9]+ 通过" && ok "汇总行输出" || notok "缺汇总行"

echo "═══ doctor.sh: 参数路径 ═══"
bash doctor.sh --help >/dev/null 2>&1 && ok "--help exit 0" || notok "--help 非0"
bash doctor.sh --bad 2>&1 | grep -q "未知参数" && ok "坏参数报错" || notok "坏参数未报错"
bash doctor.sh --bad >/dev/null 2>&1; [ $? = "1" ] && ok "坏参数 exit 1" || notok "坏参数 exit 非1"

echo "═══ doctor.sh: --cron 值守模板 ═══"
CR=$(bash doctor.sh --cron 2>&1); CR_RC=$?
[ "$CR_RC" = "0" ] && ok "--cron exit 0" || notok "--cron exit=$CR_RC"
echo "$CR" | grep -q '^\*/30 \* \* \* \*' && ok "含采集定时行" || notok "缺采集定时行"
echo "$CR" | grep -q -- "--prune 200 --archive" && ok "采集行带 prune+archive" || notok "采集行缺 archive"
echo "$CR" | grep -q -- "--alert 70 --webhook" && ok "含告警推送行" || notok "缺告警推送行"
echo "$CR" | grep -q '^PATH=' && ok "含 PATH 避坑行" || notok "缺 PATH 行"
echo "$CR" | grep -q "$(pwd)" && ok "模板带本仓库绝对路径" || notok "模板路径异常"
bash doctor.sh --cron 2>/dev/null | grep -q "自检" && notok "--cron 不应跑体检" || ok "--cron 不跑体检(纯模板)"

echo "═══ doctor.sh: 缺 dig/ping 的 FAIL 路径（PATH 剥离，必需项缺失应 exit 1） ═══"
NOPATH=$(mktemp -d)
for c in uname date mkdir touch rm ls grep wc sort basename head tail awk sed cut tr bash sh; do
  p=$(command -v "$c" 2>/dev/null) && ln -s "$p" "$NOPATH/$c"
done
DOC2=$(PATH="$NOPATH" bash doctor.sh 2>&1); DOC2_RC=$?
[ "$DOC2_RC" = "1" ] && ok "缺dig/ping时 exit 1" || notok "缺dig/ping时 exit=$DOC2_RC"
echo "$DOC2" | grep -q "必需: dig 未找到" && ok "缺 dig 被点名" || notok "缺 dig 未点名"
echo "$DOC2" | grep -q "必需: ping 未找到" && ok "缺 ping 被点名" || notok "缺 ping 未点名"
rm -rf "$NOPATH"

echo "═══ completions: bash 补全 ═══"
bash -n completions/dns-test.bash && ok "bash 补全语法 OK" || notok "bash 补全语法错误"
bash -c 'source completions/dns-test.bash && complete -p compare.sh trends.sh doctor.sh >/dev/null 2>&1' \
  && ok "补全已注册(6脚本)" || notok "补全未注册"
# 模拟 <TAB>：./trends.sh --we<TAB> 应补出 --webhook/--week
SIM=$(bash -c 'source completions/dns-test.bash
COMP_WORDS=(trends.sh --we); COMP_CWORD=1
_dns_test_complete; echo "${COMPREPLY[@]}"')
echo "$SIM" | grep -q -- "--webhook" && echo "$SIM" | grep -q -- "--week" \
  && ok "trends.sh --we<TAB> 补出 --webhook/--week" || notok "trends 前缀补全异常: [$SIM]"
SIM2=$(bash -c 'source completions/dns-test.bash
COMP_WORDS=(compare.sh al); COMP_CWORD=1
_dns_test_complete; echo "${COMPREPLY[@]}"')
echo "$SIM2" | grep -q "ali" && ok "compare.sh al<TAB> 补出预设 ali" || notok "compare 预设补全异常: [$SIM2]"
# 值位不补 flag
SIM3=$(bash -c 'source completions/dns-test.bash
COMP_WORDS=(trends.sh --week); COMP_CWORD=2
_dns_test_complete; echo "n=${#COMPREPLY[@]}"')
[ "$SIM3" = "n=0" ] && ok "--week 值位不补 flag" || notok "值位误补: [$SIM3]"
SIM4=$(bash -c 'source completions/dns-test.bash
COMP_WORDS=(trends.sh --arc); COMP_CWORD=1
_dns_test_complete; echo "${COMPREPLY[@]}"')
echo "$SIM4" | grep -q -- "--archive" && ok "trends.sh --arc<TAB> 补出 --archive" || notok "--archive 补全缺失: [$SIM4]"
SIM5=$(bash -c 'source completions/dns-test.bash
COMP_WORDS=(doctor.sh --c); COMP_CWORD=1
_dns_test_complete; echo "${COMPREPLY[@]}"')
echo "$SIM5" | grep -q -- "--cron" && ok "doctor.sh --c<TAB> 补出 --cron" || notok "--cron 补全缺失: [$SIM5]"
SIM6=$(bash -c 'source completions/dns-test.bash
COMP_WORDS=(trends.sh --ex); COMP_CWORD=1
_dns_test_complete; echo "${COMPREPLY[@]}"')
echo "$SIM6" | grep -q -- "--export" && ok "trends.sh --ex<TAB> 补出 --export" || notok "--export 补全缺失: [$SIM6]"
SIM7=$(bash -c 'source completions/dns-test.bash
COMP_WORDS=(doctor.sh --f); COMP_CWORD=1
_dns_test_complete; echo "${COMPREPLY[@]}"')
echo "$SIM7" | grep -q -- "--fix" && ok "doctor.sh --f<TAB> 补出 --fix" || notok "--fix 补全缺失: [$SIM7]"
SIM8=$(bash -c 'source completions/dns-test.bash
COMP_WORDS=(trends.sh --archive-k); COMP_CWORD=1
_dns_test_complete; echo "${COMPREPLY[@]}"')
echo "$SIM8" | grep -q -- "--archive-keep" && ok "trends.sh --archive-k<TAB> 补出 --archive-keep" || notok "--archive-keep 补全缺失: [$SIM8]"
# --archive-keep 值位不补 flag
SIM9=$(bash -c 'source completions/dns-test.bash
COMP_WORDS=(trends.sh --archive-keep); COMP_CWORD=2
_dns_test_complete; echo "n=${#COMPREPLY[@]}"')
[ "$SIM9" = "n=0" ] && ok "--archive-keep 值位不补 flag" || notok "--archive-keep 值位误补: [$SIM9]"

echo "═══ completions: zsh 补全 ═══"
grep -q "#compdef compare.sh trends.sh doctor.sh" completions/dns-test.zsh \
  && ok "zsh compdef 头正确" || notok "zsh 缺 compdef 头"
grep -q -- "--webhook" completions/dns-test.zsh && ok "zsh 含新 flag --webhook" || notok "zsh 缺 --webhook"
grep -q -- "--archive" completions/dns-test.zsh && ok "zsh 含 --archive" || notok "zsh 缺 --archive"
grep -q -- "--export" completions/dns-test.zsh && ok "zsh 含 --export" || notok "zsh 缺 --export"
grep -q -- "--net --cron --fix --help" completions/dns-test.zsh && ok "zsh doctor 含 --cron/--fix" || notok "zsh doctor 缺 --cron/--fix"
grep -q -- "--archive-keep" completions/dns-test.zsh && ok "zsh 含 --archive-keep" || notok "zsh 缺 --archive-keep"

echo "═══ install.sh: --completions 幂等安装（假 HOME，不动真实 rc） ═══"
bash -n install.sh && ok "install.sh 语法 OK" || notok "install.sh 语法错误"
FAKEHOME=$(mktemp -d)
: > "$FAKEHOME/.bashrc"; : > "$FAKEHOME/.zshrc"
IC=$(HOME="$FAKEHOME" bash install.sh --completions 2>&1)
echo "$IC" | grep -q "bash 补全已写入" && ok "写入 .bashrc 提示" || notok "未写 .bashrc"
grep -q "dns-test completions (added by install.sh)" "$FAKEHOME/.bashrc" && ok ".bashrc 含标记段" || notok ".bashrc 缺标记"
grep -q "completions/dns-test.bash" "$FAKEHOME/.bashrc" && ok ".bashrc 含 source 行" || notok ".bashrc 缺 source 行"
[ -f "$FAKEHOME/.zfunc/_dns-test" ] && ok "zsh 补全装到 .zfunc" || notok "zsh 补全未安装"
grep -q "compinit" "$FAKEHOME/.zshrc" && ok ".zshrc 启用 compinit" || notok ".zshrc 缺 compinit"
HOME="$FAKEHOME" bash install.sh --completions >/dev/null 2>&1
[ "$(grep -c "dns-test completions (added by install.sh)" "$FAKEHOME/.bashrc")" = "1" ] \
  && ok "重复运行幂等(标记唯一)" || notok "重复运行重复写入"
EMPTYH=$(mktemp -d)
HOME="$EMPTYH" bash install.sh --completions 2>&1 | grep -q "未发现" \
  && ok "无rc文件提示手动启用" || notok "无rc未提示"
rm -rf "$FAKEHOME" "$EMPTYH"

echo "═══ trends.sh: 新参数错误路径（主链路在 tests/06） ═══"
TRD=${TMPDIR:-/tmp}/t07-fixture; rm -rf "$TRD"; mkdir -p "$TRD"
printf '{"tool":"x","timestamp":"2026-08-14 08:00:00 +0800","mode":"lite","dns":[{"addr":"223.5.5.5","score":"90","stab":"100","delay_ms":20,"reachable":true}]}' > "$TRD/compare-20260814-080000.json"
tr7() { COMPARE_RESULTS_DIR="$TRD" TRENDS_DIR=${TMPDIR:-/tmp}/t07-out bash trends.sh "$@"; }
tr7 --week 2>&1 | grep -q "缺少天数" && ok "--week 缺值报错" || notok "--week 缺值未报错"
tr7 --week 0 2>&1 | grep -q "2-365" && ok "--week 越界报错" || notok "--week 越界未报错"
tr7 --webhook 2>&1 | grep -q "缺少 URL" && ok "--webhook 缺值报错" || notok "--webhook 缺值未报错"
tr7 --webhook ftp://x.com 2>&1 | grep -q "http/https" && ok "--webhook 非http报错" || notok "--webhook 非http未报错"
tr7 --webhook https://x.com/h 2>&1 | grep -q "需配合 --alert" && ok "--webhook 无--alert报错" || notok "--webhook 无--alert未报错"
rm -rf "$TRD" ${TMPDIR:-/tmp}/t07-out

echo ""
echo "════════ tests/07 结果: ✅$PASS 通过  ❌$FAIL 失败 ════════"
[ "$FAIL" = "0" ]
