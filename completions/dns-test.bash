#!/bin/bash
# ============================================================================
# dns-test bash 补全：覆盖全部 11 个入口脚本
#   compare.sh  trends.sh   dns-test.sh  doctor.sh  lite.sh      full.sh
#   dns-preset.sh  install.sh  verify.sh  release.sh  smoke_test.sh
# 启用（临时）: source completions/dns-test.bash
# 启用（持久）: echo 'source /path/to/dns-test/completions/dns-test.bash' >> ~/.bashrc
# 效果: ./compare.sh <TAB> → flags + 预设组(default/ali/tencent/all) + 常用公共DNS
# 维护: 新增入口脚本 = 下方 case 加一个分支 + 末尾 complete 行补脚本名；
#       新增选项只需改对应的 *_flags 变量（各脚本 flag 集集中定义，避免多处漂移）
# ============================================================================
_dns_test_complete() {
  local cur prev script cmp_flags trd_flags ver_flags dns_words presets
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  # 去掉目录前缀，兼容 ./compare.sh 这类带路径调用（原实现直接取 COMP_WORDS[0]，
  # 带路径时匹配不上 case 分支，补全静默失效）
  script="${COMP_WORDS[0]##*/}"

  # 成对取值参数：光标在其值位，不再补 flag
  case "$prev" in
    --watch|--rounds|--keep|--limit|--since|--until|--alert|--prune|--vs|--week|--webhook|--archive-keep)
      return 0 ;;
  esac

  # 常用公共DNS（仅提示词，任意合法IPv4/IPv6均可手输）
  dns_words="223.5.5.5 119.29.29.29 180.76.76.76 114.114.114.114 1.1.1.1 8.8.8.8"
  presets="default ali tencent all"

  # 各专项脚本的 flag 集（集中定义；dns-test.sh 的并集直接复用，避免三处各写一份）
  cmp_flags="--html --md --json --open --full --no-save --watch --rounds --keep --version --help"
  trd_flags="--html --open --md --json --csv --vs --cron --detail --limit --since --until --prune --archive --archive-keep --export --alert --webhook --week --version --help"
  ver_flags="--strict --version --help"

  case "$script" in
    compare.sh)
      COMPREPLY=( $(compgen -W "$cmp_flags $presets $dns_words" -- "$cur") ) ;;
    trends.sh)
      COMPREPLY=( $(compgen -W "$trd_flags $dns_words" -- "$cur") ) ;;
    dns-test.sh)
      # 统一入口：预设/DNS + 可透传给专项的选项并集
      COMPREPLY=( $(compgen -W "$cmp_flags $trd_flags $ver_flags $presets $dns_words" -- "$cur") ) ;;
    doctor.sh)
      COMPREPLY=( $(compgen -W "--net --cron --fix --version --help" -- "$cur") ) ;;
    dns-preset.sh)
      # 位置参数：预设组 → lite|full → 索引
      COMPREPLY=( $(compgen -W "$presets lite full --version --help" -- "$cur") ) ;;
    install.sh)
      COMPREPLY=( $(compgen -W "--smoke --all --completions --version --help" -- "$cur") ) ;;
    verify.sh)
      COMPREPLY=( $(compgen -W "$ver_flags" -- "$cur") ) ;;
    release.sh)
      COMPREPLY=( $(compgen -W "--version --help" -- "$cur") ) ;;
    lite.sh|full.sh)
      # 基础测试：DNS 地址 + 自身的 --help/--version
      COMPREPLY=( $(compgen -W "$dns_words --version --help" -- "$cur") ) ;;
    smoke_test.sh)
      # 无参数脚本：不补任何词
      COMPREPLY=() ;;
  esac
  return 0
}
complete -F _dns_test_complete compare.sh trends.sh doctor.sh dns-test.sh lite.sh full.sh \
  dns-preset.sh install.sh verify.sh release.sh smoke_test.sh
