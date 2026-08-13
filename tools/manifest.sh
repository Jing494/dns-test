#!/bin/bash
# ============================================================================
# 专项插件注册表（集中声明，供 lib/plugins.sh 加载）
# 新增专项 = 在 PLUGIN_ITEMS 加一行 + 补一个 PLUGIN_DIR_<id> 映射即可，
#            菜单（dns-test.sh）自动出现该专项，无需改主脚本
# 字段（| 分隔）: 插件id | 脚本 | 菜单名称 | 执行器(perl/bash) | 引导提示(空=无)
# 引导提示: 非空则执行前 read -t 30 一次，输入值作为脚本首个参数（可空）
# 注意: 脚本路径统一从项目根拼接（dir/script），与命令行直跑完全一致，
#       不 cd 进插件目录，避免脚本内部相对路径失效
# ============================================================================

PLUGIN_ITEMS=(
  "vowifi|01_resolve_vowifi.pl|VoWiFi域名全解析测试|perl|"
  "vowifi|02_vowifi_verify.pl|VoWiFi多DNS交叉验证|perl|"
  "vowifi|03_test_router_dns.pl|路由器DNS转发测试|perl|路由器网关IP(逗号分隔，回车默认192.168.1.1,192.168.2.1)"
  "vowifi|carrier_epdg.pl|运营商ePDG部署检测|perl|"
  "network|01_port_test.pl|端口连通性测试|perl|目标IP 端口 协议(如 223.5.5.5 53 udp)"
  "network|doh_dot_check.sh|DoH/DoT支持检测|bash|检测DNS(逗号分隔，回车用当前组)"
  "examples|01_dns_query.pl|基础DNS查询|perl|"
  "examples|02_multi_dns_compare.pl|多DNS对比测试|perl|"
  "examples|03_dns64_check.pl|DNS64支持检测|perl|"
  "examples|04_reverse_dns.pl|反向DNS解析|perl|"
)

# 插件目录映射（id -> 相对项目根路径）
PLUGIN_DIR_vowifi="tools/vowifi"
PLUGIN_DIR_network="tools/network"
PLUGIN_DIR_examples="examples"
