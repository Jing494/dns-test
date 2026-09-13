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
#      - trends.sh：损坏 JSON 不得静默跳过（须告警 + 给 doctor --fix 指引，且不污染 --json stdout）
#   F. 入口交互契约（pty 驱动，需 python3）：带命令行 DNS 时主菜单仍提供 3. DNS 管理、
#      输入 3 能进子菜单（不再静默重绘）、提示范围与实际可选项一致、compare 继承已传 DNS
# 用法: bash tests/09_cli_contract.sh   （退出码 0=全过 1=有失败）
# 注意: 本文件刻意不使用 timeout —— macOS 无该命令，走 lib/compat.sh 的兼容函数时，
#       其后台 watcher 会继承 $(...) 的 stdout 管道，使每次 out=$(timeout N cmd) 都被
#       拖满 N 秒（CI 实测把 macos-latest 从 46s 拖到 >596s 并顶爆 10 分钟 job 上限）。
#       故全部断言只用快速/离线路径（需要地址的场景注入 mock dig）。
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
  bash "$S" --help >/dev/null 2>&1
  [ $? -eq 0 ] && ok "$S --help rc=0" || notok "$S --help 非 0"
  bash "$S" --version >/dev/null 2>&1
  [ $? -eq 0 ] && ok "$S --version rc=0" || notok "$S --version 非 0"
  out=$(bash "$S" --zzz-bogus 2>&1); rc=$?
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
  perl "$P" --help >/dev/null 2>&1
  [ $? -eq 0 ] && ok "$(basename "$P") --help rc=0" || notok "$(basename "$P") --help 非 0"
  out=$(perl "$P" --zzz 2>&1); rc=$?
  [ "$rc" -eq 1 ] && ok "$(basename "$P") 未知选项 rc=1" || notok "$(basename "$P") 未知选项 rc=$rc"
  echo "$out" | grep -q "未知选项" && ok "$(basename "$P") 明确报未知选项" \
    || notok "$(basename "$P") 未明确报未知选项"
done
# --help 出现在中间位置也要生效（examples 历史实现只看 $ARGV[0]）
perl examples/01_dns_query.pl 8.8.8.8 --help 2>&1 | grep -q "用法:" \
  && ok "examples 中间位置 --help 生效" || notok "examples 中间位置 --help 未生效"
# 03 的 '--' 是语义分隔符，不能被当成选项拒绝
out=$(perl tools/vowifi/03_test_router_dns.pl 192.0.2.1 -- 223.5.5.5 2>&1)
echo "$out" | grep -q "未知选项" && notok "03 把 '--' 误判为未知选项" \
  || ok "03 保留 '--' 分隔符语义"

# ---------- C1. release.sh ----------
echo "═══ C1. release.sh 参数校验 ═══"
rm -f dns-test-*.tar.gz
bash release.sh --help >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "release.sh --help rc=0" || notok "release.sh --help rc=$rc"
ls dns-test-*.tar.gz >/dev/null 2>&1 && notok "release.sh --help 产出了垃圾包" \
  || ok "release.sh --help 未产出任何包"
