# ❓ 常见问题（FAQ）

> 快速问题排查；详细方法论见 [TEST_METHOD.md](./TEST_METHOD.md)，环境差异见 [AI_GUIDE.md](./AI_GUIDE.md) 第十一章。

## ❓ 常见问题

### Q: 运行超时怎么办？
完整版测试单DNS约2-4分钟，多DNS完整跑完会超过大多数调用超时限制。解决方案：
- **推荐**：命令末尾加索引参数，只测第N个DNS：`bash full.sh 8.8.8.8 114.114.114.114 0`
- 或运行入口脚本，选择基础测试后选"指定测试某一个DNS"
- 非交互模式（无终端）自动降级为精简版+仅第1个DNS，不会超时

### Q: 测试结果中的扣分项影响使用吗？
- PTR解析扣分：国内IP大多无反向解析，属于正常现象，不影响使用
- 劫持检测扣分：CDN域名解析不同是负载均衡正常现象
- DNSSEC扣分：不是所有域名都部署了DNSSEC，轻微影响
- VoWiFi域名返回127.0.0.1：表示该运营商未部署ePDG，属于正常现象

### Q: 如何验证路由器DNS是否转发到省级DNS？
运行路由器DNS转发测试（`perl tools/vowifi/03_test_router_dns.pl 192.168.1.1`），脚本会先取云南电信省级DNS的解析结果作为基准，再对比路由器DNS的解析结果——完全一致则说明路由器将DNS请求转发到了省级DNS；不一致则可能是自建DNS或转发了其他DNS。

### Q: 支持哪些操作系统？
支持所有安装了`dig`、`ping`工具的Linux/macOS系统，Perl脚本需要Perl 5.10+环境。

**Windows 用户**（不支持原生，请用以下方式）：
```bash
# 方式1: WSL（推荐，体验与Linux一致）
wsl --install                    # 首次安装WSL
wsl -d Ubuntu -- apt install dnsutils curl perl   # 装依赖
wsl -d Ubuntu -- bash smoke_test.sh               # 验证

# 方式2: Git Bash / MSYS2（部分功能可用，需自行装 dig/perl）
#   注意: DoH/DoT检测的 /dev/tcp 在Git Bash下不可靠
```
> 不建议尝试原生 cmd/PowerShell 运行——脚本依赖 bash 特性（BASH_SOURCE、/dev/tcp 等）与 GNU 工具（dig/sed/awk）。

### Q: 可以测试多少个DNS？
支持任意数量的DNS。单个DNS可完整跑完；多个DNS建议用索引参数逐个测（`bash full.sh A B 0`、`bash full.sh A B 1`），避免单次调用超时。

---

