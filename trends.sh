#!/bin/bash
# ============================================================================
# DNS 趋势洞察：聚合 compare.sh 的历史 JSON 结果，输出趋势总览/CSV/HTML报告
# 兼容性: bash 3.2+（无关联数组依赖，macOS 默认 bash 可直接运行）
# 用法: bash trends.sh [DNS地址...] [--html] [--open] [--md] [--json] [--csv] [--vs A,B] [--cron] [--detail] [--limit N] [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--prune N] [--archive] [--archive-keep N] [--export] [--alert N] [--webhook URL] [--week N]
#   例: bash trends.sh                              # 全部DNS趋势总览（文本，含P95/时段/日级/周对比/突变检测）
#       bash trends.sh 223.5.5.5                    # 只看223.5.5.5
#       bash trends.sh --html --csv                 # 生成 trends/report.html + trends.csv
#       bash trends.sh --html --open                # 生成HTML并自动在浏览器打开（隐含--html）
#       bash trends.sh --md                         # 生成 trends/report.md（GitHub/PR友好）
#       bash trends.sh --json                       # 趋势汇总JSON到stdout（文本转stderr，jq/看板友好）
#       bash trends.sh --vs 223.5.5.5,119.29.29.29  # 两DNS头对头：同轮对决胜负计数
#       bash trends.sh --cron 223.5.5.5 119.29.29.29  # 先采集(跑compare)再聚合（crontab用）
#       bash trends.sh --detail --limit 5           # 每个DNS列最近5条明细
#       bash trends.sh --since 2026-08-01 --until 2026-08-07  # 只看该周的窗口数据
#       bash trends.sh --week 14                    # 周对比窗口改14天（默认7：近N天 vs 前N天）
#       bash trends.sh --alert 70                   # 值守告警：评分均值<70或全不可达 → 提示+exit 3（cron用）
#       bash trends.sh --alert 70 --webhook https://open.feishu.cn/open-apis/bot/v2/hook/xxx
#                                                  # 告警命中时推送（飞书/钉钉/企微/Telegram/Bark/通用JSON）
#       bash trends.sh --prune 200 --archive        # 清理前先把被删JSON打包到 trends/archive/（防误删）
#       bash trends.sh --archive                    # 全量打包当前JSON到 trends/archive/（备份/迁移/报障分享）
#       bash trends.sh --export --html --md --csv   # 一键报障包：数据JSON+本次报告+doctor自检 → trends/export/
#       bash trends.sh --export --since 2026-08-01  # 报障包只带该日期之后的数据（配 --until 收窄窗口）
#       bash trends.sh --archive-keep 10            # 归档包轮转：trends/archive/ 只留最近10个包（长跑防堆积）
# 环境变量:
#   TRENDS_DIR              趋势产物目录（默认 trends/）
#   COMPARE_RESULTS_DIR     compare JSON 数据源目录（默认 results/）
# 趋势判断: 线性回归斜率为主 + 首尾对比为辅
#   评分: ↑=变好 ↓=变差；延迟: ↑=变好 ↓=变差（箭头=好坏方向，非数值方向）
#   延迟统计: 均值 + P50/P95 分位（长尾场景均值失真，P95 更真实）
#   时段分析: 按小时聚合延迟，标出最优/最差时段（每小时≥3样本才统计）
#   退出码: 0=完成  1=参数/错误  2=无可用数据  3=--alert 告警命中（cron 值守判断用）
# ============================================================================
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 1
cd "$SCRIPT_DIR" || exit 1
source lib/core.sh
source lib/trends_lib.sh

VERSION="${PROJECT_VERSION}"
SRC_DIR="${COMPARE_RESULTS_DIR:-results}"   # compare JSON 数据源
OUT_DIR="${TRENDS_DIR:-trends}"             # 趋势产物目录
GEN_HTML=0
GEN_CSV=0
GEN_MD=0
GEN_JSON=0
GEN_OPEN=0
CRON_MODE=0
DETAIL=0
LIMIT=""
SINCE=""
UNTIL=""
ALERT_N=""
PRUNE_N=""
ARCHIVE=0
ARCHIVE_KEEP=""
EXPORT=0
VS_ARG=""
WEBHOOK_URL=""
WEEK_N=7
FILTER=()

# ---------- 参数解析（while+shift风格，兼容--limit N成对取值） ----------
ARGS=("$@")
i=0
while [ $i -lt ${#ARGS[@]} ]; do
  a="${ARGS[$i]}"
  case "$a" in
    --html)   GEN_HTML=1 ;;
    --open)   GEN_HTML=1; GEN_OPEN=1 ;;   # --open 隐含 --html（打开的前提是生成）
    --csv)    GEN_CSV=1 ;;
    --md)     GEN_MD=1 ;;
    --json)   GEN_JSON=1 ;;
    --week)   i=$((i+1)); WEEK_N="${ARGS[$i]:-}"; [ -z "$WEEK_N" ] && { echo "❌ --week 缺少天数（例: --week 14 = 近14天 vs 前14天）"; exit 1; } ;;
    --webhook) i=$((i+1)); WEBHOOK_URL="${ARGS[$i]:-}"; [ -z "$WEBHOOK_URL" ] && { echo "❌ --webhook 缺少 URL（例: --webhook https://open.feishu.cn/open-apis/bot/v2/hook/xxx）"; exit 1; } ;;
    --vs)     i=$((i+1)); VS_ARG="${ARGS[$i]:-}"; [ -z "$VS_ARG" ] && { echo "❌ --vs 缺少值（例: --vs 223.5.5.5,119.29.29.29）"; exit 1; } ;;
    --cron)   CRON_MODE=1 ;;
    --detail) DETAIL=1 ;;
    --limit)  i=$((i+1)); LIMIT="${ARGS[$i]:-}"; [ -z "$LIMIT" ] && { echo "❌ --limit 缺少值"; exit 1; } ;;
    --since)  i=$((i+1)); SINCE="${ARGS[$i]:-}"; [ -z "$SINCE" ] && { echo "❌ --since 缺少值"; exit 1; } ;;
    --until)  i=$((i+1)); UNTIL="${ARGS[$i]:-}"; [ -z "$UNTIL" ] && { echo "❌ --until 缺少值"; exit 1; } ;;
    --alert)  i=$((i+1)); ALERT_N="${ARGS[$i]:-}"; [ -z "$ALERT_N" ] && { echo "❌ --alert 缺少阈值（1-100，例: --alert 70）"; exit 1; } ;;
    --prune)  i=$((i+1)); PRUNE_N="${ARGS[$i]:-}"; [ -z "$PRUNE_N" ] && { echo "❌ --prune 缺少值"; exit 1; } ;;
    --archive) ARCHIVE=1 ;;
    --archive-keep) i=$((i+1)); ARCHIVE_KEEP="${ARGS[$i]:-}"; [ -z "$ARCHIVE_KEEP" ] && { echo "❌ --archive-keep 缺少值（保留包数，例: --archive-keep 10）"; exit 1; } ;;
    --export)  EXPORT=1 ;;
    --version)
      echo "dns-test ${PROJECT_VERSION} (${PROJECT_RELEASE})"
      exit 0 ;;
    --help|-h)
      echo "用法: bash trends.sh [DNS地址...] [--html] [--open] [--md] [--json] [--csv] [--vs A,B] [--cron] [--detail] [--limit N] [--since Y-M-D] [--until Y-M-D] [--prune N] [--archive] [--archive-keep N] [--export] [--alert N] [--webhook URL] [--week N]"
      echo "  例: bash trends.sh --html --csv"
      echo "      bash trends.sh --html --open                    # 生成HTML并自动打开(隐含--html)"
      echo "      bash trends.sh --md                             # 生成 trends/report.md（GitHub/PR友好）"
      echo "      bash trends.sh --json                           # 趋势汇总JSON到stdout(文本转stderr,jq/看板友好)"
      echo "      bash trends.sh --vs 223.5.5.5,119.29.29.29      # 头对头:两DNS同轮对决胜负计数"
      echo "      bash trends.sh --cron 223.5.5.5 119.29.29.29   # 先采集再聚合(crontab用)"
      echo "      bash trends.sh --since 2026-08-01 --until 2026-08-07  # 窗口分析(含两端日期)"
      echo "      bash trends.sh --week 14                        # 周对比窗口改14天(默认7,近N天vs前N天)"
      echo "      bash trends.sh --alert 70 --webhook https://open.feishu.cn/open-apis/bot/v2/hook/xxx"
      echo "                                                    # 值守:告警命中推飞书/钉钉/企微/TG/Bark/通用 → exit 3"
      echo "      bash trends.sh --prune 200 --html              # 只保留最近200份JSON再聚合(--watch配套)"
      echo "      bash trends.sh --prune 200 --archive           # 被清理的JSON先打包trends/archive/再删(防误删)"
      echo "      bash trends.sh --archive                       # 全量打包当前JSON(备份/迁移/报障分享,不删文件)"
      echo "      bash trends.sh --export --html --md --csv      # 一键报障包:数据+报告+doctor自检→trends/export/"
      echo "      bash trends.sh --export --since 2026-08-01    # 报障包只带该日期后的数据(配--until收窄)"
      echo "      bash trends.sh --archive-keep 10              # 归档包轮转:archive/只留最近10个包(长跑防堆积)"
      echo "环境变量: TRENDS_DIR(默认trends/)  COMPARE_RESULTS_DIR(默认results/)"
      echo "退出码: 0=完成 1=参数错 2=无数据 3=--alert告警命中"
      exit 0 ;;
    --*)
      echo "❌ 未知参数: $a"; exit 1 ;;
    *)
      if valid_dns_addr "$a"; then FILTER+=("$a")
      else echo "❌ 非法DNS地址: $a"; exit 1; fi ;;
  esac
  i=$((i+1))
done