out=$(bash release.sh 8.8.8 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "release.sh 非法版本 rc=1" || notok "release.sh 非法版本 rc=$rc"
echo "$out" | grep -q "非法版本号" && ok "release.sh 非法版本给出明确提示" || notok "release.sh 非法版本提示缺失"
bash release.sh v1.18 extra >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "release.sh 参数过多 rc=1" || notok "release.sh 参数过多 rc=$rc"
bash release.sh --version >/dev/null 2>&1 && ok "release.sh --version rc=0" || notok "release.sh --version 非 0"
ls dns-test-*.tar.gz >/dev/null 2>&1 && notok "release.sh 校验失败仍产出包" || ok "release.sh 校验失败未产出包"

# ---------- C2. dns-preset.sh 优先级（mock dig，离线且快速） ----------
echo "═══ C2. dns-preset.sh：命令行参数 > 环境变量 ═══"
MOCK="$TMP/mock"; mkdir -p "$MOCK"
printf '#!/bin/sh\nexit 1\n' > "$MOCK/dig"; chmod +x "$MOCK/dig"   # 一切地址都"不可达"，保证离线且快
out=$(PATH="$MOCK:$PATH" PRESET_DNS_CSV="192.0.2.1" bash dns-preset.sh ali lite 0 2>&1)
echo "$out" | grep -q "阿里云公共DNS" && ok "显式预设组 ali 胜过 PRESET_DNS_CSV" \
  || notok "PRESET_DNS_CSV 仍压过命令行参数"
echo "$out" | grep -q "自定义（1个）" && notok "环境变量越权生效" || ok "环境变量未越权"
out=$(PATH="$MOCK:$PATH" PRESET_DNS_CSV="192.0.2.1" bash dns-preset.sh 2>&1)
echo "$out" | grep -q "自定义（1个）" && ok "无位置参数时环境变量正常生效" \
  || notok "未给位置参数时环境变量未生效"

# ---------- C3. SAVE_LOG 覆盖 ----------
echo "═══ C3. SAVE_LOG 覆盖全部入口 ═══"
rm -f results/compare-*.log results/trends-*.log results/doctor-*.log results/verify-*.log results/lite-*.log
for S in compare trends doctor verify; do
  SAVE_LOG=1 bash "$S.sh" --help >/dev/null 2>&1
  sleep 0.3   # tee 子进程异步落盘
  ls results/$S-*.log >/dev/null 2>&1 && ok "SAVE_LOG 覆盖 $S.sh" || notok "SAVE_LOG 未覆盖 $S.sh"
done
# lite/full 的 --help/--version 在 source core.sh 之前就早退，故用真实运行触发落盘
# （192.0.2.1 是 TEST-NET 保留地址，预检必然快速跳过，不依赖外网）
SAVE_LOG=1 bash lite.sh 192.0.2.1 0 >/dev/null 2>&1; sleep 0.3
ls results/lite-*.log >/dev/null 2>&1 && ok "SAVE_LOG 覆盖 lite.sh" || notok "SAVE_LOG 未覆盖 lite.sh"
# trends --json 必须跳过（stdout 是机器可读契约，被 tee 合并 stderr 会破坏它）
rm -f results/trends-*.log
SAVE_LOG=1 bash trends.sh --json >/dev/null 2>&1; sleep 0.3
ls results/trends-*.log >/dev/null 2>&1 && notok "trends --json 不应落盘却落盘" || ok "trends --json 正确跳过落盘"
# 清理本测试产生的日志（绝不动用户 results/ 下的 compare-*.json 历史数据）
rm -f results/compare-*.log results/trends-*.log results/doctor-*.log results/verify-*.log results/lite-*.log

# ---------- C4. dns-test.sh 未知 flag 不被当 DNS 地址 ----------
echo "═══ C4. dns-test.sh：选项不再被当 DNS 地址 ═══"
# 注入 mock dig 保持离线：dns-test.sh 非交互模式会落到 lite.sh（默认 DNS 会真实查询）
out=$(PATH="$MOCK:$PATH" bash dns-test.sh --strict 2>&1)
echo "$out" | grep -q "非法DNS地址" && notok "dns-test.sh 仍把 --strict 当 DNS 地址" \
  || ok "dns-test.sh 未把 --strict 当 DNS 地址"
echo "$out" | grep -q "不适用" && ok "dns-test.sh 明确提示选项不适用" || notok "dns-test.sh 缺少选项忽略提示"

# ---------- C5. trends.sh 损坏 JSON 不得静默 ----------
echo "═══ C5. trends.sh：损坏数据文件必须被告警 ═══"
TD="$TMP/trd"; mkdir -p "$TD"
printf 'BROKEN{{{' > "$TD/compare-20260810-090000.json"
out=$(COMPARE_RESULTS_DIR="$TD" TRENDS_DIR="$TD/out" bash trends.sh 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "全损坏时 exit 2" || notok "全损坏时 rc=$rc"
echo "$out" | grep -q "无法解析" && ok "损坏文件被明确指出" || notok "损坏文件未被告警"
echo "$out" | grep -q "doctor.sh --fix" && ok "给出修复指引" || notok "缺少修复指引"
# 归因不得停留在"不可达/被过滤"（那是把排障引向错误方向）
echo "$out" | grep -qE "无可用数据（所有记录均为不可达" && notok "仍按不可达/过滤归因" || ok "归因不再误导"
# 一好一坏：应继续出报告，且 --json 的 stdout 仍是纯 JSON（告警走 stderr）
printf '{"tool":"x","timestamp":"2026-08-11 09:00:00 +0800","mode":"lite","dns":[{"addr":"223.5.5.5","score":"90","stab":"100","delay_ms":20,"reachable":true}]}' > "$TD/compare-20260811-090000.json"
outj=$(COMPARE_RESULTS_DIR="$TD" TRENDS_DIR="$TD/out" bash trends.sh --json 2>/dev/null)
if printf '%s' "$outj" | grep -q "无法解析"; then
  notok "损坏告警污染了 --json 的 stdout"
else
  printf '%s' "$outj" | head -c 1 | grep -q "{" && ok "损坏文件下 --json stdout 仍为纯 JSON" \
    || notok "损坏文件下 --json stdout 异常"
fi
rm -rf "$TD"

# ---------- C6. compat 的 timeout 兼容函数不得阻塞命令替换 ----------
echo "═══ C6. lib/compat.sh 的 timeout 兼容函数 ═══"
# 用 command() 覆盖骗过 command -v timeout，强制 compat 定义它（本地有真 timeout 也照样走该分支）
res=$(bash -c '
command() { if [ "$1" = "-v" ] && [ "$2" = "timeout" ]; then return 1; fi; builtin command "$@"; }
source lib/compat.sh
[ "$(type -t timeout)" = "function" ] || { echo NOFUNC; exit 0; }
s=$(date +%s)
out=$(timeout 20 bash -c "echo hi")
e=$(date +%s)
echo "$((e-s))s:$out"
' 2>/dev/null)
case "$res" in
  *":hi") secs=${res%%:*}; secs=${secs%s}   # 去掉输出里的 "s" 单位
          [ "$secs" -le 3 ] && ok "compat timeout 在 \$(...) 中即时返回（${secs}s）" \
            || notok "compat timeout 拖满超时（${secs}s：后台 watcher 仍持有 stdout 管道）" ;;
  NOFUNC) notok "compat timeout 未被定义（覆盖 command 失效）" ;;
  *)      notok "compat timeout 用例异常: [$res]" ;;
