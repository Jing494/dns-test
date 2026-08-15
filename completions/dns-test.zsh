#compdef compare.sh trends.sh doctor.sh dns-test.sh lite.sh full.sh
# ============================================================================
# dns-test zsh 补全：compare.sh / trends.sh / doctor.sh / dns-test.sh / lite.sh / full.sh
# 启用（方式1）: cp completions/dns-test.zsh ~/.zfunc/_dns-test && echo 'fpath=(~/.zfunc $fpath); autoload -Uz compinit && compinit' >> ~/.zshrc
# 启用（方式2）: source completions/dns-test.zsh && compdef _dns-test compare.sh trends.sh doctor.sh
# 效果: ./compare.sh <TAB> → flags + 预设组(default/ali/tencent/all) + 常用公共DNS
# ============================================================================
_dns-test() {
  local script cur
  script=${words[1]##*/}
  cur=${words[CURRENT]}
  # 成对取值参数：光标在其值位，不补 flag
  if [[ ${words[CURRENT-1]} == (--watch|--rounds|--keep|--limit|--since|--until|--alert|--prune|--vs|--week|--webhook|--archive-keep) ]]; then
    return 0
  fi
  local -a dns_words
  dns_words=(223.5.5.5 119.29.29.29 180.76.76.76 114.114.114.114 1.1.1.1 8.8.8.8)
  case "$script" in
    compare.sh)
      _values 'option/预设/DNS' \
        --html --md --open --full --no-save --json --watch --rounds --keep --version --help \
        default ali tencent all "${dns_words[@]}" ;;
    trends.sh)
      _values 'option/DNS' \
        --html --open --md --json --csv --vs --cron --detail --limit --since --until --prune --archive --archive-keep --export --alert --webhook --week --version --help \
        "${dns_words[@]}" ;;
    doctor.sh)
      _values 'option' --net --cron --fix --help ;;
    dns-test.sh|lite.sh|full.sh)
      _values 'DNS' "${dns_words[@]}" ;;
    *) ;;
  esac
  return 0
}
