#!/bin/bash
# ============================================================================
# dns-test bash 补全：compare.sh / trends.sh / doctor.sh / dns-test.sh / lite.sh / full.sh
# 启用（临时）: source completions/dns-test.bash
# 启用（持久）: echo 'source /path/to/dns-test/completions/dns-test.bash' >> ~/.bashrc
# 效果: ./compare.sh <TAB> → flags + 预设组(default/ali/tencent/all) + 常用公共DNS
# ============================================================================
_dns_test_complete() {
  local cur prev script flags dns_words presets
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  script="${COMP_WORDS[0]}"
  # 成对取值参数：光标在其值位，不再补 flag
  case "$prev" in
    --watch|--rounds|--keep|--limit|--since|--until|--alert|--prune|--vs|--week|--webhook)
      return 0 ;;
  esac
  # 常用公共DNS（仅提示词，任意合法IPv4/IPv6均可手输）
  dns_words="223.5.5.5 119.29.29.29 180.76.76.76 114.114.114.114 1.1.1.1 8.8.8.8"
  case "$script" in
    compare.sh)
      presets="default ali tencent all"
      flags="--html --md --open --full --no-save --json --watch --rounds --keep --version --help"
      COMPREPLY=( $(compgen -W "$flags $presets $dns_words" -- "$cur") ) ;;
    trends.sh)
      flags="--html --open --md --json --csv --vs --cron --detail --limit --since --until --prune --archive --alert --webhook --week --version --help"
      COMPREPLY=( $(compgen -W "$flags $dns_words" -- "$cur") ) ;;
    doctor.sh)
      COMPREPLY=( $(compgen -W "--net --cron --help" -- "$cur") ) ;;
    dns-test.sh|lite.sh|full.sh)
      # 入口/极简脚本只吃 DNS 地址
      COMPREPLY=( $(compgen -W "$dns_words" -- "$cur") ) ;;
  esac
  return 0
}
complete -F _dns_test_complete compare.sh trends.sh doctor.sh dns-test.sh lite.sh full.sh
