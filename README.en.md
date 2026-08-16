# DNS / Network Testing Toolkit

> 🌐 **中文**：[README.md](./README.md) ｜ **English**: This document

A unified toolkit for DNS benchmarking and network diagnostics, with a focus on China's telecom networks (Yunnan Telecom DNS as the default baseline, plus Alibaba/Tencent public DNS for comparison).

> 📄 Full documentation is in Chinese: [README.md](./README.md). This English file is a concise overview.

## Features

- **DNS Benchmarking** (lite: 10 items / full: 16 items, ~10s per DNS)
  - A/AAAA records, MX/NS/TXT/CNAME/SOA, stability (20 rounds), NXDOMAIN, ping (IPv4 + IPv6), consistency, carrier domains, DNSSEC, ECS, PTR, TTL, result comparison vs Alibaba DNS (suspected-hijack hint), recursion
- **Carrier ePDG Deployment Detection** — check whether China Telecom / China Mobile / China Unicom / China Broadnet have deployed VoWiFi ePDG (per-province, via your provincial DNS)
- **Plugin Registry** — the special-test menu is driven by `tools/manifest.sh` (loaded by `lib/plugins.sh`); adding a new plugin = one line in the manifest + a directory mapping, it appears in the menu automatically
- **Router DNS Forwarding Test** — verify if your home router forwards DNS to the provincial DNS (custom baseline supported)
- **DoH / DoT Support Check** — adaptive: real test via `dig +tls` / `curl --doh-url` when available, port-level probe otherwise
- **IPv6 support** — v4/v6 dual-stack everywhere, IPv6 connectivity test (ping6)
- **AI Operator Manual** — 12-chapter guide teaching AI agents how to interact with users properly (ask DNS → pick version → guide to specialty tests)
- **DNS Comparison** — `compare.sh` compares multiple DNS side-by-side (score / latency median / stability), preset groups supported (`bash compare.sh ali tencent`), optional responsive HTML / Markdown reports + structured JSON results, period-over-period deltas, per-OS switch commands, current-system-DNS marker (👤), `--watch N` timed collection with `--rounds M` limit, `--keep K` JSON retention, `--json` stdout output, resumable collection (rerun the same command after Ctrl-C to continue from the last round) and auto-refreshing HTML report in watch mode
- **Trend Insight** — `trends.sh` aggregates historical compare results (linear-regression trend arrows, delay P50/P95 percentiles, per-hour worst/best and per-day analysis, provider labels, multi-DNS overlay comparison charts, HTML insights card, CSV export, SVG line charts, optional cron collection, `--prune N` history retention control, `--open` auto-launch browser); `--week N` configurable week-over-week window (2–365 days), `--json` machine-readable output (stdout kept clean for `jq`), `--alert T --webhook URL` watchdog alerting (Feishu / DingTalk / WeCom / Telegram / Bark / generic JSON), `--archive` + `--archive-keep N` tar.gz archiving with rotation, `--export` one-command bug-report bundle (data + report + doctor output, `--since/--until` time-window filter)
- **Environment Doctor** — `doctor.sh` one-command self-check (platform, required/optional deps, macOS–Linux compat layer, writable dirs, data health); `--net` adds connectivity tests, `--fix` auto-repairs healable items (missing dirs, quarantines corrupted JSON), `--cron` prints a ready-to-paste crontab template (collect + alert + weekly archive, with the cron-PATH pitfall pre-solved)
- **Shell Completions** — bash/zsh completions for all entry scripts (`bash install.sh --completions`, idempotent; flags, preset groups and public-DNS addresses)
- **Automated Smoke Test** — `smoke_test.sh` validates all core paths in one run (24 checks)

## Quick Start

```bash
# TL;DR: clone → install → verify
git clone https://github.com/Jing494/dns-test.git && cd dns-test
bash install.sh            # install dig/perl/curl only if missing (add --all to also install optional shellcheck)
bash smoke_test.sh         # 24-item automated validation
bash dns-test.sh           # interactive guided testing
```

