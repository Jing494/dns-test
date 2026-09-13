#!/bin/bash
# ============================================================================
# 纯 bash 轻量断言单测：trends.sh 数据解析健壮性 + 中断/数据安全回归（离线）
#
# 为什么需要这个文件：trends.sh 的数据入口原先是「行正则」
#   grep -oE '"addr": ?"..", ?"score": ?"..", ?"stab": ?"..", ?"delay_ms": ?[0-9]+'
# 它要求 4 个字段**紧邻、顺序固定、字段间最多一个空格**：字段换行/顺序调整/中间
# 插入新字段（jitter_ms 等）都会让整条记录被**静默丢弃**且零告警。实测这三种常见
# 变体下旧解析器解析出 0 条，却报「无可用数据（所有记录均为不可达…）」——
# 把解析失败伪装成数据结论。本文件把「任何形态的合法 JSON 都必须解析出来，
# 解析不出来必须告警」固化下来，防止回归。
#
# 覆盖：
#   A. 解析容错：字段顺序调换 / 中间插入新字段 / 字段间多空格 / 对象跨行 / 同轮多对象
#   B. 失败可见：有记录无法解析时必须告警（不得静默）；告警不污染 --json stdout
#   C. 数据安全回归：install_exit_traps 下 INT/TERM 必须**显式退出**（bash 执行完
#      trap 会继续执行后续语句，曾导致"清理完临时目录后继续跑，把中断轮写成不可达
#      并落盘污染历史"）；tests/06 必须以 cp（而非 mv）备份用户数据
# 用法: bash tests/10_trends_parse.sh   （退出码 0=全过 1=有失败）
# 说明: 全程离线；数据与产物走 COMPARE_RESULTS_DIR/TRENDS_DIR 隔离目录，
#       不读写仓库的 results/ 与 trends/。core.sh 加载做 dig/perl 前置检查，
#       与 03/04 同策略：缺失时用最小 stub 通过检查。
# ============================================================================
cd "$(dirname "$0")/.." || exit 1

STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
for c in dig perl; do
  if ! command -v "$c" >/dev/null 2>&1; then
    printf '#!/bin/bash\nexit 0\n' > "$STUB/$c"
    chmod +x "$STUB/$c"
  fi
done

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
notok(){ FAIL=$((FAIL+1)); echo "  ❌ $1"; }

IN="$STUB/in"; OUT="$STUB/out"
mkdir -p "$IN" "$OUT"
# trs：在隔离目录上跑 trends.sh（数据源与产物都不落仓库）
trs() { COMPARE_RESULTS_DIR="$IN" TRENDS_DIR="$OUT" PATH="$STUB:$PATH" bash trends.sh "$@"; }
fixture() { printf '%s' "$2" > "$IN/compare-$1.json"; }

echo "═══ A. 解析容错（字段形态变化不得丢记录） ═══"
# A1 字段顺序调换 + 中间插入新字段(loss) + 字段间多空格
fixture 20260801-080000 '{"tool":"x","timestamp":"2026-08-01 08:00:00 +0800","mode":"lite",
 "dns":[{"delay_ms": 20,  "loss":0, "stab":"100", "score":"90", "addr":"223.5.5.5", "reachable":true}]}'
# A2 对象跨行（字段换行，合法 JSON）
fixture 20260802-080000 '{"tool":"x","timestamp":"2026-08-02 08:00:00 +0800","mode":"lite",
 "dns":[
   {"addr":"223.5.5.5",
    "score":"95",
    "stab":"100",
    "delay_ms":18}
 ]}'
# A3 同轮两个对象同行 + jitter_ms 插在 stab 与 delay_ms 之间
fixture 20260803-080000 '{"tool":"x","timestamp":"2026-08-03 08:00:00 +0800","mode":"lite","dns":[{"addr":"223.5.5.5","score":"85","stab":"99","jitter_ms":3,"delay_ms":22,"reachable":true},{"addr":"119.29.29.29","score":"70","stab":"98","jitter_ms":5,"delay_ms":40,"reachable":true}]}'

O1=$(trs 2>/dev/null)
echo "$O1" | grep -q "223.5.5.5" && ok "字段顺序调换+插新字段+多空格 仍解析出记录" || notok "字段顺序/插入字段导致记录丢失"
echo "$O1" | grep -q "119.29.29.29" && ok "对象跨行/同行多对象 仍解析出全部DNS" || notok "跨行对象解析丢失"
echo "$O1" | grep -q "4条可达记录" && ok "记录计数正确(3文件共4条可达)" || notok "记录计数错误(应4条)"
echo "$O1" | grep -qE "223.5.5.5.*9[0-9]" && ok "字段乱序时取值仍正确(均值90)" || notok "字段乱序时取值错误"

echo "═══ B. 解析失败必须可见（不得静默少算） ═══"
# B1 一条 addr 为空的记录：解析不出来 → 必须告警
fixture 20260804-080000 '{"tool":"x","timestamp":"2026-08-04 08:00:00 +0800","mode":"lite","dns":[{"addr":"","score":"50","stab":"100","delay_ms":10}]}'
E1=$(trs 2>&1 >/dev/null)
echo "$E1" | grep -q "未能解析" && ok "存在无法解析的记录时给出显式告警" || notok "解析丢记录却无告警（静默少算）"
if echo "$E1" | grep -q "compare-20260804"; then
  ok "告警点名具体文件，便于定位"
