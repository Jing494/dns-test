#!/bin/bash
# ============================================================================
# DoH/DoT 支持检测（环境自适应）
# 功能: 检测DNS服务器是否提供 DoH / DoT 加密解析
# 用法: bash doh_dot_check.sh [DNS1[,DNS2...]]    默认223.5.5.5
# 方法（自动选最优）:
#   DoT: dig +tls=dot 实测（v4/v6 均可）
#   DoH: 有 curl → curl --doh-url 实测；无 curl → 443 端口级探测
# 注意: 实测失败可能因未提供/网络不通/路径不同，非绝对结论
# ============================================================================
DNS_LIST="${1:-223.5.5.5}"

# 环境能力：是否有 curl
HAS_CURL=0
command -v curl >/dev/null 2>&1 && HAS_CURL=1

IFS=',' read -ra DNS_ARR <<< "$DNS_LIST"
for DNS in "${DNS_ARR[@]}"; do
  DNS="$(echo "$DNS" | tr -d ' ')"
  # 合法地址校验（v4/v6）
  if [[ "$DNS" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || [[ "$DNS" =~ ^[0-9a-fA-F:]+$ && "$DNS" == *":"* ]]; then
    echo "════ DoH/DoT 检测: $DNS ════"
    # ===== DoT: dig +tls 实测 =====
    if timeout 6 dig +tls=dot @$DNS www.baidu.com A +short +time=3 +tries=1 2>/dev/null | grep -qE "\."; then
      echo "  DoT: ✅ dig +tls=dot 实测成功（提供DoT）"
    else
      echo "  DoT: ⚠️ dig +tls 失败（未提供DoT / 网络不通）"
    fi
    # ===== DoH: curl 实测或端口级 =====
    if [ "$HAS_CURL" = "1" ]; then
      # IPv6 地址需要方括号
      local_url="$DNS"
      [[ "$DNS" == *":"* ]] && local_url="[$DNS]"
      code=$(timeout 8 curl -s --doh-url "https://$local_url/dns-query" -o /dev/null -w "%{http_code}" https://www.baidu.com 2>/dev/null)
      if [ "$code" = "200" ]; then
        echo "  DoH: ✅ curl --doh-url 实测成功（提供DoH）"
      else
        echo "  DoH: ⚠️ curl DoH 失败（未提供/路径不同/网络不通，code=$code）"
      fi
    else
      port_hit=$({ timeout 3 bash -c "echo > /dev/tcp/$DNS/443" 2>/dev/null; } && echo 1 || echo 0)
      if [ "$port_hit" = "1" ]; then
        echo "  DoH: ✅ 443端口开放（无curl，仅端口级探测）"
      else
        echo "  DoH: ⚠️ 443端口不可达"
      fi
    fi
  else
    echo "❌ 非法DNS地址: $DNS"
  fi
  echo ""
done
echo "⚠️  实测结果受网络环境影响（代理/防火墙可能干扰）；端口级结果仅供参考。"