esac

echo "═══ F. 入口交互契约（pty 驱动：菜单可选=提示范围、已传 DNS 被继承、3 号不再静默） ═══"
# 为什么放这里：这些行为只有真终端才走得通（无 TTY 时入口自动降级为"非交互 lite"）。
# 用 python3 的 pty 驱动，并配一个"必失败"的 dig 桩，避免真的发网络请求（strict 层要求无网络）。
# 注意: 不用 shell 的 timeout 命令（macOS 无它，走 compat 兼容函数会拖满超时，见文件头说明），
#       超时由 python 侧控制。
if command -v python3 >/dev/null 2>&1 && python3 -c 'import pty' 2>/dev/null; then
  STUBD="$TMP/pty-stub"; mkdir -p "$STUBD"
  printf '#!/bin/bash\nexit 1\n' > "$STUBD/dig"; chmod +x "$STUBD/dig"
  # 副作用隔离：入口里跑 compare 会往 results/ 写 JSON。测试不该在用户目录留痕，
  # 也不该给后续测试（tests/06 的"环比上次"）留下环境状态 —— 先快照、跑完原样恢复。
  RSNAP="$TMP/results-snap"; SNAP_OK=0
  [ -d results ] && { cp -a results "$RSNAP" && SNAP_OK=1; }
  TTY_OUT=$(PATH="$STUBD:$PATH" python3 - <<'PYEOF'
import os, pty, select, subprocess, sys, time
m, s = pty.openpty()
p = subprocess.Popen(['bash', 'dns-test.sh', '8.8.8.8'], stdin=s, stdout=s, stderr=s, close_fds=True)
os.close(s)
out = b''
# 3=进 DNS 管理 → 0=返回 → 2=专项 → 11=compare → 空行(回车取继承的默认值) → 0=退出
inputs = ['3', '0', '2', '11', '', '0']
i = 0
t0 = time.time(); nxt = t0 + 2.0
while time.time() - t0 < 60:
    r, _, _ = select.select([m], [], [], 0.2)
    if r:
        try:
            d = os.read(m, 65536)
        except OSError:
            break
        if not d:
            break
        out += d
    if i < len(inputs) and time.time() >= nxt:
        os.write(m, (inputs[i] + '\n').encode()); i += 1; nxt = time.time() + 1.5
    if p.poll() is not None:
        break
if p.poll() is None:
    p.kill()
try:
    os.close(m)
except OSError:
    pass
sys.stdout.write(out.decode('utf-8', 'replace'))
PYEOF
)
  # 恢复入口测试造成的 results/ 副作用（原先没有该目录时直接删掉，不留痕）
  rm -rf results
  [ "$SNAP_OK" = "1" ] && cp -a "$RSNAP" results
  echo "$TTY_OUT" | grep -q "3. DNS 管理（追加/替换/删除/清空；当前 1 个" && ok "带命令行 DNS 时主菜单仍提供 3. DNS 管理" || notok "带命令行 DNS 时第 3 项缺失"
  echo "$TTY_OUT" | grep -q "DNS 管理 ────" && ok "输入 3 进入 DNS 管理子菜单（不再静默重绘）" || notok "输入 3 无任何反应"
  echo "$TTY_OUT" | grep -q "请选择(0-3)" && ok "主菜单提示范围与实际可选项一致(0-3)" || notok "主菜单提示范围与实际可选项不符"
  echo "$TTY_OUT" | grep -q "未输入，默认对比 8.8.8.8 与" && ok "compare 分支继承已传 DNS（默认值含它）" || notok "compare 分支丢掉了已传 DNS"
else
  echo "  ⏭️  跳过（无 python3 或 pty 不可用）"
fi

rm -rf "$TMP"
echo ""
echo "════════ tests/09 结果: ✅$PASS 通过  ❌$FAIL 失败 ════════"
[ "$FAIL" = "0" ]
