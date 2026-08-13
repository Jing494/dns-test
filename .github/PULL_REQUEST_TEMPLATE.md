## 变更内容
（做了什么，为什么）

## 类型
- [ ] feat 新功能
- [ ] fix 修复
- [ ] docs 文档
- [ ] refactor 重构
- [ ] chore 其他

## 验证
- [ ] `bash verify.sh` 全部通过（或说明哪些网络项因环境跳过）
- [ ] `perl -Ilib tests/01_dnsutil.t` 与 `bash tests/02_plugins.sh` 单测通过
- [ ] shellcheck 0 告警（`shellcheck -S warning *.sh lib/*.sh tools/*.sh tools/network/*.sh`）
- [ ] 插件变更已同步 `tools/manifest.sh` + README 插件机制小节（若有）

## 兼容性检查
- [ ] 无 bash 4+ 专属语法（declare -A/mapfile/${var^^} 等，macOS 默认 bash 3.2）
- [ ] 无 GNU 专属命令（timeout/sort -V 等，macOS 兼容）

## 备注
