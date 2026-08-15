#!/bin/bash
# ============================================================================
# dns-test 自检（doctor）：依赖/平台兼容/目录/数据健康 一键体检
# 适用: 环境初始化后验证、跑不起来先自诊、报障时贴输出给 issue
# 用法: bash doctor.sh [--net] [--fix] [--cron]
#   --net   追加真实网络连通检查（dig 223.5.5.5；离线环境不加此参数则跳过该节）
#   --fix   体检后自动修复可自愈项（建缺失目录/隔离损坏JSON到 results/quarantine/，不动正常数据）
#   --cron  不跑体检，直接打印值守 crontab 模板（采集/告警/归档三件套，改路径即可粘贴）
# 退出码: 0=全部通过  1=存在 FAIL（WARN 不影响退出码）
# 注意: 本脚本【不】source lib/core.sh —— core.sh 缺 dig/perl 会直接 exit 1，
#       而那正是 doctor 需要诊断并报告的场景；只 source 纯函数的 compat.sh 与纯变量的 version.sh
# ============================================================================
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 1
cd "$SCRIPT_DIR" || exit 1
source lib/compat.sh
source lib/version.sh

NET_MODE=0
FIX_MODE=0
for _a in "$@"; do
  case "$_a" in
    --net) NET_MODE=1 ;;
    --fix) FIX_MODE=1 ;;
    --cron)
      # 值守模板：路径取当前仓库绝对路径，DNS/阈值/webhook 按需改后粘贴进 crontab -e
      echo "# ===== dns-test 值守 crontab 模板（${PROJECT_VERSION} / ${PROJECT_RELEASE}）====="
      echo "# 用法: 按需修改 DNS 列表/阈值/webhook 后，crontab -e 粘贴保存；日志在 trends/ 下"
      echo "# 注: cron 的 PATH 极简，首行显式指定是头号避坑项；macOS 亦可用 crontab（launchd 等价）"
      echo "PATH=/usr/local/bin:/usr/bin:/bin"
      echo ""
      echo "# 1) 每 30 分钟采集一轮并聚合（保留最近 200 份，清理前先归档到 trends/archive/，归档只留最近 20 个）"
      echo "*/30 * * * * cd ${SCRIPT_DIR} && bash trends.sh --cron 223.5.5.5 119.29.29.29 --prune 200 --archive --archive-keep 20 >> trends/cron.log 2>&1"
      echo ""
      echo "# 2) 每天 09:00 值守告警（任一 DNS 评分均值<70 或全不可达 → 推飞书并 exit 3）"
      echo "0 9 * * * cd ${SCRIPT_DIR} && bash trends.sh --alert 70 --webhook https://open.feishu.cn/open-apis/bot/v2/hook/xxx >> trends/alert.log 2>&1"
      echo ""
      echo "# 3) 每周日 03:00 全量归档（备份/迁移/报障分享，不删文件；配 --archive-keep 20 防堆积）"
      echo "0 3 * * 0 cd ${SCRIPT_DIR} && bash trends.sh --archive --archive-keep 20 >> trends/cron.log 2>&1"
      echo ""
      if command -v crontab >/dev/null 2>&1; then
        echo "# 安装: crontab -e 粘贴上方内容（不含本行及 # 注释行亦可）"
      else
        echo "# ⚠️ 当前环境无 crontab 命令 — macOS/Linux 一般自带；容器环境建议改用调度器定时拉起"
      fi
      exit 0 ;;
    -h|--help)
      echo "用法: bash doctor.sh [--net] [--fix] [--cron]"
      echo "  --net  追加真实网络连通检查（dig @223.5.5.5；离线环境省略则跳过该节）"
      echo "  --fix  体检后自动修复可自愈项（建缺失目录/隔离损坏JSON，不动正常数据）"
      echo "  --cron 打印值守 crontab 模板（采集+告警+归档三件套，不执行体检）"
      echo "退出码: 0=全部通过 1=存在 FAIL"
      exit 0 ;;
    "") ;;
    *) echo "❌ 未知参数: $_a（仅支持 --net / --fix / --cron）"; exit 1 ;;
  esac
done

PASS_N=0; WARN_N=0; FAIL_N=0
ok()    { PASS_N=$((PASS_N+1)); echo "  ✅ $1"; }
warn()  { WARN_N=$((WARN_N+1)); echo "  ⚠️  $1"; }
fail()  { FAIL_N=$((FAIL_N+1)); echo "  ❌ $1"; }