# --since/--until 日期格式校验（写错格式会静默全排除/全保留，与静默吞错不同，必须显式报错）
for _d in "since:$SINCE" "until:$UNTIL"; do
  _dv="${_d#*:}"; _dn="${_d%%:*}"
  if [ -n "$_dv" ] && ! [[ "$_dv" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "❌ --${_dn} 格式必须为 YYYY-MM-DD（例: 2026-08-01），收到: $_dv"
    exit 1
  fi
done
# --until 不能早于 --since（窗口倒挂必然空集，提前报错比"2=无数据"更可诊断）
if [ -n "$SINCE" ] && [ -n "$UNTIL" ] && [[ "$UNTIL" < "$SINCE" ]]; then
  echo "❌ --until（$UNTIL）早于 --since（$SINCE），时间窗口倒挂"
  exit 1
fi
# --alert 阈值校验：1-100 的评分百分制
if [ -n "$ALERT_N" ] && ! [[ "$ALERT_N" =~ ^(100|[1-9][0-9]?)$ ]]; then
  echo "❌ --alert 必须为 1-100 的整数（评分百分制阈值），收到: $ALERT_N"
  exit 1
fi
# --vs 头对头校验：逗号分隔恰好2个合法DNS地址且互不相同（扫描后再确认数据集中存在）
VS_A=""; VS_B=""
if [ -n "$VS_ARG" ]; then
  VS_A="${VS_ARG%%,*}"; VS_B="${VS_ARG##*,}"
  if [ "$VS_A" = "$VS_B" ] || [ -z "$VS_A" ] || [ -z "$VS_B" ]; then
    echo "❌ --vs 必须为逗号分隔的两个不同DNS（例: --vs 223.5.5.5,119.29.29.29），收到: $VS_ARG"
    exit 1
  fi
  for _v in "$VS_A" "$VS_B"; do
    if ! valid_dns_addr "$_v"; then
      echo "❌ --vs 含非法DNS地址: $_v"; exit 1
    fi
  done
fi
# --week 窗口校验：2-365 的整数天（近N天 vs 前N天，默认 7）
if ! [[ "$WEEK_N" =~ ^[0-9]+$ ]] || [ "$WEEK_N" -lt 2 ] || [ "$WEEK_N" -gt 365 ]; then
  echo "❌ --week 必须为 2-365 的整数天数，收到: $WEEK_N"
  exit 1
fi
# --webhook 校验：须为 http(s) URL，且推送时机=告警命中（需配合 --alert，否则没有触发点）
if [ -n "$WEBHOOK_URL" ]; then
  case "$WEBHOOK_URL" in
    http://*|https://*) ;;
    *) echo "❌ --webhook 必须为 http/https URL，收到: $WEBHOOK_URL"; exit 1 ;;
  esac
  if [ -z "$ALERT_N" ]; then
    echo "❌ --webhook 需配合 --alert 使用（推送时机=告警命中；例: --alert 70 --webhook https://...）"
    exit 1
  fi
fi

# ---------- --cron 采集模式：先跑 compare 再聚合 ----------
if [ "$CRON_MODE" = "1" ]; then
  if [ ${#FILTER[@]} -eq 0 ]; then
    echo "❌ --cron 需要至少一个DNS参数（要采集的DNS）"
    echo "  例: bash trends.sh --cron 223.5.5.5 119.29.29.29"
    exit 1
  fi
  mkdir -p "$OUT_DIR"
  # cron.log 超过 512KB 先轮转为 cron.log.1（防长期 cron 无限增长；只留一代足够排查）
  if [ -f "$OUT_DIR/cron.log" ] && [ "$(wc -c < "$OUT_DIR/cron.log")" -gt 524288 ]; then
    mv -f "$OUT_DIR/cron.log" "$OUT_DIR/cron.log.1"
    echo "  ♻️  cron.log 超过512KB，已轮转为 cron.log.1"
  fi
  echo "⏳ 采集: compare.sh ${FILTER[*]}"
  bash compare.sh "${FILTER[@]}" >> "$OUT_DIR/cron.log" 2>&1
  echo "   采集完成，开始聚合..."
fi

# ---------- --archive：数据归档（两种用法，纯增量不动留存文件） ----------
#   1) --archive --prune N : 被 --prune 清理的旧JSON先打包到 trends/archive/prune-<时间>.tar.gz 再删（防误删）
#   2) --archive 单独用    : 全量打包当前 compare JSON 到 trends/archive/full-<时间>.tar.gz（备份/迁移/报障分享），不删任何文件
# tar 用 -C 切目录 + 相对路径打包（BSD/GNU tar 均支持），归档包本身不自动清理（长期值守可定期删 trends/archive/）
if [ "$ARCHIVE" = "1" ] && [ -z "$PRUNE_N" ]; then
  AFULL=()
  for _f in "$SRC_DIR"/compare-*.json; do
    [ -e "$_f" ] && AFULL+=("$(basename "$_f")")
  done
  if [ ${#AFULL[@]} -eq 0 ]; then
    echo "  🗄️  --archive: $SRC_DIR 暂无 compare-*.json，跳过归档"
  else
    mkdir -p "$OUT_DIR/archive"
    A_TAR="$OUT_DIR/archive/full-$(date '+%Y%m%d-%H%M%S').tar.gz"
    if tar -czf "$A_TAR" -C "$SRC_DIR" "${AFULL[@]}" 2>/dev/null; then
      echo "  🗄️  --archive: 已全量归档 ${#AFULL[@]} 份 → $A_TAR（原文件保留不动）"
    else
      echo "  ⚠️  --archive: tar 打包失败（tar 不可用/磁盘满？），原文件未受影响"
    fi
  fi
fi

# ---------- --prune N：只保留最近 N 份 compare JSON（--watch/定时长期采集的磁盘配套清理） ----------
# glob 字典序=时间序（时间戳文件名），删最老的 TOTAL-N 份；先清理再聚合，报告口径与留存一致
# 带 --archive 时：先打包被删文件再删；打包失败则放弃本次清理（数据安全优先，聚合照常继续）
if [ -n "$PRUNE_N" ]; then
  if ! [[ "$PRUNE_N" =~ ^[1-9][0-9]*$ ]]; then
    echo "❌ --prune 参数必须为正整数（保留份数），收到: $PRUNE_N"; exit 1
  fi
  PFILES=()
  for _f in "$SRC_DIR"/compare-*.json; do
    [ -e "$_f" ] && PFILES+=("$_f")
  done
  PTOTAL=${#PFILES[@]}
  if [ "$PTOTAL" -le "$PRUNE_N" ]; then
    echo "  ♻️  --prune: 共 ${PTOTAL} 份 ≤ 保留 ${PRUNE_N} 份，无需清理"
  else
    DELN=$((PTOTAL - PRUNE_N))
    ARCHIVE_OK=1
    if [ "$ARCHIVE" = "1" ]; then
      A_NAMES=(); k=0
      for _f in "${PFILES[@]}"; do
        k=$((k+1))
        [ "$k" -le "$DELN" ] && A_NAMES+=("$(basename "$_f")")
      done
      mkdir -p "$OUT_DIR/archive"
      A_TAR="$OUT_DIR/archive/prune-$(date '+%Y%m%d-%H%M%S').tar.gz"
      if tar -czf "$A_TAR" -C "$SRC_DIR" "${A_NAMES[@]}" 2>/dev/null; then
        echo "  🗄️  已归档待清理的 ${#A_NAMES[@]} 份 → $A_TAR"
      else
        echo "  ⚠️  --archive 归档失败，为数据安全本次跳过清理（排查 tar/磁盘后重试）"
        ARCHIVE_OK=0
      fi
    fi
    if [ "$ARCHIVE_OK" = "1" ]; then
      echo "  ♻️  --prune: 共 ${PTOTAL} 份，保留最近 ${PRUNE_N} 份，删除 ${DELN} 份:"
      k=0
      for _f in "${PFILES[@]}"; do
        k=$((k+1))
        if [ "$k" -le "$DELN" ]; then
          echo "     🗑️  $(basename "$_f")"
          rm -f "$_f"
        fi
      done
    fi
  fi
fi

# ---------- --archive-keep N：归档包轮转（trends/archive/ 只留最近 N 个包，长跑防堆积） ----------
# prune-* 与 full-* 统一按文件名时间戳排序（字典序=时间序），删最老的 总数-N 个
# 建议与 --archive/--prune --archive 组合（先归档再轮转，一轮完成"打包+控量"）；单独用也可
if [ -n "$ARCHIVE_KEEP" ]; then
  if ! [[ "$ARCHIVE_KEEP" =~ ^[1-9][0-9]*$ ]]; then
    echo "❌ --archive-keep 参数必须为正整数（保留包数），收到: $ARCHIVE_KEEP"; exit 1
  fi
  KFILES=()
  for _f in "$OUT_DIR"/archive/*.tar.gz; do
    [ -e "$_f" ] && KFILES+=("$_f")
  done
  KTOTAL=${#KFILES[@]}
  if [ "$KTOTAL" -le "$ARCHIVE_KEEP" ]; then
    echo "  🗄️  --archive-keep: 共 ${KTOTAL} 个归档包 ≤ 保留 ${ARCHIVE_KEEP} 个，无需轮转"
  else
    KDEL=$((KTOTAL - ARCHIVE_KEEP))
    echo "  🗄️  --archive-keep: 共 ${KTOTAL} 个归档包，保留最近 ${ARCHIVE_KEEP} 个，删除 ${KDEL} 个:"
    k=0
    for _f in "${KFILES[@]}"; do
      k=$((k+1))
      if [ "$k" -le "$KDEL" ]; then
        echo "     🗑️  $(basename "$_f")"
        rm -f "$_f"
      fi
    done
  fi
fi

# ---------- 数据扫描 ----------
mkdir -p "$SRC_DIR" "$OUT_DIR"
# glob 展开天然按字典序（含时间戳文件名即时间序），不解析 ls 输出（规避 SC2012：文件名含空格/换字的解析风险）
FILES=""
for _f in "$SRC_DIR"/compare-*.json; do
  [ -e "$_f" ] && FILES="$FILES$_f
"
done
if [ -z "$FILES" ]; then
  echo "❌ 无数据: $SRC_DIR/compare-*.json 不存在"
  echo "  请先运行 compare.sh 至少一次，例如: bash compare.sh 223.5.5.5 119.29.29.29"
  exit 2
fi

# ============================================================================
# 解析: 拉平为 时间|addr|score|stab|delay 行
# 平行数组（兼容bash 3.2）:
#   RAW_ADDR[i] = DNS地址（出现顺序）
#   RAW_VAL[i]  = 该地址的多行数据（每行 ts|score|stab|delay，不可达行尾标UNREACH）
#   ROUNDS_TS[] = 全局轮次轴（每份JSON的采集时间戳，文件序=时间序）
#                 多DNS同图对比的共享X轴：各DNS样本按所属轮次对齐，缺轮自然留缺口
# ============================================================================
RAW_ADDR=()
RAW_VAL=()
ROUNDS_TS=()

# 查找 addr 在 RAW_ADDR 的下标（-1=不存在）
raw_idx() {
  local d="$1" k=0
  for a in "${RAW_ADDR[@]}"; do
    [ "$a" = "$d" ] && { echo "$k"; return 0; }
    k=$((k+1))
  done
  echo "-1"
}

# 查找时间戳在 ROUNDS_TS 的轮次下标（-1=不在轴上）
round_idx() {
  local t="$1" k=0
  for r in "${ROUNDS_TS[@]}"; do
    [ "$r" = "$t" ] && { echo "$k"; return 0; }
    k=$((k+1))
  done
  echo "-1"
}

rec_total=0
MODE_SEEN=""   # 已见采集模式（lite/full 混采则评分口径不一致，扫描后统一警告）
LAST_TS=""     # 最新一条采集时间戳（数据新鲜度计算用）
for f in $FILES; do
  ts=$(grep -oE '"timestamp": ?"[^"]+"' "$f" | head -1 | sed 's/"timestamp": *"//;s/"$//')
  [ -z "$ts" ] && continue
  if [ -n "$SINCE" ] && [[ "$ts" < "$SINCE" ]]; then continue; fi
  # --until 含当日整天：按日期前缀比较（ts 前缀="2026-08-13"，until 为纯日期）
  if [ -n "$UNTIL" ] && [[ "${ts:0:10}" > "$UNTIL" ]]; then continue; fi
  ROUNDS_TS+=("$ts")
  LAST_TS="$ts"
  _m=$(grep -oE '"mode": ?"[^"]+"' "$f" | head -1 | sed 's/"mode": *"//;s/"$//')
  [ -z "$_m" ] && _m="unknown"
  case " $MODE_SEEN " in *" $_m "*) ;; *) MODE_SEEN="$MODE_SEEN $_m";; esac
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    addr=$(echo "$line" | sed -n 's/.*"addr": *"\([^"]*\)".*/\1/p')
    [ -z "$addr" ] && continue
    score=$(echo "$line" | sed -n 's/.*"score": *"\([^"]*\)".*/\1/p')
    stab=$(echo "$line" | sed -n 's/.*"stab": *"\([^"]*\)".*/\1/p')
    delay=$(echo "$line" | sed -n 's/.*"delay_ms": *\([0-9]*\).*/\1/p')
    if [ ${#FILTER[@]} -gt 0 ]; then
      in=0
      for fd in "${FILTER[@]}"; do [ "$fd" = "$addr" ] && in=1; done
      [ "$in" = "0" ] && continue
    fi
    ix=$(raw_idx "$addr")
    if [ "$ix" = "-1" ]; then
      RAW_ADDR+=("$addr"); RAW_VAL+=("")
      ix=$(( ${#RAW_ADDR[@]} - 1 ))
    fi
    if [ "$score" = "不可达" ]; then
      RAW_VAL[$ix]="${RAW_VAL[$ix]}${ts}|不可达|-|${delay}|UNREACH
"
    else
      RAW_VAL[$ix]="${RAW_VAL[$ix]}${ts}|${score}|${stab}|${delay}
"
      rec_total=$((rec_total+1))
    fi
  done < <(grep -oE '"addr": ?"[^"]+", ?"score": ?"[^"]*", ?"stab": ?"[^"]*", ?"delay_ms": ?[0-9]+' "$f")
done

if [ "$rec_total" -eq 0 ]; then
  echo "❌ 无可用数据（所有记录均为不可达，或已被 --since/过滤条件排除）"
  exit 2
fi

# 期间/计数改用"已入选数据"口径（ROUNDS_TS 只含通过 --since/--until 过滤的文件，与表格/图表一致）
# 原实现取自文件名时间戳且未过滤，窗口分析时会显示全量范围与总数，口径不符
T0_TS="${ROUNDS_TS[0]:0:16}"
T1_TS="${LAST_TS:0:16}"
N_FILES=${#ROUNDS_TS[@]}

# lite/full 混采警告：两种模式测试项数不同、评分口径不同，横向趋势会失真（只警告不阻断）
# 注意不能用 case *" lite "*" full "* 单模式判定：两个字面量的首尾空格会要求两词间有两个空格（永不匹配）
_ms=" $MODE_SEEN "
if [[ "$_ms" == *" lite "* && "$_ms" == *" full "* ]]; then
  echo "⚠️  检测到 lite 与 full 两种采集模式混合：评分口径不同（测试项数不同），横向趋势仅供粗略参考"
  echo "   建议: 用 --since/--until 圈定同一模式的时段分别对比"
fi

# 数据新鲜度：最新采集距现在多久（跨平台 epoch 换算见 lib/compat.sh ts_to_epoch；解析失败静默跳过）
FRESHNESS=""
if [ -n "$LAST_TS" ]; then
  _le=$(ts_to_epoch "${LAST_TS:0:16}")
  if [ -n "$_le" ]; then
    _mins=$(( ( $(date +%s) - _le ) / 60 ))
    if   [ "$_mins" -lt 1 ];    then FRESHNESS="刚刚"
    elif [ "$_mins" -lt 60 ];   then FRESHNESS="${_mins}分钟前"
    elif [ "$_mins" -lt 1440 ]; then FRESHNESS="$(( _mins / 60 )).$(( (_mins % 60) * 10 / 60 ))小时前"
    else                             FRESHNESS="$(( _mins / 1440 )).$(( (_mins % 1440) * 10 / 1440 ))天前"
    fi
  fi
fi

# --json 模式：人类可读输出全部改走 stderr（fd 3 保留原 stdout），stdout 只留最终 JSON（管道/jq 友好）
if [ "$GEN_JSON" = "1" ]; then
  exec 3>&1 1>&2
fi

print_header "DNS趋势洞察 — ${N_FILES}次采集 | ${rec_total}条可达记录"
echo "  数据源: $SRC_DIR/compare-*.json  |  产物: $OUT_DIR/"
echo "  期间: ${T0_TS} ~ ${T1_TS}${FRESHNESS:+  |  最新采集: ${FRESHNESS}}"
echo ""

printf "  %-46s %-6s %-9s %-8s %-9s %-8s %-9s\n" "DNS" "样本" "评分均值" "评分趋势" "延迟均值" "延迟趋势" "P95延迟"
print_separator

if [ "$GEN_CSV" = "1" ]; then
  CSVF="$OUT_DIR/trends.csv"
  echo "timestamp,addr,score,stab,delay_ms" > "$CSVF"
fi

HTML_ROWS=""      # 总览表行
HTML_CHARTS=""    # 图表卡片
ALERT_CAND=""     # --alert 候选（addr_show|score_mean|n_ok|n_un，逐DNS一行，末尾统一判定）

# ============================================================================
# 趋势统计函数: 输出 "score_t|delay_t|score_mean|stab_mean|delay_mean|score_last|delay_last|n_ok|n_un|p50|p95"
#   p50/p95 = 延迟分位数（排序取位；样本≥2才出，否则 - ）
# ============================================================================
trend_stats() {
  local lines="$1"
  local ok_lines n_ok n_un
  ok_lines=$(printf '%s\n' "$lines" | grep -v UNREACH)
  n_ok=$(printf '%s\n' "$ok_lines" | grep -c '|' )
  n_un=$(printf '%s\n' "$lines" | grep -c UNREACH)
  [ -z "$n_ok" ] && n_ok=0
  [ -z "$n_un" ] && n_un=0
  if [ "$n_ok" -lt 1 ]; then
    echo "-|-|-|-|-|-|-|0|$n_un|-|-"; return
  fi
  local score_mean stab_mean delay_mean score_last delay_last
  score_mean=$(printf '%s\n' "$ok_lines" | awk -F'|' '{s+=$2} END{printf "%.1f", s/NR}')
  stab_mean=$(printf '%s\n' "$ok_lines" | awk -F'|' '{s+=$3} END{printf "%.1f", s/NR}')
  delay_mean=$(printf '%s\n' "$ok_lines" | awk -F'|' '{s+=$4} END{printf "%.1f", s/NR}')
  score_last=$(printf '%s\n' "$ok_lines" | tail -1 | cut -d'|' -f2)
  delay_last=$(printf '%s\n' "$ok_lines" | tail -1 | cut -d'|' -f4)
  # 延迟分位数：P50 中位 / P95 长尾上界（均值被长尾拉高时，P50 更接近体感）
  # 纯函数在 lib/trends_lib.sh（tests/08 覆盖）；样本<2 函数自回 "-"
  local p50 p95 _delays
  _delays=$(printf '%s\n' "$ok_lines" | awk -F'|' '{print $4}')
  p50=$(trends_percentile "$_delays" 0.5)
  p95=$(trends_percentile "$_delays" 0.95)
  local score_slope=0 delay_slope=0
  if [ "$n_ok" -ge 3 ]; then
    score_slope=$(printf '%s\n' "$ok_lines" | awk -F'|' '{n++;sx+=n-1;sy+=$2;sxx+=(n-1)*(n-1);sxy+=(n-1)*$2} END{d=n*sxx-sx*sx; printf "%.4f", (d==0)?0:(n*sxy-sx*sy)/d}')
    delay_slope=$(printf '%s\n' "$ok_lines" | awk -F'|' '{n++;sx+=n-1;sy+=$4;sxx+=(n-1)*(n-1);sxy+=(n-1)*$4} END{d=n*sxx-sx*sx; printf "%.4f", (d==0)?0:(n*sxy-sx*sy)/d}')
  fi
  local score_first delay_first
  score_first=$(printf '%s\n' "$ok_lines" | head -1 | cut -d'|' -f2)
  delay_first=$(printf '%s\n' "$ok_lines" | head -1 | cut -d'|' -f4)

  # 趋势判定（纯函数在 lib/trends_lib.sh，tests/08 覆盖；回归为主，首尾为辅）
  local score_t delay_t
  score_t=$(trends_slope_judge "$score_slope" "$score_first" "$score_last" score)
  delay_t=$(trends_slope_judge "$delay_slope" "$delay_first" "$delay_last" delay)
  echo "$score_t|$delay_t|$score_mean|$stab_mean|$delay_mean|$score_last|$delay_last|$n_ok|$n_un|$p50|$p95"
}

# ============================================================================
# SVG 图表公共框架（模板化）：card+svg 开头 / Y轴 / 收尾
# svg_chart（单DNS）与 svg_multi_chart（多DNS同图）共用；轴/极值标签统一此处，点线绘制各自保留
# 参数: chart_begin "标题" "meta副标题(可空)" w h pad_l pad_t plot_w plot_h ymin ymax
# ============================================================================
chart_begin() {
  local title="$1" meta="$2" w="$3" h="$4" pad_l="$5" pad_t="$6" plot_w="$7" plot_h="$8" ymin="$9" ymax="${10}"
  echo "<div class='card'><h2>$title</h2>"
  [ -n "$meta" ] && echo "<div class='meta'>$meta</div>"
  echo "<div class='sc'><svg viewBox='0 0 $w $h' style='min-width:${w}px;max-width:100%'>"
  echo "<line class='ax' x1='$pad_l' y1='$pad_t' x2='$pad_l' y2='$((pad_t + plot_h))'/>"
  echo "<line class='ax' x1='$pad_l' y1='$((pad_t + plot_h))' x2='$((pad_l + plot_w))' y2='$((pad_t + plot_h))'/>"
  echo "<text x='4' y='$((pad_t + 4))' font-size='10' class='ax-t'>$ymax</text>"
  echo "<text x='4' y='$((pad_t + plot_h + 4))' font-size='10' class='ax-t'>$ymin</text>"
}
chart_end() {
  echo "</svg></div>"
}

# ============================================================================
# SVG 折线图（纯bash生成，无JS依赖）
# 用法: svg_chart "addr" "数据行" "score|delay" "趋势文字" "单位" "最新值" "均值"
# ============================================================================
svg_chart() {
  local addr="$1" data="$2" metric="$3" trend="$4" unit="$5" last_disp="$6" mean_disp="$7"
  local title color
  if [ "$metric" = "score" ]; then
    title="综合评分趋势"; color="#22c55e"
  else
    title="延迟趋势 (ms) — 越低越好"; color="#3b82f6"
  fi
  local w=660 h=170 pad_l=44 pad_r=14 pad_t=22 pad_b=28
  local plot_w=$((w - pad_l - pad_r)) plot_h=$((h - pad_t - pad_b))
  local n=0
  while IFS= read -r line; do [ -n "$line" ] && n=$((n+1)); done <<< "$data"
  if [ "$n" -lt 2 ]; then
    echo "<div class='card'><h2>$addr — $title</h2><div class='meta'>样本不足（$n条，至少2条才出图）</div></div>"
    return
  fi
  local col=2; [ "$metric" = "delay" ] && col=4
  local minv maxv
  minv=$(printf '%s\n' "$data" | awk -F'|' -v c=$col 'NR==1{m=$c} {if($c<m)m=$c} END{print m}')
  maxv=$(printf '%s\n' "$data" | awk -F'|' -v c=$col 'NR==1{m=$c} {if($c>m)m=$c} END{print m}')
  [ "$minv" = "$maxv" ] && maxv=$((minv + 1))
  local pts="" dots="" labels="" i=0
  while IFS='|' read -r ts sc st dl; do
    local v=""; [ "$metric" = "score" ] && v=$sc || v=$dl
    local x=$((pad_l + i * plot_w / (n - 1)))
    local y=$((pad_t + (maxv - v) * plot_h / (maxv - minv)))
    pts="$pts $x,$y"
    dots="$dots<circle cx='$x' cy='$y' r='3' fill='$color'/>"
    if [ $i -eq 0 ] || [ $i -eq $((n - 1)) ] || [ "$n" -le 10 ]; then
      labels="$labels<text x='$x' y='$((h - 8))' font-size='10' class='ax-t' text-anchor='middle'>${ts:5:11}</text>"
    fi
    i=$((i+1))
  done <<< "$data"
  chart_begin "<span class='mono'>$addr</span> — $title" "最新: $last_disp$unit ｜ 均值: $mean_disp$unit ｜ 趋势: $trend" \
    "$w" "$h" "$pad_l" "$pad_t" "$plot_w" "$plot_h" "$minv" "$maxv"
  echo "<polyline points='$pts' fill='none' stroke='$color' stroke-width='2' stroke-linejoin='round'/>"
  echo "$dots"
  echo "$labels"
  echo "</div></div>"
}

# ============================================================================
# SVG 多DNS同图对比（纯bash生成）：所有DNS画在同一坐标系，共享轮次X轴（ROUNDS_TS）
# 用法: svg_multi_chart "score|delay"
#   读全局 RAW_ADDR/RAW_VAL/ROUNDS_TS；缺轮的DNS点跳过（线跨缺口直连），颜色按DNS序循环
# ============================================================================
MULTI_COLORS=("#22c55e" "#3b82f6" "#f59e0b" "#ef4444" "#8b5cf6" "#14b8a6" "#f97316" "#64748b")
svg_multi_chart() {
  local metric="$1"
  local n_rounds=${#ROUNDS_TS[@]}
  if [ "$n_rounds" -lt 2 ] || [ ${#RAW_ADDR[@]} -lt 2 ]; then return 0; fi
  local col=2 title unit
  if [ "$metric" = "score" ]; then title="综合评分对比"; col=2; unit="%"
  else title="延迟对比 (ms) — 越低越好"; col=4; unit="ms"; fi
  local w=660 h=200 pad_l=44 pad_r=14 pad_t=14 pad_b=40
  local plot_w=$((w - pad_l - pad_r)) plot_h=$((h - pad_t - pad_b))
  # Y 轴值域：所有DNS该指标的全局 min/max（不可达轮不参与，天然留缺口）
  local gmin="" gmax=""
  for k in "${!RAW_ADDR[@]}"; do
    while IFS='|' read -r ts sc st dl; do
      [ -z "$ts" ] && continue
      local v; [ "$metric" = "score" ] && v="$sc" || v="$dl"
      [ -z "$gmin" ] && gmin="$v"
      [ -z "$gmax" ] && gmax="$v"
      [ "$v" -lt "$gmin" ] 2>/dev/null && gmin="$v"
      [ "$v" -gt "$gmax" ] 2>/dev/null && gmax="$v"
    done <<< "$(printf '%s\n' "${RAW_VAL[$k]}" | grep -v UNREACH)"
  done
  [ -z "$gmin" ] && return 0
  [ "$gmin" = "$gmax" ] && gmax=$((gmin + 1))
  local legend="" ci=0
  chart_begin "📊 $title（${#RAW_ADDR[@]}个DNS × ${n_rounds}轮）" "" \
    "$w" "$h" "$pad_l" "$pad_t" "$plot_w" "$plot_h" "$gmin" "$gmax"
  # X 轴标签：首/尾 + 中点（轮次≥3才画中点，2轮时中=尾会重叠）
  local mid_r=$((n_rounds / 2))
  local xlabels="0 $((n_rounds - 1))"
  [ "$n_rounds" -ge 3 ] && xlabels="0 $mid_r $((n_rounds - 1))"
  for r in $xlabels; do
    local lx=$((pad_l + r * plot_w / (n_rounds - 1)))
    [ "$r" = "$((n_rounds - 1))" ] && lx=$((pad_l + plot_w))
    local anchor="middle"; [ "$r" = "0" ] && anchor="start"; [ "$r" = "$((n_rounds - 1))" ] && anchor="end"
    echo "<text x='$lx' y='$((h - 26))' font-size='10' class='ax-t' text-anchor='$anchor'>${ROUNDS_TS[$r]:5:11}</text>"
  done
  for k in "${!RAW_ADDR[@]}"; do
    local color="${MULTI_COLORS[$((ci % ${#MULTI_COLORS[@]}))]}"
    local pts="" dots="" first=1
    while IFS='|' read -r ts sc st dl; do
      [ -z "$ts" ] && continue
      local v; [ "$metric" = "score" ] && v="$sc" || v="$dl"
      local ri; ri=$(round_idx "$ts")
      [ "$ri" = "-1" ] && continue
      local x=$((pad_l + ri * plot_w / (n_rounds - 1)))
      local y=$((pad_t + (gmax - v) * plot_h / (gmax - gmin)))
      if [ "$first" = "1" ]; then pts="$x,$y"; first=0; else pts="$pts $x,$y"; fi
      dots="$dots<circle cx='$x' cy='$y' r='2.5' fill='$color'/>"
    done <<< "$(printf '%s\n' "${RAW_VAL[$k]}" | grep -v UNREACH)"
    if [ "$first" = "0" ]; then
      echo "<polyline points='$pts' fill='none' stroke='$color' stroke-width='2' stroke-linejoin='round' opacity='.85'/>"
      echo "$dots"
    fi
    # 图例：色块 + 地址（+提供商标签）
    local _lg="${RAW_ADDR[$k]}"; _lt=$(dns_preset_label "${RAW_ADDR[$k]}") && _lg="${_lg}·${_lt}"
    legend="$legend<span class='lg-i'><span class='lg-c' style='background:$color'></span>${_lg}</span>"
    ci=$((ci+1))
  done
  chart_end
  echo "<div class='legend'>$legend</div>"
  echo "<div class='meta'>X轴=采集轮次（按时间等距）；某轮不可达的DNS该点缺省，折线跨缺口直连</div>"
  echo "</div>"
}

# ============================================================================
# 主循环：每个DNS统计 + 输出（文本表/明细/时段分析/日级分析/周对比/突变检测/CSV/HTML行与图表）
# ============================================================================
HOUR_ANALYSIS=""   # 时段分析文本行（凑齐才输出小节）
DAILY_ANALYSIS=""  # 日级分析文本行（数据跨≥2天才输出小节）
WEEK_ANALYSIS=""   # 周对比文本行（近7天 vs 前7天，两窗都有样本的DNS才计入）
MUTATION_ANALYSIS="" # 突变检测文本行（延迟较上轮突增的轮次，有命中才计入）
HTML_INSIGHTS=""   # HTML 洞察卡内容（时段+日级+周对比+突变，等宽对齐）
MD_ROWS=""         # --md 总览表行（与 HTML_ROWS 同口径）
JSON_DNS=()        # --json 逐DNS对象（循环后拼装，下标与 RAW_ADDR 对齐）
WK_JSON=()         # --json 周对比对象（有 Δ 才有值，否则 null）
MUT_N=()           # --json 突变计数（按下标）
# --json 数值字段兜底：空串/"-" 等非数字输出 null（JSON 语法要求）
_num_or_null() { case "$1" in ''|*[!0-9.]*) echo "null" ;; *) echo "$1" ;; esac; }
# 周对比窗口（--week N 可配，默认7）：近N天（含今天）= 日期 >= W1；前N天 = W2 <= 日期 <= W2E
# 字符串字典序比较（零子进程开销）；date_days_ago 不可用（极端环境）时跳过该节，不阻断主流程
W1=$(date_days_ago $((WEEK_N - 1)))
W2=$(date_days_ago $((WEEK_N * 2 - 1)))
W2E=$(date_days_ago "$WEEK_N")
[ -z "$W1" ] && W2=""   # W1 失败则一并停用（W2 单独存在无意义）
for k in "${!RAW_ADDR[@]}"; do
  addr="${RAW_ADDR[$k]}"
  lines="${RAW_VAL[$k]}"
  stats=$(trend_stats "$lines")
  score_t=$(echo "$stats" | cut -d'|' -f1)
  delay_t=$(echo "$stats" | cut -d'|' -f2)
  score_mean=$(echo "$stats" | cut -d'|' -f3)
  stab_mean=$(echo "$stats" | cut -d'|' -f4)
  delay_mean=$(echo "$stats" | cut -d'|' -f5)
  score_last=$(echo "$stats" | cut -d'|' -f6)
  delay_last=$(echo "$stats" | cut -d'|' -f7)
  n_ok=$(echo "$stats" | cut -d'|' -f8)
  n_un=$(echo "$stats" | cut -d'|' -f9)
  p50=$(echo "$stats" | cut -d'|' -f10)
  p95=$(echo "$stats" | cut -d'|' -f11)

  # 提供商标签（预设内 DNS 才有，与 compare.sh 报告同口径）
  addr_show="$addr"
  plabel=$(dns_preset_label "$addr") && addr_show="${addr}·${plabel}"

  un_suffix=""
  [ "$n_un" -gt 0 ] && un_suffix=" (含${n_un}次不可达)"
  p95_show="-"; [ "$p95" != "-" ] && p95_show="${p95}ms"
  ALERT_CAND="${ALERT_CAND}${addr_show}|${score_mean:-0}|${n_ok}|${n_un}
"

  if [ "$n_ok" -ge 1 ]; then
    printf "  %-46s %-6s %-9s %-8s %-9s %-8s %-9s%s\n" "$addr_show" "$n_ok" "$score_mean%" "$score_t" "${delay_mean}ms" "$delay_t" "$p95_show" "$un_suffix"
  else
    printf "  %-46s %-6s %-9s %-8s %-9s %-8s %-9s%s\n" "$addr_show" "0" "-" "-" "-" "-" "-" "$un_suffix"
  fi

  # 时段分析：按小时聚合延迟（ts 取 HH 字段），每小时≥3样本才可信；输出最优/最差时段
  if [ "$n_ok" -ge 3 ]; then
    hours_stat=$(printf '%s\n' "$lines" | grep -v UNREACH | grep -v '^$' | awk -F'|' '{
      n=split($1, dt, " "); split(dt[2], hm, ":"); h=hm[1]
      sum[h]+=$4; cnt[h]++
    } END {
      for (h in sum) if (cnt[h]>=3) printf "%s %.1f %d\n", h, sum[h]/cnt[h], cnt[h]
    }' | sort -k2 -n)
    if [ -n "$hours_stat" ]; then
      best_h=$(echo "$hours_stat" | head -1)
      worst_h=$(echo "$hours_stat" | tail -1)
      bh=$(echo "$best_h"  | awk '{print $1}'); bd=$(echo "$best_h"  | awk '{print $2}')
      wh=$(echo "$worst_h" | awk '{print $1}'); wd=$(echo "$worst_h" | awk '{print $2}')
      HOUR_ANALYSIS="${HOUR_ANALYSIS}  ${addr_show}
    最差 ${wh}:00 均延${wd}ms ｜ 最优 ${bh}:00 均延${bd}ms ｜ 全程均值${delay_mean}ms
"
    fi
  fi

  # 日级分析：按天聚合评分/延迟均值（跨天采集才有意义；该DNS数据跨≥2天才计入）
  if [ "$n_ok" -ge 2 ]; then
    day_stat=$(printf '%s\n' "$lines" | grep -v UNREACH | grep -v '^$' | awk -F'|' '{
      n=split($1, dt, " "); d=substr(dt[1], 6)   # 取 MM-DD
      sc[d]+=$2; dl[d]+=$4; cnt[d]++
    } END {
      for (d in cnt) printf "%s %.1f %.1f %d\n", d, sc[d]/cnt[d], dl[d]/cnt[d], cnt[d]
    }' | sort)
    n_days=$(printf '%s\n' "$day_stat" | grep -c .)
    if [ "$n_days" -ge 2 ]; then
      DAILY_ANALYSIS="${DAILY_ANALYSIS}  ${addr_show}
"
      while read -r dline; do
        [ -z "$dline" ] && continue
        dd=$(echo "$dline" | awk '{print $1}')
        dsc=$(echo "$dline" | awk '{print $2}')
        ddl=$(echo "$dline" | awk '{print $3}')
        dcn=$(echo "$dline" | awk '{print $4}')
        DAILY_ANALYSIS="${DAILY_ANALYSIS}    ${dd}  均分${dsc}  均延${ddl}ms（${dcn}样本）
"
      done <<< "$day_stat"
    fi
  fi

  # 周对比：近7天（含今天）vs 前7天 的评分/延迟均值变化（两窗都有样本才有 Δ 可言）
  if [ -n "$W2" ] && [ "$n_ok" -ge 2 ]; then
    wk_stat=$(printf '%s\n' "$lines" | grep -v UNREACH | grep -v '^$' | awk -F'|' -v w1="$W1" -v w2="$W2" -v w2e="$W2E" '{
      d=substr($1,1,10)
      if (d>=w1) { s1+=$2; dl1+=$4; n1++ }
      else if (d>=w2 && d<=w2e) { s2+=$2; dl2+=$4; n2++ }
    } END {
      if (n1>0 && n2>0) printf "%.1f %.1f %.1f %.1f %d %d", s2/n2, s1/n1, dl2/n2, dl1/n1, n2, n1
    }')
    if [ -n "$wk_stat" ]; then
      wk_prev_s=$(echo "$wk_stat" | awk '{print $1}')
      wk_cur_s=$(echo "$wk_stat"  | awk '{print $2}')
      wk_prev_d=$(echo "$wk_stat" | awk '{print $3}')
      wk_cur_d=$(echo "$wk_stat"  | awk '{print $4}')
      wk_prev_n=$(echo "$wk_stat" | awk '{print $5}')
      wk_cur_n=$(echo "$wk_stat"  | awk '{print $6}')
      wk_ds=$(awk "BEGIN{printf \"%+.1f\", $wk_cur_s - $wk_prev_s}")
      wk_dd=$(awk "BEGIN{printf \"%+.1f\", $wk_cur_d - $wk_prev_d}")
      # Δ符号语义: 评分升=好，延迟降=好（箭头=好坏方向）
      wk_ds_mark="→"; awk "BEGIN{exit !($wk_ds>0.5)}"  && wk_ds_mark="↑"
      awk "BEGIN{exit !($wk_ds<-0.5)}" && wk_ds_mark="↓"
      wk_dd_mark="→"; awk "BEGIN{exit !($wk_dd<-1)}"   && wk_dd_mark="↑"
      awk "BEGIN{exit !($wk_dd>1)}"    && wk_dd_mark="↓"
      WEEK_ANALYSIS="${WEEK_ANALYSIS}  ${addr_show}
    评分 ${wk_prev_s}%→${wk_cur_s}%（${wk_ds} ${wk_ds_mark}）｜ 延迟 ${wk_prev_d}ms→${wk_cur_d}ms（${wk_dd}ms ${wk_dd_mark}）｜ 样本 ${wk_prev_n}→${wk_cur_n}
"
      # --json 周对比对象（Δ 数值剥掉前导 + 号：JSON 数字不允许 +20.0 写法）
      WK_JSON[$k]="{\"prev_score\": ${wk_prev_s}, \"cur_score\": ${wk_cur_s}, \"delta_score\": ${wk_ds#+}, \"prev_delay_ms\": ${wk_prev_d}, \"cur_delay_ms\": ${wk_cur_d}, \"delta_delay_ms\": ${wk_dd#+}, \"prev_n\": ${wk_prev_n}, \"cur_n\": ${wk_cur_n}}"
    fi
  fi

  # 突变检测：延迟较上一轮突增（Δ>+100ms 且 >2×前值）视为异常轮（网络抖动/加速器抽风定位）
  if [ "$n_ok" -ge 2 ]; then
    mut_hits=$(printf '%s\n' "$lines" | grep -v UNREACH | grep -v '^$' | awk -F'|' '
      NR>1 && ($4-prev_d>100 && $4>2*prev_d) {
        printf "    %-16s %sms→%sms（+%dms，为上轮%.1f倍）\n", substr($1,1,16), prev_d, $4, $4-prev_d, $4/prev_d
      }
      { prev_d=$4 }')
    if [ -n "$mut_hits" ]; then
      mut_cnt=$(printf '%s\n' "$mut_hits" | grep -c .)
      MUT_N[$k]=$mut_cnt
      MUTATION_ANALYSIS="${MUTATION_ANALYSIS}  ${addr_show}（${mut_cnt}次突增）
${mut_hits}
"
    fi
  fi

  # CSV
  if [ "$GEN_CSV" = "1" ] && [ "$n_ok" -ge 1 ]; then
    printf '%s\n' "$lines" | grep -v UNREACH | grep -v '^$' | while IFS='|' read -r ts sc st dl; do
      echo "$ts,$addr,$sc,$st,$dl" >> "$CSVF"
    done
  fi

  # 明细（--detail）
  if [ "$DETAIL" = "1" ] && [ "$n_ok" -ge 1 ]; then
    printf '     ── %s 明细（最早→最新）──\n' "$addr_show"
    printf '%s\n' "$lines" | grep -v UNREACH | grep -v '^$' | tail -n "${LIMIT:-10}" | while IFS='|' read -r ts sc st dl; do
      tss=$(echo "$ts" | sed 's/^[0-9]*-\([0-9]*-[0-9]* [0-9]*:[0-9]*\).*/\1/')
      printf '        %-12s 评分%-4s 稳定性%-4s 延迟%sms\n' "$tss" "$sc" "$st" "$dl"
    done
  fi

  # HTML
  if [ "$GEN_HTML" = "1" ]; then
    pl_b=""; [ -n "${plabel:-}" ] && pl_b="<span class='pname'>${plabel}</span>"
    if [ "$n_ok" -ge 1 ]; then
      stc="flat"
      case "$score_t" in *变好*) stc="up";; *变差*) stc="down";; esac
      dtc="flat"
      case "$delay_t" in *变好*) dtc="up";; *变差*) dtc="down";; esac
      HTML_ROWS="$HTML_ROWS<tr><td class='addr'>$addr$pl_b</td><td>$n_ok</td><td>${score_mean}%</td><td><span class='bdg b-$stc'>$score_t</span></td><td>${delay_mean}ms</td><td><span class='bdg b-$dtc'>$delay_t</span></td><td>${p95_show}</td></tr>"
    else
      HTML_ROWS="$HTML_ROWS<tr><td class='addr'>$addr$pl_b</td><td>0</td><td>—</td><td><span class='bdg b-flat'>—</span></td><td>—</td><td><span class='bdg b-flat'>—</span></td><td>—</td></tr>"
    fi
    ok_lines=$(printf '%s\n' "$lines" | grep -v UNREACH)
    if [ "$n_ok" -ge 2 ]; then
      HTML_CHARTS="$HTML_CHARTS$(svg_chart "$addr_show" "$ok_lines" score "$score_t" "%" "$score_last" "$score_mean")"
      HTML_CHARTS="$HTML_CHARTS$(svg_chart "$addr_show" "$ok_lines" delay "$delay_t" "ms" "$delay_last" "$delay_mean")"
    fi
  fi

  # --md 总览表行（与文本表同口径；addr_show 无需转义，仅含 hex/点/冒号/中文/·）
  if [ "$GEN_MD" = "1" ]; then
    if [ "$n_ok" -ge 1 ]; then
      MD_ROWS="${MD_ROWS}| \`${addr_show}\` | ${n_ok} | ${score_mean}% | ${score_t} | ${delay_mean}ms | ${delay_t} | ${p95_show} |
"
    else
      MD_ROWS="${MD_ROWS}| \`${addr_show}\` | 0 | — | — | — | — | — |
"
    fi
  fi

  # --json 逐DNS对象（与文本表同口径；均值/末值非数字时输出 null，P50/P95 同）
  if [ "$GEN_JSON" = "1" ]; then
    sm=$(_num_or_null "$score_mean"); dm=$(_num_or_null "$delay_mean")
    sl=$(_num_or_null "$score_last"); dl=$(_num_or_null "$delay_last")
    p5=$(_num_or_null "$p50"); p9=$(_num_or_null "$p95")
    st=$(json_escape "$score_t"); dt=$(json_escape "$delay_t"); lb=$(json_escape "${plabel:-}")
    wk_j="${WK_JSON[$k]:-null}"
    JSON_DNS[${#JSON_DNS[@]}]="    {\"addr\": \"${addr}\", \"label\": \"${lb}\", \"n_ok\": ${n_ok:-0}, \"n_unreach\": ${n_un:-0}, \"score_mean\": ${sm}, \"score_last\": ${sl}, \"score_trend\": \"${st}\", \"delay_mean\": ${dm}, \"delay_last\": ${dl}, \"delay_trend\": \"${dt}\", \"delay_p50_ms\": ${p5}, \"delay_p95_ms\": ${p9}, \"mutation_count\": ${MUT_N[$k]:-0}, \"week\": ${wk_j}}"
  fi
done

# ---------- 时段/日级分析小节（文本；有满足条件的DNS才输出） ----------
if [ -n "$HOUR_ANALYSIS" ]; then
  echo ""
  echo "  ━━━ 时段分析（按小时聚合，每小时≥3样本才统计） ━━━"
  printf '%s' "$HOUR_ANALYSIS"
fi
if [ -n "$DAILY_ANALYSIS" ]; then
  echo ""
  echo "  ━━━ 日级分析（按天聚合，数据跨≥2天才显示） ━━━"
  printf '%s' "$DAILY_ANALYSIS"
fi
if [ -n "$WEEK_ANALYSIS" ]; then
  echo ""
  echo "  ━━━ 周对比（近${WEEK_N}天 vs 前${WEEK_N}天，两窗都有样本才显示） ━━━"
  printf '%s' "$WEEK_ANALYSIS"
fi
if [ -n "$MUTATION_ANALYSIS" ]; then
  echo ""
  echo "  ━━━ 突变检测（延迟较上轮 +100ms 且 >2× 记为突增） ━━━"
  printf '%s' "$MUTATION_ANALYSIS"
fi

# ---------- --vs 头对头：两DNS同轮对决胜负计数（同轮都可达才成局，评分高者胜） ----------
VS_TEXT=""
if [ -n "$VS_A" ]; then
  va_idx=$(raw_idx "$VS_A"); vb_idx=$(raw_idx "$VS_B")
  if [ "$va_idx" = "-1" ] || [ "$vb_idx" = "-1" ]; then
    _miss=""; [ "$va_idx" = "-1" ] && _miss="$VS_A"
    [ "$vb_idx" = "-1" ] && _miss="${_miss:+$_miss }$VS_B"
    echo "❌ --vs 的 ${_miss} 不在数据集中（先采集该DNS: bash compare.sh $VS_A $VS_B）"
    exit 1
  fi
  wins_a=0; wins_b=0; draws=0; duel_n=0
  for r in "${ROUNDS_TS[@]}"; do
    # 该轮两方评分（RAW_VAL 行= "ts|score|stab|delay"；不可达行尾标 UNREACH 已排除）
    sa=$(printf '%s\n' "${RAW_VAL[$va_idx]}" | grep -F "$r|" | grep -v UNREACH | head -1 | cut -d'|' -f2)
    sb=$(printf '%s\n' "${RAW_VAL[$vb_idx]}" | grep -F "$r|" | grep -v UNREACH | head -1 | cut -d'|' -f2)
    [ -z "$sa" ] || [ -z "$sb" ] && continue
    duel_n=$((duel_n+1))
    if [ "$sa" -gt "$sb" ]; then wins_a=$((wins_a+1))
    elif [ "$sb" -gt "$sa" ]; then wins_b=$((wins_b+1))
    else draws=$((draws+1)); fi
  done
  if [ "$duel_n" -gt 0 ]; then
    # 均值对比（复用 trend_stats 的均值口径）
    va_mean=$(trend_stats "${RAW_VAL[$va_idx]}" | cut -d'|' -f3)
    vb_mean=$(trend_stats "${RAW_VAL[$vb_idx]}" | cut -d'|' -f3)
    va_dmean=$(trend_stats "${RAW_VAL[$va_idx]}" | cut -d'|' -f5)
    vb_dmean=$(trend_stats "${RAW_VAL[$vb_idx]}" | cut -d'|' -f5)
    va_show="$VS_A"; _vl=$(dns_preset_label "$VS_A") && va_show="$VS_A·$_vl"
    vb_show="$VS_B"; _vl=$(dns_preset_label "$VS_B") && vb_show="$VS_B·$_vl"
    vs_verdict="势均力敌"
    [ "$wins_a" -gt $((duel_n * 2 / 3)) ] && vs_verdict="🏆 ${va_show} 占优"
    [ "$wins_b" -gt $((duel_n * 2 / 3)) ] && vs_verdict="🏆 ${vb_show} 占优"
    VS_TEXT="⚔️  头对头（同轮对决 ${duel_n} 局）: ${va_show} 胜${wins_a} ｜ ${vb_show} 胜${wins_b} ｜ 平${draws} ｜ ${vs_verdict}
    全期均值: 评分 ${va_mean}% vs ${vb_mean}% ｜ 延迟 ${va_dmean}ms vs ${vb_dmean}ms
"
    echo ""
    echo "  ━━━ 头对头 --vs（同轮对决，评分高者胜） ━━━"
    printf '%s' "$VS_TEXT"
  else
    echo ""
    echo "  ⚔️  --vs: ${VS_A} 与 ${VS_B} 无同轮都可达的采集记录，无法对决（需同轮对比采集: bash compare.sh $VS_A $VS_B）"
  fi
fi

# HTML 洞察卡内容（时段/日级/周对比/突变/头对头一并给 HTML；等宽 pre 风格，数据均为数字/地址无需转义）
if [ "$GEN_HTML" = "1" ]; then
  if [ -n "$HOUR_ANALYSIS" ]; then
    HTML_INSIGHTS="⏰ 时段分析（每小时≥3样本）
${HOUR_ANALYSIS}
"
  fi
  if [ -n "$DAILY_ANALYSIS" ]; then
    HTML_INSIGHTS="${HTML_INSIGHTS}📅 日级分析（跨≥2天）
${DAILY_ANALYSIS}
"
  fi
  if [ -n "$WEEK_ANALYSIS" ]; then
    HTML_INSIGHTS="${HTML_INSIGHTS}📆 周对比（近${WEEK_N}天 vs 前${WEEK_N}天）
${WEEK_ANALYSIS}
"
  fi
  if [ -n "$MUTATION_ANALYSIS" ]; then
    HTML_INSIGHTS="${HTML_INSIGHTS}⚡ 突变检测（延迟较上轮 +100ms 且 >2×）
${MUTATION_ANALYSIS}
"
  fi
  if [ -n "$VS_TEXT" ]; then
    HTML_INSIGHTS="${HTML_INSIGHTS}${VS_TEXT}
"
  fi
fi

if [ "$GEN_CSV" = "1" ]; then
  echo ""
  echo "  📄 CSV已导出: $CSVF"
fi

# ---------- HTML 报告（与 compare.sh 同套视觉：CSS 变量双主题，自动跟随系统暗色） ----------
if [ "$GEN_HTML" = "1" ]; then
  HF="$OUT_DIR/report.html"
  {
    echo "<!DOCTYPE html>"
    echo "<html lang='zh'><head><meta charset='utf-8'>"
    echo "<meta name='viewport' content='width=device-width,initial-scale=1'>"
    echo "<meta name='color-scheme' content='light dark'>"
    echo "<title>DNS趋势报告</title>"
    echo "<style>"
    echo ":root{--bg:#f5f7fa;--card:#fff;--tx:#333;--sub:#888;--th-bg:#fafbfc;--th-tx:#666;--line:#eee;--gtx:#16a34a;--rtx:#dc2626;--mono:ui-monospace,SFMono-Regular,Menlo,Consolas,'Courier New',monospace}"
    echo "@media(prefers-color-scheme:dark){:root{--bg:#0f172a;--card:#1e293b;--tx:#e2e8f0;--sub:#94a3b8;--th-bg:#283548;--th-tx:#94a3b8;--line:#334155;--gtx:#4ade80;--rtx:#f87171}}"
    echo "body{font-family:-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;margin:0;background:var(--bg);color:var(--tx)}"
    echo ".wrap{max-width:920px;margin:24px auto;padding:0 16px}"
    echo ".card{background:var(--card);border-radius:12px;padding:20px 24px;margin:16px 0;box-shadow:0 2px 8px rgba(0,0,0,.06)}"
    echo "h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:14px 0 6px;color:var(--sub)}"
    echo ".meta{color:var(--sub);font-size:13px;margin-bottom:10px}"
    echo ".mono{font-family:var(--mono)}"
    echo "td.addr{font-family:var(--mono);font-size:13px}"
    echo ".pname{display:block;font-size:11px;color:var(--sub);font-family:inherit;margin-top:1px}"
    echo ".bdg{display:inline-block;min-width:52px;text-align:center;padding:2px 10px;border-radius:999px;font-size:12px;font-weight:600}"
    echo ".b-up{background:rgba(34,197,94,.14);color:var(--gtx)}.b-down{background:rgba(239,68,68,.14);color:var(--rtx)}.b-flat{background:rgba(127,127,127,.12);color:var(--sub)}"
    echo ".tbl-wrap{overflow-x:auto;-webkit-overflow-scrolling:touch}"
    echo "table{width:100%;border-collapse:collapse;font-size:14px;margin:10px 0}"
    echo "th,td{padding:8px 10px;text-align:left;border-bottom:1px solid var(--line);white-space:nowrap}"
    echo "th{background:var(--th-bg);color:var(--th-tx);font-weight:600}"
    echo "tbody tr:nth-child(even){background:rgba(127,127,127,.04)}"
    echo ".sc{overflow-x:auto}"
    echo ".ax{stroke:var(--line)}.ax-t{fill:var(--sub)}"
    echo ".insight{white-space:pre-wrap;font-family:var(--mono);font-size:12px;line-height:1.8;color:var(--tx);overflow-x:auto}"
    echo ".legend{display:flex;flex-wrap:wrap;gap:6px 16px;margin-top:8px;font-size:12px;font-family:var(--mono)}"
    echo ".lg-i{display:inline-flex;align-items:center;gap:5px;color:var(--tx)}"
    echo ".lg-c{display:inline-block;width:14px;height:4px;border-radius:2px}"
    echo "@media(max-width:600px){.wrap{padding:0 8px}.card{padding:14px}table{font-size:12px}}"
    echo "@media print{body{background:#fff}.card{box-shadow:none;border:1px solid #ddd;break-inside:avoid}}"
    echo "</style></head><body>"
    echo "<div class='wrap'>"
    echo "<div class='card'><h1>📈 DNS 趋势报告</h1>"
    echo "<div class='meta'>${N_FILES}次采集（${T0_TS} ~ ${T1_TS}）${FRESHNESS:+｜ 最新采集 ${FRESHNESS}}｜ dns-test ${VERSION} ｜ 数据源 ${SRC_DIR}/compare-*.json</div>"
    echo "<div class='tbl-wrap'><table><thead><tr><th>DNS</th><th>样本</th><th>评分均值</th><th>评分趋势</th><th>延迟均值</th><th>延迟趋势</th><th>P95延迟</th></tr></thead><tbody>"
    echo "$HTML_ROWS"
    echo "</tbody></table></div></div>"
    # 洞察卡（时段+日级分析；有内容才输出）
    if [ -n "$HTML_INSIGHTS" ]; then
      echo "<div class='card'><h2>🔍 洞察</h2><div class='insight'>${HTML_INSIGHTS}</div></div>"
    fi
    # 多DNS同图对比总图（≥2个DNS且≥2轮才出；放在单DNS明细图之前，先总后分）
    echo "$(svg_multi_chart score)"
    echo "$(svg_multi_chart delay)"
    echo "$HTML_CHARTS"
    # 归档包清单（--archive/--prune 产物；有才显示；时间取文件名内嵌时间戳，大小 wc -c 免解析 ls）
    if ls "$OUT_DIR"/archive/*.tar.gz >/dev/null 2>&1; then
      echo "<div class='card'><h2>🗄️ 归档包（${OUT_DIR}/archive/）</h2>"
      echo "<div class='tbl-wrap'><table><thead><tr><th>包名</th><th>类型</th><th>大小</th></tr></thead><tbody>"
      for _a in "$OUT_DIR"/archive/*.tar.gz; do
        [ -e "$_a" ] || continue
        case "$(basename "$_a")" in
          prune-*) _at="清理前备份" ;;
          full-*)  _at="全量快照" ;;
          *)       _at="-" ;;
        esac
        _b=$(wc -c < "$_a" | tr -d ' ')
        _sz=$(awk -v b="$_b" 'BEGIN{printf (b>=1048576)?"%.1f MB":((b>=1024)?"%.0f KB":"%d B"), (b>=1048576)?b/1048576:((b>=1024)?b/1024:b)}')
        echo "<tr><td class='addr'>$(basename "$_a")</td><td>${_at}</td><td>${_sz}</td></tr>"
      done
      echo "</tbody></table></div>"
      echo "<div class='meta'>恢复历史: tar -xzf 包名 -C ${SRC_DIR}/（prune-*=清理前备份，full-*=全量快照；积多可定期清理）</div></div>"
    fi
    echo "</div></body></html>"
  } > "$HF"
  echo ""
  echo "  📄 HTML趋势报告已生成: $HF"
  # --open：生成后自动用系统浏览器打开（open_report_file 已下沉 lib/core.sh）
  if [ "${GEN_OPEN:-0}" = "1" ]; then
    open_report_file "$HF"
  fi
fi

# ---------- Markdown 报告（--md）— GitHub/PR/Issue 友好，与 compare --md 同风格 ----------
if [ "$GEN_MD" = "1" ]; then
  MF="$OUT_DIR/report.md"
  {
    echo "# DNS 趋势报告"
    echo ""
    echo "> ${N_FILES}次采集（${T0_TS} ~ ${T1_TS}）${FRESHNESS:+｜ 最新采集 ${FRESHNESS}}｜ dns-test ${VERSION}｜ 数据源 \`${SRC_DIR}/compare-*.json\`"
    echo ""
    echo "| DNS | 样本 | 评分均值 | 评分趋势 | 延迟均值 | 延迟趋势 | P95延迟 |"
    echo "|-----|------|---------|---------|---------|---------|--------|"
    printf '%s' "$MD_ROWS"
    echo ""
    if [ -n "$WEEK_ANALYSIS" ]; then
      echo "## 周对比（近${WEEK_N}天 vs 前${WEEK_N}天）"
      echo ""
      echo '```'
      printf '%s' "$WEEK_ANALYSIS"
      echo '```'
      echo ""
    fi
    if [ -n "$MUTATION_ANALYSIS" ]; then
      echo "## 突变检测（延迟较上轮 +100ms 且 >2× 记为突增）"
      echo ""
      echo '```'
      printf '%s' "$MUTATION_ANALYSIS"
      echo '```'
      echo ""
    fi
    if [ -n "$VS_TEXT" ]; then
      echo "## 头对头（同轮对决）"
      echo ""
      echo '```'
      printf '%s' "$VS_TEXT"
      echo '```'
      echo ""
    fi
    if [ -n "$HOUR_ANALYSIS" ]; then
      echo "## 时段分析（按小时聚合）"
      echo ""
      echo '```'
      printf '%s' "$HOUR_ANALYSIS"
      echo '```'
      echo ""
    fi
    if [ -n "$DAILY_ANALYSIS" ]; then
      echo "## 日级分析（按天聚合）"
      echo ""
      echo '```'
      printf '%s' "$DAILY_ANALYSIS"
      echo '```'
      echo ""
    fi
    echo "---"
    echo "<sub>由 dns-test ${VERSION} 生成；采集: \`bash compare.sh DNS1 DNS2 --watch 30\`；HTML: \`bash trends.sh --html\`</sub>"
  } > "$MF"
  echo ""
  echo "  📝 Markdown趋势报告已生成: $MF"
fi

# ---------- --alert 值守告警：评分均值低于阈值 或 全程不可达 → 列出并 exit 3 ----------
# cron 场景按退出码分发（≠0 即触发通知通道）；文本模式同样输出，人肉跑也能看到
ALERT_HITS=""
ALERT_JSON_DNS=""
if [ -n "$ALERT_N" ]; then
  while IFS='|' read -r aname amean aok aun; do
    [ -z "$aname" ] && continue
    if [ "$aok" = "0" ]; then
      ALERT_HITS="${ALERT_HITS}  🚨 ${aname}: 全部 ${aun} 次采集均不可达
"
      ALERT_JSON_DNS="${ALERT_JSON_DNS}, {\"dns\": \"$(json_escape "$aname")\", \"reason\": \"all_unreachable\"}"
    elif awk "BEGIN{exit !($amean < $ALERT_N)}"; then
      ALERT_HITS="${ALERT_HITS}  🚨 ${aname}: 评分均值 ${amean}% 低于阈值 ${ALERT_N}%
"
      ALERT_JSON_DNS="${ALERT_JSON_DNS}, {\"dns\": \"$(json_escape "$aname")\", \"reason\": \"score_below_threshold\", \"score_mean\": ${amean:-null}}"
    fi
  done <<< "$ALERT_CAND"
fi
# 告警 JSON 子对象（--alert 未启用 = null；启用 = {threshold, hit, dns[]}）
ALERT_JSON="null"
if [ -n "$ALERT_N" ]; then
  ALERT_JSON="{\"threshold\": ${ALERT_N}, \"hit\": $([ -n "$ALERT_HITS" ] && echo true || echo false), \"dns\": [${ALERT_JSON_DNS#, }]}"
fi

# ---------- --json 机器可读输出（stdout 独占；人类文本已在 fd 切换时转 stderr） ----------
# 置于告警判定之后：JSON 内含告警命中结果；exit 3 前也能先吐完 JSON
if [ "$GEN_JSON" = "1" ]; then
  _gen_at=$(date '+%Y-%m-%d %H:%M:%S %z')
  {
    echo "{"
    echo "  \"tool\": \"dns-test/trends.sh\","
    echo "  \"version\": \"${VERSION}\","
    echo "  \"generated_at\": \"${_gen_at}\","
    echo "  \"files\": ${N_FILES},"
    echo "  \"period\": {\"from\": \"${T0_TS}\", \"to\": \"${T1_TS}\"},"
    echo "  \"freshness\": \"$(json_escape "${FRESHNESS:-}")\","
    echo "  \"modes\": \"${MODE_SEEN# }\","  # 去前导空格（扫描期拼接产物）
    echo "  \"week_window_days\": ${WEEK_N},"
    echo "  \"dns\": ["
    printf '%s\n' "$(printf '%s,\n' "${JSON_DNS[@]}" | sed '$ s/,$//')"
    echo "  ],"
    echo "  \"alert\": ${ALERT_JSON}"
    echo "}"
  } >&3
fi

# ---------- --export：一键报障/迁移包（数据JSON + 本次报告 + doctor 自检输出 → trends/export/） ----------
# 与 --archive 的区别：archive 只包数据 JSON；export 是"数据+报告+环境自检"三合一报障包
# 置于告警判定之前：--alert 命中 exit 3 前报障包也已产出（报障场景往往正是告警时）
if [ "$EXPORT" = "1" ]; then
  EXP_STAGE=$(mktemp -d 2>/dev/null)
  if [ -z "$EXP_STAGE" ]; then
    echo "  ⚠️  --export: mktemp 失败（临时目录不可写？），跳过打包"
  else
    mkdir -p "$EXP_STAGE/results" "$EXP_STAGE/trends"
    # 时间窗过滤（--since/--until 复用主流程变量）：按文件名内嵌日期段 compare-YYYYMMDD- 比较
    EXP_SINCE="${SINCE//-/}"; EXP_UNTIL="${UNTIL//-/}"
    EXP_N=0; EXP_SKIP=0
    for _f in "$SRC_DIR"/compare-*.json; do
      [ -e "$_f" ] || continue
      if [ -n "$EXP_SINCE" ] || [ -n "$EXP_UNTIL" ]; then
        EXP_D=$(basename "$_f" | sed 's/^compare-\([0-9]\{8\}\)-.*/\1/')
        case "$EXP_D" in
          [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
          *) EXP_D="" ;;  # 文件名异常（非标准命名）不过滤，保留
        esac
        if [ -n "$EXP_D" ]; then
          if [ -n "$EXP_SINCE" ] && [ "$EXP_D" -lt "$EXP_SINCE" ] 2>/dev/null; then EXP_SKIP=$((EXP_SKIP+1)); continue; fi
          if [ -n "$EXP_UNTIL" ] && [ "$EXP_D" -gt "$EXP_UNTIL" ] 2>/dev/null; then EXP_SKIP=$((EXP_SKIP+1)); continue; fi
        fi
      fi
      cp "$_f" "$EXP_STAGE/results/" 2>/dev/null && EXP_N=$((EXP_N+1))
    done
    [ "$EXP_SKIP" -gt 0 ] && echo "  ℹ️  --export: ${EXP_SKIP} 份在 --since/--until 窗口外，未打包"
    EXP_R=0
    for _r in report.html report.md trends.csv; do
      [ -f "$OUT_DIR/$_r" ] && { cp "$OUT_DIR/$_r" "$EXP_STAGE/trends/" 2>/dev/null; EXP_R=$((EXP_R+1)); }
    done
    EXP_D=0
    if [ -f "$SCRIPT_DIR/doctor.sh" ]; then
      ( cd "$SCRIPT_DIR" && bash doctor.sh ) > "$EXP_STAGE/doctor.txt" 2>&1
      EXP_D=1
    fi
    mkdir -p "$OUT_DIR/export"
    EXP_TAR="$OUT_DIR/export/dns-test-export-$(date '+%Y%m%d-%H%M%S').tar.gz"
    if tar -czf "$EXP_TAR" -C "$EXP_STAGE" . 2>/dev/null; then
      echo "  📦 --export: 报障包已生成 → $EXP_TAR"
      echo "     内含: results/ ${EXP_N}份JSON + trends/ ${EXP_R}份报告${EXP_D:+ + doctor.txt（环境自检）}"
      echo "     报障: 整包附到 issue（含 doctor.txt 环境信息，维护者可快速定位）"
      echo '     迁移: 解包到新机仓库根即可续用历史（tar -xzf <上面这个包> -C /path/to/dns-test）'
    else
      echo "  ⚠️  --export: tar 打包失败（磁盘满？），已跳过"
    fi
    rm -rf "$EXP_STAGE"
  fi
fi

# 告警文本输出 + webhook 推送（不改变 exit 3 语义；推送失败仅提示）
if [ -n "$ALERT_N" ]; then
  if [ -n "$ALERT_HITS" ]; then
    echo ""
    echo "  ━━━ 🚨 告警（--alert ${ALERT_N}）━━━"
    printf '%s' "$ALERT_HITS"
    if [ -n "$WEBHOOK_URL" ]; then
      webhook_push "$WEBHOOK_URL" \
        "🚨 dns-test 告警：评分阈值 ${ALERT_N} 命中（${VERSION}）" \
        "期间: ${T0_TS} ~ ${T1_TS}${FRESHNESS:+（最新采集 ${FRESHNESS}）}
${ALERT_HITS}处置: 检查网络/换DNS后跑 bash trends.sh 复核"
    fi
    exit 3
  fi
  echo ""
  echo "  ✅ --alert ${ALERT_N}: 全部 DNS 评分均值达标"
fi

exit 0