else
  notok "告警未点名文件"
  # 失败时把实际告警文本与文件内容打出来，避免只能靠猜
  echo "      --- 实际 stderr ---"
  printf '%s\n' "$E1" | sed 's/^/      | /'
  echo "      --- 该文件内容 ---"
  sed 's/^/      | /' "$IN/compare-20260804-080000.json"
  echo "      --- addr 键计数 / 文件存在 ---"
  echo "      | seen=$(grep -o '"addr"' "$IN/compare-20260804-080000.json" 2>/dev/null | wc -l | tr -d ' ') exists=$([ -e "$IN/compare-20260804-080000.json" ] && echo yes || echo no)"
fi
# B2 --json 的 stdout 不被告警污染（告警必须走 stderr）
rm -f "$IN/compare-20260804-080000.json"
trs --json > "$STUB/j.json" 2>/dev/null
if command -v python3 >/dev/null 2>&1; then
  python3 -c "import json; json.load(open('$STUB/j.json'))" 2>/dev/null && ok "--json stdout 仍是合法 JSON" || notok "--json stdout 非法"
else
  grep -q '^{' "$STUB/j.json" && ok "--json stdout 以 JSON 开头（无 python3，弱校验）" || notok "--json stdout 非 JSON"
fi

echo "═══ C. 数据安全回归（中断语义 + 测试不毁用户数据） ═══"
cat > "$STUB/probe.sh" <<'EOF'
#!/bin/bash
cd "$1" || exit 1
source lib/core.sh || exit 1
install_exit_traps
sleep 20
echo "SHOULD-NOT-REACH"
EOF
chmod +x "$STUB/probe.sh"
PATH="$STUB:$PATH" "$STUB/probe.sh" "$PWD" > "$STUB/probe.out" 2>&1 &
pp=$!
sleep 1
kill -TERM $pp 2>/dev/null
wait $pp 2>/dev/null; prc=$?
[ "$prc" = "143" ] && ok "install_exit_traps: TERM 退出码=143" || notok "install_exit_traps: TERM 退出码=${prc}（应 143）"
grep -q "SHOULD-NOT-REACH" "$STUB/probe.out" 2>/dev/null && notok "TERM 后脚本仍继续执行（trap 缺 exit）" || ok "TERM 后未继续执行（中止语义正确）"
grep -q 'cp -a results' tests/06_compare_e2e.sh && ok "tests/06 以 cp 备份用户 results/（mv 会让唯一副本离开原位）" || notok "tests/06 未用 cp 备份 results/"
grep -q 'cp -a trends' tests/06_compare_e2e.sh && ok "tests/06 同时备份用户 trends/（原先从未备份却无条件删）" || notok "tests/06 未备份 trends/"
grep -qE '(^|[^a-z])mv results ' tests/06_compare_e2e.sh && notok "tests/06 仍以 mv 移动用户 results/" || ok "tests/06 不再以 mv 移动用户数据"

echo "═══ D. 变量紧邻中文的写法守卫（macOS bash 3.2 实测翻车点） ═══"
# 为什么需要：`$f（含…` 这种「变量紧跟多字节字符」的写法，在 macOS 自带的 bash 3.2 +
# UTF-8 locale 下会被解析成变量名 `f` + 中文首字节，于是该变量展开为空、多字节字符被
# 劈掉首字节渲染成乱码。CI 实测：trends.sh 的解析告警在 macOS 上把文件名整段吞掉
# （ubuntu 与 bash 5 一切正常），断言才把它抓出来。修法是写成 `${f}（含…`。
# 这里做静态守卫，防止再引入同类写法（注释行不参与展开，故排除）。
if command -v python3 >/dev/null 2>&1 && python3 -c 'pass' 2>/dev/null; then
  BADFMT=$(python3 - <<'PYEOF'
import re, pathlib
pat = re.compile(r'\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7f]')
out = []
for p in sorted(pathlib.Path('.').rglob('*')):
    if p.suffix not in ('.sh', '.pm') or not p.is_file() or '.git' in p.parts:
        continue
    for i, line in enumerate(p.read_text(encoding='utf-8', errors='replace').splitlines(), 1):
        s = line.strip()
        if s.startswith('#'):
            continue
        for m in pat.finditer(line):
            out.append('%s:%d: %s' % (p, i, s[:100]))
print('\n'.join(out))
PYEOF
)
  if [ -z "$BADFMT" ]; then
    ok "代码中无「\$var 紧跟非 ASCII」写法"
  else
    notok "存在「\$var 紧跟非 ASCII」写法（macOS bash 3.2 下变量名会被多字节首字节污染）"
    printf '%s\n' "$BADFMT" | sed 's/^/      | /'
  fi
else
  echo "  ⏭️  跳过（无可用 python3）"
fi

echo ""
echo "════════ tests/10 结果: ✅${PASS} 通过  ❌${FAIL} 失败 ════════"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
