# 贡献指南

欢迎参与 DNS/网络测试工具集的改进！本项目由一名学生维护，代码简单、结构清晰，适合学习和贡献。

## 项目结构

```
dns-test/
├── full.sh / lite.sh        # 基础测试入口（完整版/精简版）
├── dns-test.sh              # 交互入口（选DNS组/测试类型/专项）
├── dns-preset.sh            # 预设快捷测试
├── smoke_test.sh            # 自动化冒烟测试（改动后必跑）
├── lib/core.sh              # 核心库（变量/函数/并行/评分）
├── tools/vowifi/            # VoWiFi专项（ePDG检测/路由器转发）
├── tools/network/           # 端口测试 / DoH-DoT检测
├── examples/                # 示例脚本（可传参）
└── docs/                    # 文档（含AI_GUIDE.md操作手册）
```

## 开发流程

1. **Fork + Clone**：Fork 本仓库，clone 到本地
2. **改代码**：遵循现有风格（bash 4+ / Perl 5.10+，v4/v6 双栈，注释中文）
3. **跑冒烟测试**（必须）：
   ```bash
   bash smoke_test.sh   # 14项全绿才能提交
   ```
4. **提交规范**：`type: 简短中文描述`（type: feat/fix/docs/chore）
5. **PR**：说明改动内容 + 附 smoke 结果

## 注意事项

- **不要硬编码运营商基础设施 IP**（示例用公共 DNS/私网地址，占位用 192.0.2.x）
- **不要提交**：results/ 日志、*.tar.gz、*.log、测试报告（.gitignore 已覆盖）
- **环境兼容**：Linux/macOS/WSL 双平台（避免 GNU 特有语法，如需用 grep -oP 请改 sed）
- **超时保护**：新增测试项需考虑慢网络（预检/索引参数/超时）

## 文档同步

改了功能，记得同步：
- 新脚本 → README 目录结构 + AI_GUIDE 命令映射
- 新环境变量 → TEST_METHOD 环境变量表
- 新测试项 → TEST_METHOD 测试维度表
