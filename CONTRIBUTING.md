# 贡献指南

欢迎参与 DNS/网络测试工具集的改进！本项目由一名学生维护，代码简单、结构清晰，适合学习和贡献。

## 项目结构

```
dns-test/
├── full.sh / lite.sh        # 基础测试入口（完整版/精简版）
├── dns-test.sh              # 交互入口（选DNS组/测试类型/专项）
├── dns-preset.sh            # 预设快捷测试
├── compare.sh               # 多DNS对比（并行+延迟中位数+HTML/JSON）
├── trends.sh                # DNS趋势洞察（聚合compare历史数据）
├── verify.sh                # 一键全面验证（语法+shellcheck+单测+冒烟+对比+趋势，--strict 可强制 shellcheck）
├── install.sh               # 一键安装依赖（缺失才装，--all 连可选依赖 shellcheck 一起装）
├── release.sh               # 打包发布脚本
├── smoke_test.sh            # 自动化冒烟测试（改动后必跑）
├── lib/                     # 公共库
│   ├── core.sh              # 核心库（变量/函数/并行/评分）
│   ├── compat.sh            # 平台兼容层（timeout等，macOS）
│   ├── plugins.sh           # 插件加载器（专项菜单动态驱动）
│   └── DNSUtil.pm           # DNS纯函数模块（可单测）
├── tests/                   # 单元测试
│   └── 01_dnsutil.t         # DNSUtil 18用例
├── tools/vowifi/            # VoWiFi专项（ePDG检测/路由器转发）
├── tools/network/           # 端口测试 / DoH-DoT检测
├── examples/                # 示例脚本（可传参）
└── docs/                    # 文档（含AI_GUIDE.md操作手册）
```

## 开发流程

1. **Fork + Clone**：Fork 本仓库，clone 到本地
2. **改代码**：遵循现有风格（bash 3.2+ / Perl 5.10+，v4/v6 双栈，注释中文）
3. **跑冒烟测试**（必须）：
   ```bash
   bash smoke_test.sh   # 25项全绿才能提交
   ```
4. **分支流程**：功能改动先提交到 develop 分支，CI（ubuntu+macOS）通过后再合并 main
5. **提交规范**：`type: 简短中文描述`（type: feat/fix/docs/chore）
6. **PR**：说明改动内容 + 附 smoke 结果

## 新增专项插件（可选）

专项菜单由注册表驱动（`dns-test.sh` 选"专项测试"自动列出），**新增一个专项只需两步**：

1. 把脚本放进 `tools/<目录>/`（或 `examples/`）
2. 在 `tools/manifest.sh` 的 `PLUGIN_ITEMS` 加一行：`插件id|脚本|菜单名|执行器(perl/bash)|引导提示(可空)|透传DNS(1/0,默认1)`，并在文件底部补 `PLUGIN_DIR_<id>="目录"` 映射

字段说明：`引导提示` 非空则执行前 `read -t 30` 询问一次；**参数策略三态**——引导输入非空→独占参数；空引导+透传DNS=1→透传当前 DNS 组；空引导+透传DNS=0→无参数执行（用脚本默认）。执行器白名单仅 `perl`/`bash`。详见 `lib/plugins.sh` 头注释。加完跑 `bash smoke_test.sh` 确认"插件注册表可加载"仍绿。

## 注意事项

- **不要硬编码运营商基础设施 IP**（示例用公共 DNS/私网地址，占位用 192.0.2.x）
- **不要提交**：results/ 日志、*.tar.gz、*.log、测试报告、trends/ 产物（.gitignore 已覆盖）
- **环境兼容**：Linux/macOS/WSL 双平台（macOS 默认 bash 3.2：避免关联数组 declare -A、mapfile、${var^^} 等 bash 4+ 语法；macOS 无 timeout 命令，用兼容函数或 dig/curl 自带超时）
- **超时保护**：新增测试项需考虑慢网络（预检/索引参数/超时）

## 文档同步

改了功能，记得同步：
- 新脚本 → README 目录结构 + AI_GUIDE 命令映射
- 新环境变量 → TEST_METHOD 环境变量表
- 新测试项 → TEST_METHOD 测试维度表