```bash
# 1. Get the code
git clone https://github.com/Jing494/dns-test.git
cd dns-test

# 2. Install dependencies (pick your OS)
#   Ubuntu/Debian/WSL: sudo apt install dnsutils curl
#   CentOS/RHEL:       sudo yum install bind-utils curl
#   macOS:             brew install bind curl

# 3. Verify (5 minutes)
bash verify.sh             # one-command full self-check (syntax/unit/smoke/compare/trends; --help for usage)
bash verify.sh --strict    # strict mode: missing shellcheck (optional dep) counts as FAIL
bash smoke_test.sh         # automated 24-item validation
bash lite.sh 223.5.5.5 0   # benchmark a DNS
```

## Usage Examples

```bash
bash lite.sh                      # default: Yunnan Telecom DNS (lite)
bash full.sh 8.8.8.8 0            # full test, single DNS (index param to avoid timeout)
bash dns-preset.sh ali lite 0     # Alibaba DNS preset
bash compare.sh ali tencent                   # compare preset groups (default/ali/tencent/all, mixable with IPs)
bash compare.sh 223.5.5.5 119.29.29.29 --html  # DNS comparison + HTML report (+ --md for Markdown)
bash compare.sh 223.5.5.5 119.29.29.29 --full   # full-mode comparison (77~78 checks/DNS)
bash compare.sh 223.5.5.5 119.29.29.29 --watch 30  # collect every 30 min (Ctrl-C to stop; feeds trends)
bash compare.sh 223.5.5.5 --watch 30 --rounds 12   # auto-stop after 12 rounds (--keep 200 caps JSON files)
#   resumable: rerun the same --watch command after Ctrl-C to continue from the last round
#   watch mode HTML report auto-refreshes at the collection interval
bash compare.sh 223.5.5.5 119.29.29.29 --json      # also print JSON to stdout (pipe-friendly)
bash trends.sh --html --csv       # trend insight (needs accumulated compare data)
bash trends.sh --html --open      # generate HTML and auto-open in browser (implies --html)
bash trends.sh --prune 200        # keep only the latest 200 JSON snapshots, then aggregate
bash trends.sh --prune 200 --archive --archive-keep 20   # archive pruned JSON to tar.gz before deletion, keep last 20 archives
bash trends.sh --week 14          # week-over-week window = 14 days (default 7, range 2-365)
bash trends.sh --json | jq '.dns[0].score_trend'   # machine-readable output (human text goes to stderr)
bash trends.sh --alert 70 --webhook "$WEBHOOK_URL" # exit 3 + push alert if avg score < 70 or all unreachable
#   webhook auto-detected: Feishu / DingTalk / WeCom / Telegram / Bark / generic JSON (via curl)
bash trends.sh --export --since 2026-08-01         # bug-report bundle: data JSON + report + doctor output in one tar.gz
bash doctor.sh                    # environment self-check (--net: connectivity; --fix: auto-repair; --cron: crontab template)
bash install.sh --completions     # install bash/zsh shell completions (idempotent)
perl tools/vowifi/carrier_epdg.pl all   # carrier ePDG deployment check
perl tools/vowifi/03_test_router_dns.pl 192.168.1.1   # router forwarding check
bash tools/network/doh_dot_check.sh 223.5.5.5          # DoH/DoT check
perl examples/01_dns_query.pl --help     # print usage (all examples support --help)
```

## Environment Notes

- The scripts auto-detect the environment (`🌐 环境: Linux/macOS | dig✅... | IPv6:可用`), so results can be interpreted correctly (sandbox vs real machine).
- The repository is path-agnostic: scripts use relative paths (`BASH_SOURCE`), so it runs from any directory.
- Placeholder IPs (192.0.2.x, RFC 5737) are used for operator infrastructure addresses; no real operator-internal IPs are exposed.

## Documentation

Detailed docs are in Chinese (the primary audience is China's telecom/DNS community):
- [README.md](./README.md) — full usage guide
- [docs/AI_GUIDE.md](./docs/AI_GUIDE.md) — AI operator manual (12 chapters)
- [docs/TEST_METHOD.md](./docs/TEST_METHOD.md) — test methodology & scoring
- [docs/CODE_WIKI.md](./docs/CODE_WIKI.md) — developer code wiki (architecture/modules/functions/CI)
- [docs/SANDBOX_GUIDE.md](./docs/SANDBOX_GUIDE.md) — sandbox environment guide
- [docs/FAQ.md](./docs/FAQ.md) — frequently asked questions
- [docs/CHANGELOG.md](./docs/CHANGELOG.md) — full change history

## License

[MIT](./LICENSE)
