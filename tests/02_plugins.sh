#!/bin/bash
# ============================================================================
# 纯 bash 轻量断言单测（无依赖，等价 perl 单测的 bash 版）
# 测 lib/plugins.sh 的注册表解析 / 参数策略 / 拦截逻辑
# 用法: bash tests/02_plugins.sh    （退出码 0=全过 1=有失败）
# 说明: bats 评估结论(2026-08-13)为不引入——纯函数用零依赖轻量断言即可
# ============================================================================
cd "$(dirname "$0")/.." || exit 1
source lib/plugins.sh

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
notok(){ FAIL=$((FAIL+1)); echo "  ❌ $1"; }

echo "═══ plugins.sh 单测 ═══"

# 1. 注册表可加载且 ≥10 项
if [ ${#PLUGIN_ITEMS[@]} -ge 10 ]; then ok "注册表≥10项(${#PLUGIN_ITEMS[@]})"; else notok "注册表≥10项"; fi

# 2. _plugin_split 5 字段（第6字段缺省 → P_FWD=1）
_plugin_split "vowifi|01_resolve_vowifi.pl|VoWiFi域名全解析测试|perl|"
if [ "$P_ID" = "vowifi" ] && [ "$P_SCRIPT" = "01_resolve_vowifi.pl" ] && [ "$P_NAME" = "VoWiFi域名全解析测试" ] && [ "$P_EXEC" = "perl" ] && [ "$P_FWD" = "1" ]; then
  ok "split5字段默认FWD=1"
else
  notok "split5字段默认FWD=1 (ID=$P_ID SCRIPT=$P_SCRIPT EXEC=$P_EXEC FWD=$P_FWD)"
fi

# 3. _plugin_split 6 字段 FWD=0
_plugin_split "network|01_port_test.pl|端口连通性测试|perl|目标IP|0"
if [ "$P_FWD" = "0" ]; then ok "split6字段FWD=0"; else notok "split6字段FWD=0 (FWD=$P_FWD)"; fi

# 4. _plugin_split 6 字段 FWD=1
_plugin_split "x|y.pl|测试|perl||1"
if [ "$P_FWD" = "1" ]; then ok "split6字段FWD=1"; else notok "split6字段FWD=1 (FWD=$P_FWD)"; fi

# 5. plugin_list 输出格式（编号. 名称）
if plugin_list | head -1 | grep -qE "^[0-9]+\. "; then ok "plugin_list格式"; else notok "plugin_list格式"; fi

# 6. plugin_run 无效编号 → 退出码非0
if plugin_run 999 >/dev/null 2>&1; then notok "无效编号拦截"; else ok "无效编号拦截"; fi

# 7. plugin_run 未知执行器 → 退出码非0（子shell设数组+屏蔽manifest）
if bash -c 'PLUGIN_MANIFEST=/dev/null; PLUGIN_ITEMS=("x|dns-test.sh|测试|python|"); PLUGIN_DIR_x="."; source lib/plugins.sh && plugin_run 1' >/dev/null 2>&1; then
  notok "未知执行器拦截"
else
  ok "未知执行器拦截"
fi

# 8. plugin_run 脚本缺失 → 退出码非0
if bash -c 'PLUGIN_MANIFEST=/dev/null; PLUGIN_ITEMS=("x|not_exist.pl|测试|perl|"); PLUGIN_DIR_x="."; source lib/plugins.sh && plugin_run 1' >/dev/null 2>&1; then
  notok "脚本缺失检测"
else
  ok "脚本缺失检测"
fi

# 9. 全部插件脚本文件存在（防 manifest 手滑）
OK=1
for item in "${PLUGIN_ITEMS[@]}"; do
  P_ID="${item%%|*}"; rest="${item#*|}"
  P_SCRIPT="${rest%%|*}"
  dir="PLUGIN_DIR_$P_ID"; dir="${!dir}"
  [ -f "${dir}/${P_SCRIPT}" ] || { OK=0; echo "  ❌ 缺失: ${dir}/${P_SCRIPT}"; }
done
if [ "$OK" = "1" ]; then ok "全部插件脚本存在"; else notok "全部插件脚本存在"; fi

echo ""
echo "════ 结果: $PASS 通过 / $FAIL 失败 ════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
