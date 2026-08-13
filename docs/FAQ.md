# ❓ 常见问题（FAQ）

> 快速问题排查；详细方法论见 [TEST_METHOD.md](./TEST_METHOD.md)，环境差异见 [AI_GUIDE.md](./AI_GUIDE.md) 第十一章。

## ❓ 常见问题

### Q: verify.sh 提示"未安装 shellcheck，跳过"，需要装吗？
不需要也行——shellcheck 是**可选依赖**（shell 静态检查工具），只影响 verify.sh 的"代码质量检查"这一项，**不影响任何 DNS 测试功能**；代码质量已由 CI 兜底（GitHub Actions 每轮自动检查）。
- 想装（推荐开发者）：`bash install.sh --all`（自动检测包管理器一键装），或按系统手动 `sudo apt-get install -y shellcheck` / `brew install shellcheck`
- 装完后 `bash verify.sh` 该项会显示 "shellcheck(0告警)"；`bash verify.sh --strict` 可强制要求该项必须存在

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

**Windows 用户**（不支持原生运行，推荐 **WSL**——体验与 Linux 完全一致，全功能可用）：

**方式1: WSL（推荐，一条命令开装）**
```bash
# ① 安装 WSL（管理员 PowerShell 或 CMD 运行，装完按提示重启，重启后自动进入 Ubuntu 并让你设置 Linux 用户名/密码）
wsl --install

# ② 若未自动装好发行版，可手动指定
wsl --install -d Ubuntu

# ③ 进入 WSL（Ubuntu 窗口）后，更新系统并安装依赖
sudo apt update && sudo apt upgrade -y
sudo apt install -y dnsutils perl curl

# ④ 在 WSL 内验证环境（把工具包放到 WSL 能访问的位置，如 /mnt/d/dns-test）
cd /mnt/d/dns-test        # D盘在WSL里挂载为 /mnt/d
bash smoke_test.sh        # 25 项自动化验证，全绿 = 环境就绪
bash dns-test.sh          # 交互引导测试
```
> 💡 要点：`wsl --install` 需 Win10 2004+/Win11；老版本先 `wsl --update` 升到 WSL2；Windows 文件（D 盘等）在 WSL 里挂载为 `/mnt/<盘符>`，可直接访问；装完依赖也可直接 `bash install.sh` 自动补齐。

**方式2: Git Bash / MSYS2（部分功能可用，需自行装 dig/perl/curl）**
- 可用: lite/full 多数项、compare、trends（前提：自行装好 dig/perl/curl）
- 不可靠: DoH/DoT 检测的 `/dev/tcp` 端口探测
- 换行: 仓库已带 `.gitattributes` 强制 LF，clone 不会出现 CRLF 报错

> 不建议尝试原生 cmd/PowerShell 运行——脚本依赖 bash 特性（BASH_SOURCE、/dev/tcp 等）与 GNU 工具（dig/sed/awk）。

### Q: 可以测试多少个DNS？
支持任意数量的DNS。单个DNS可完整跑完；多个DNS建议用索引参数逐个测（`bash full.sh A B 0`、`bash full.sh A B 1`），避免单次调用超时。

---