echo "━━━━━━━━ dns-test doctor 自检（${PROJECT_VERSION} / ${PROJECT_RELEASE}）━━━━━━━━"

# ---------- 1. 平台与 shell ----------
echo ""
echo "  ━━━ 平台与 shell ━━━"
OS=$(uname -s); OS_R=$(uname -r)
case "$OS" in
  Darwin) ok "macOS ($OS_R) — BSD 工具链，compat 层按 BSD 语法兜底" ;;
  Linux)  ok "Linux ($OS_R)" ;;
  MINGW*|MSYS*|CYGWIN*) warn "Windows/WSL 环境 ($OS) — 部分 emoji/颜色显示可能异常，功能不受影响" ;;
  *) warn "非常规平台: $OS $OS_R — 未专门测试，遇问题提 issue 附本输出" ;;
esac
BV=${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}
if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
  ok "bash $BV（≥4，全特性可用）"
elif [ "${BASH_VERSINFO[0]}" -eq 3 ] && [ "${BASH_VERSINFO[1]}" -ge 2 ]; then
  ok "bash $BV（≥3.2，项目最低要求满足；关联数组等 4+ 特性未用）"
else
  fail "bash $BV 过旧（需 ≥3.2，macOS 2004 后自带版本即满足）"
fi

# ---------- 2. 依赖 ----------
echo ""
echo "  ━━━ 依赖（必需项缺一不可，可选项缺了只降级对应功能） ━━━"
for c in dig ping awk sed grep cut sort head tail; do
  if command -v "$c" >/dev/null 2>&1; then ok "必需: $c ($(command -v "$c"))"
  else fail "必需: $c 未找到（dig=dnsutils/bind-utils；ping=iputils-ping/inetutils）"; fi
done
command -v curl    >/dev/null 2>&1 && ok "可选: curl（webhook 推送 / DoH 实测可用）"    || warn "可选: curl 未找到 — trends --webhook 与 DoH 实测将跳过"
command -v perl    >/dev/null 2>&1 && ok "可选: perl（专项测试可用）"                    || warn "可选: perl 未找到 — 专项测试(tests/01)将跳过"
command -v python3 >/dev/null 2>&1 && ok "可选: python3（仅辅助，无功能依赖）"           || echo "  ℹ️  python3 未安装（本项目不依赖，无影响）"

# ---------- 3. 平台兼容层 ----------
echo ""
echo "  ━━━ 平台兼容层（compat.sh 时间运算 / timeout） ━━━"
if command -v timeout >/dev/null 2>&1; then
  ok "timeout 命令原生可用"
else
  ok "timeout 由 compat.sh 兜底实现（macOS 默认无该命令，属正常兜底）"
fi
_t=$(date_plus_minutes 5)
case "$_t" in
  [0-2][0-9]:[0-5][0-9]) ok "date_plus_minutes 正常（当前+5min = $_t）" ;;
  *) fail "date_plus_minutes 输出异常: [$_t]（date 命令受损？ETA/新鲜度将缺失）" ;;
esac
_e=$(ts_to_epoch "2026-01-01 00:00")
case "$_e" in
  ''|*[!0-9]*) fail "ts_to_epoch 输出异常: [$_e]（数据新鲜度显示将缺失）" ;;
  *) ok "ts_to_epoch 正常（2026-01-01 00:00 → epoch $_e）" ;;
esac
_d=$(date_days_ago 7)
case "$_d" in
  20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ok "date_days_ago 正常（7天前 = $_d，周对比可用）" ;;
  *) fail "date_days_ago 输出异常: [$_d]（周对比小节将隐藏）" ;;
esac

# ---------- 4. 工作目录 ----------
echo ""
echo "  ━━━ 工作目录可写（results/ 落采集数据，trends/ 落报告） ━━━"
for d in results trends; do
  if mkdir -p "$d" 2>/dev/null && touch "$d/.doctor-write-test" 2>/dev/null; then
    ok "$d/ 可写（$(cd "$d" && pwd)）"
    rm -f "$d/.doctor-write-test"
  else
    fail "$d/ 不可写 — 检查目录权限（采集/报告将失败）"
  fi
done

