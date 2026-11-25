# 贡献指南

本仓库是 [mindfold-ai/Trellis](https://github.com/mindfold-ai/Trellis) 的**私有 fork**，
在上游基础上把 [PI-Desktop](https://github.com/vastsa/PI-Desktop) 接成一等平台，
并以 [`@awesome_dura/trellis`](https://www.npmjs.com/package/@awesome_dura/trellis) 的名义发布 CLI。

## 问题该提在哪

| 类型 | 去处 |
| --- | --- |
| 上游 Trellis 的 bug、功能、平台支持 | [mindfold-ai/Trellis issues](https://github.com/mindfold-ai/Trellis/issues) |
| PI-Desktop 安装 / 插件 / 子智能体问题 | 本仓库的 Issues |
| 构建、安装、跟随上游、发布 | [FORK.md](FORK.md) |
| 本 fork 改了什么、为什么 | `.trellis/spec/cli/backend/platform-integration.md` |

## 在本 fork 上开发

```powershell
pnpm install
pnpm build                      # core + cli
pwsh ./scripts/install-fork.ps1 # 从源码装全局 CLI
```

靶向测试（全量测试里有 23 个从上游继承的 Windows 环境失败，所以脚本只跑相关文件）：

```powershell
cd packages/cli
npx vitest run --maxWorkers=3 test/commands/pi-desktop.test.ts test/templates/pi-desktop.test.ts test/registry-invariants.test.ts
```

`.trellis/scripts/**` 与 `packages/cli/src/templates/trellis/scripts/**` 必须逐字节一致——有测试在盯着。

## 许可证

AGPL-3.0，继承自上游。见 [LICENSE](LICENSE)。
