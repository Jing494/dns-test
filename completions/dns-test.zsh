#compdef compare.sh trends.sh doctor.sh dns-test.sh lite.sh full.sh dns-preset.sh install.sh verify.sh release.sh smoke_test.sh
# ============================================================================
# dns-test zsh 补全：覆盖全部 11 个入口脚本（与 completions/dns-test.bash 保持一致）
#   compare.sh  trends.sh   dns-test.sh  doctor.sh  lite.sh      full.sh
#   dns-preset.sh  install.sh  verify.sh  release.sh  smoke_test.sh
# 启用（方式1）: cp completions/dns-test.zsh ~/.zfunc/_dns-test && echo 'fpath=(~/.zfunc $fpath); autoload -Uz compinit && compinit' >> ~/.zshrc
# 启用（方式2）: source completions/dns-test.zsh && compdef _dns-test compare.sh trends.sh doctor.sh
# 效果: ./compare.sh <TAB> → flags + 预设组(default/ali/tencent/all) + 常用公共DNS
# 维护: 与 dns-test.bash 同步增删分支（两文件脚本清单必须一致）
# ============================================================================
_dns-test() {
  local script cur
  script=${words[1]##*/}
  cur=${words[CURRENT]}
  # 成对取值参数：光标在其值位，不补 flag
  if [[ ${words[CURRENT-1]} == (--watch|--rounds|--keep|--limit|--since|--until|--alert|--prune|--vs|--week|--webhook|--archive-keep) ]]; then
    return 0
  fi
  local -a dns_words presets cmp_flags trd_flags ver_flags
  dns_words=(223.5.5.5 119.29.29.29 180.76.76.76 114.114.114.114 1.1.1.1 8.8.8.8)
  presets=(default ali tencent all)
  # 各专项脚本的 flag 集（与 dns-test.bash 的 *_flags 对应）
  cmp_flags=(--html --md --json --open --full --no-save --watch --rounds --keep --version --help)
  trd_flags=(--html --open --md --json --csv --vs --cron --detail --limit --since --until --prune --archive --archive-keep --export --alert --webhook --week --version --help)
  ver_flags=(--strict --version --help)
  case "$script" in
    compare.sh)
      _values 'option/预设/DNS' ${cmp_flags[@]} ${presets[@]} "${dns_words[@]}" ;;
    trends.sh)
      _values 'option/DNS' ${trd_flags[@]} "${dns_words[@]}" ;;
    dns-test.sh)
      _values 'option/预设/DNS' ${cmp_flags[@]} ${trd_flags[@]} ${ver_flags[@]} ${presets[@]} "${dns_words[@]}" ;;
    doctor.sh)
      _values 'option' --net --cron --fix --help ;;
    dns-preset.sh)
      _values '预设/版本' ${presets[@]} lite full --version --help ;;
    install.sh)
      _values 'option' --smoke --all --completions --version --help ;;
    verify.sh)
      _values 'option' ${ver_flags[@]} ;;
    release.sh)
      _values 'option' --version --help ;;
    lite.sh|full.sh)
      _values 'DNS' "${dns_words[@]}" ;;
    *)
      ;;
  esac
  return 0
}