# ---------- 5. 数据健康（有数据才查） ----------
echo ""
echo "  ━━━ 数据健康（results/compare-*.json） ━━━"
if ls results/compare-*.json >/dev/null 2>&1; then
  N_JSON=$(ls results/compare-*.json 2>/dev/null | wc -l | tr -d ' ')
  LATEST=$(ls results/compare-*.json 2>/dev/null | sort | tail -1)
  ok "已积累 $N_JSON 份采集数据（最新: $(basename "$LATEST")）"
  if [ "$N_JSON" -lt 2 ]; then
    warn "仅 1 份数据 — trends 趋势/环比需要 ≥2 份，继续采集: bash compare.sh 223.5.5.5 --watch 30"
  fi
  BAD_N=0
  for f in results/compare-*.json; do
    grep -q '"timestamp"' "$f" 2>/dev/null || BAD_N=$((BAD_N+1))
  done
  if [ "$BAD_N" -gt 0 ]; then
    warn "$BAD_N 份 JSON 缺 timestamp 字段（trends 聚合会自动跳过；可清理避免干扰）"
  else
    ok "全部 JSON 含 timestamp 字段"
  fi
  if grep -l '"mode": *"lite"' results/compare-*.json >/dev/null 2>&1 && \
     grep -l '"mode": *"full"' results/compare-*.json >/dev/null 2>&1; then
    warn "lite 与 full 模式混采 — 评分口径不同，trends 会提示；建议 --since 分段分析"
  fi
else
  warn "results/ 暂无采集数据 — 先跑一次: bash compare.sh 223.5.5.5 119.29.29.29"
fi

# ---------- 6. 网络连通（--net 才测真实网络） ----------
if [ "$NET_MODE" = "1" ]; then
  echo ""
  echo "  ━━━ 网络连通（--net 实测，离线环境勿用） ━━━"
  _r=$(dig @223.5.5.5 example.com +short +time=3 +tries=1 2>/dev/null | head -1)
  if [ -n "$_r" ]; then
    ok "dig @223.5.5.5 example.com → $_r（UDP 53 出网正常）"
  else
    fail "dig @223.5.5.5 无响应 — 检查防火墙/UDP 53 出网，或换 119.29.29.29 重试"
  fi
fi

# ---------- 7. 自动修复（--fix 才执行；只做无损自愈，不动正常数据） ----------
if [ "$FIX_MODE" = "1" ]; then
  echo ""
  echo "  ━━━ 自动修复（--fix：建缺失目录 / 隔离损坏 JSON） ━━━"
  FIXED_N=0
  # ① 建缺失的工作目录（含归档/报障/隔离子目录）
  for d in results trends trends/archive trends/export results/quarantine; do
    if [ ! -d "$d" ]; then
      if mkdir -p "$d" 2>/dev/null; then
        echo "  🔧 已创建 $d/"; FIXED_N=$((FIXED_N+1))
      else
        echo "  ❌ 无法创建 $d/（权限不足，请手动: mkdir -p $d）"
      fi
    fi
  done
  # ② 损坏 JSON（缺 timestamp）移入 results/quarantine/ 隔离（不删，可回溯/人工复核）
  if ls results/compare-*.json >/dev/null 2>&1; then
    QMOVED=0
    for f in results/compare-*.json; do
      grep -q '"timestamp"' "$f" 2>/dev/null || {
        mkdir -p results/quarantine
        if mv "$f" "results/quarantine/" 2>/dev/null; then
          echo "  🔧 已隔离损坏文件: $(basename "$f") → results/quarantine/"
          QMOVED=$((QMOVED+1)); FIXED_N=$((FIXED_N+1))
        else
          echo "  ❌ 隔离失败: $f（权限不足？）"
        fi
      }
    done
    [ "$QMOVED" -gt 0 ] && echo "     （隔离文件未删除，确认无用后可 rm results/quarantine/* 清空）"
  fi
  [ "$FIXED_N" -eq 0 ] && echo "  ✅ 无可自愈项（目录齐全、JSON 完好）" \
                       || echo "  共修复 ${FIXED_N} 项 — 建议重跑 bash doctor.sh 复核"
fi

# ---------- 汇总 ----------
echo ""
echo "━━━━━━━━ 自检结果: ✅${PASS_N} 通过  ⚠️${WARN_N} 警告  ❌${FAIL_N} 失败 ━━━━━━"
if [ "$FAIL_N" -gt 0 ]; then
  echo "  存在失败项：按上方 ❌ 提示修复后重跑；仍异常请携带本输出提 issue"
  exit 1
fi
[ "$WARN_N" -gt 0 ] && echo "  警告项不阻断使用，按需处理即可"
exit 0
