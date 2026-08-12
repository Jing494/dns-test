# DNS / Network Testing Toolkit

> 🌐 **中文**：[README.md](./README.md) ｜ **English**: This document

A unified toolkit for DNS benchmarking and network diagnostics, with a focus on China's telecom networks (Yunnan Telecom DNS as the default baseline, plus Alibaba/Tencent public DNS for comparison).

> 📄 Full documentation is in Chinese: [README.md](./README.md). This English file is a concise overview.

## Features

- **DNS Benchmarking** (lite: 10 items / full: 16 items, ~10s per DNS)
  - A/AAAA records, MX/NS/TXT/CNAME/SOA, stability (20 rounds), NXDOMAIN, ping (IPv4 + IPv6), consistency, carrier domains, DNSSEC, ECS, PTR, TTL, hijack detection, recursion
- **Carrier ePDG Deployment Detection** — check whether China Telecom / China Mobile / China Unicom / China Broadnet have deployed VoWiFi ePDG (per-province, via your provincial DNS)
- **Router DNS Forwarding Test** — verify if your home router forwards DNS to the provincial DNS (custom baseline supported)
- **DoH / DoT Support Check** — adaptive: real test via `dig +tls` / `curl --doh-url` when available, port-level probe otherwise
- **IPv6 support** — v4/v6 dual-stack everywhere, IPv6 connectivity test (ping6)
- **AI Operator Manual** — 12-chapter guide teaching AI agents how to interact with users properly (ask DNS → pick version → guide to specialty tests)
- **DNS Comparison** — `compare.sh` compares multiple DNS side-by-side (score / latency median / stability), optional responsive HTML report + structured JSON results
- **Trend Insight** — `trends.sh` aggregates historical compare results (linear-regression trend arrows, CSV export, SVG line charts, optional cron collection)
- **Automated Smoke Test** — `smoke_test.sh` validates all core paths in one run (23 checks)

## Quick Start

```bash
# TL;DR: clone → install → verify
git clone https://github.com/Jing494/dns-test.git && cd dns-test
bash install.sh            # install dig/perl/curl only if missing
bash smoke_test.sh         # 23-item automated validation
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
bash verify.sh             # one-command full self-check (syntax/unit/smoke/compare/trends)
bash smoke_test.sh         # automated 23-item validation
bash lite.sh 223.5.5.5 0   # benchmark a DNS
```

## Usage Examples

```bash
bash lite.sh                      # default: Yunnan Telecom DNS (lite)
bash full.sh 8.8.8.8 0            # full test, single DNS (index param to avoid timeout)
bash dns-preset.sh ali lite 0     # Alibaba DNS preset
bash compare.sh 223.5.5.5 119.29.29.29 --html  # DNS comparison + HTML report
bash compare.sh 223.5.5.5 119.29.29.29 --full   # full-mode comparison (77~78 checks/DNS)
bash trends.sh --html --csv       # trend insight (needs accumulated compare data)
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
- [docs/SANDBOX_GUIDE.md](./docs/SANDBOX_GUIDE.md) — sandbox environment guide
- [docs/FAQ.md](./docs/FAQ.md) — frequently asked questions
- [docs/CHANGELOG.md](./docs/CHANGELOG.md) — full change history

## License

[MIT](./LICENSE)
