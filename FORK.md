# 私有 fork 维护说明（PI-Desktop 适配）

本仓库是 [mindfold-ai/Trellis](https://github.com/mindfold-ai/Trellis) 的私有 fork，唯一目的是让 **PI-Desktop** 成为 Trellis 的一等平台（第 23 个）。上游不合并这份改动，所以维护方式固定为：**上游跟进 + 本地重基**。

| 远端 | 地址 | 用途 |
| --- | --- | --- |
| `upstream` | `mindfold-ai/Trellis` | 只读，跟随官方发布 |
| `origin` | `Techd81/Trellis` | 本 fork，自用 |

分支模型：

- `main` —— 永远与 `upstream/main` 齐平，不放任何本地改动。
- `feat/pi-desktop` —— 全部适配改动，基于 `main` 重基。日常用的是这条分支。

## 相对上游改了什么（37 个文件）

| 区域 | 文件 | 作用 |
| --- | --- | --- |
| 平台注册 | `packages/cli/src/types/ai-tools.ts` | 新增 `pi-desktop` 条目；`pi` 增加 `detectionPaths`，避免纯桌面仓库被误判为 pi CLI 项目 |
| 模板收集 | `configurators/{pi,pi-desktop,index,shared}.ts` | `collectPiSurface()` 复用 pi 的共享面；`pi-desktop` 另加插件外壳 |
| 插件模板 | `templates/pi-desktop/{manifest.json,main.js,index.ts,subagents.ts}` | 宿主插件清单、启动脚本、全局 sub-agent 定义 |
| 宿主扩展 | `templates/pi/extensions/trellis/index.ts.txt` | 桌面端运行期分支：不注册 spawn 型工具、`Task` 派发补 `Active task:`、用 shell ticket 传会话身份 |
| 安装桥 | `commands/pi-desktop/**`、`constants/pi-desktop.ts` | `install` / `status` / `uninstall` |
| CLI 接线 | `cli/index.ts`、`commands/init.ts` | `--pi-desktop` 与 `pi-desktop` 子命令 |
| 脚本 | `templates/trellis/scripts/common/{task_store,workflow_phase}.py` + `.trellis/scripts` 双胞胎 | `.pi-desktop` 加入 sub-agent 平台表；`pi-desktop → Pi` 标记 |
| 测试 | `test/commands/pi-desktop.test.ts`、`test/templates/pi-desktop.test.ts`、`test/templates/trellis.test.ts` | 46 条（30 + 16） |
| 文档 | `README.md`、`README_CN.md`、`.trellis/spec/cli/backend/{platform-integration,commands-pi-desktop,index}.md` | 平台计数 22 → 23、适配说明 |

### `docs-site` 子模块怎么办

`docs-site` 是独立仓库（`mindfold-ai/docs`），上游不会接受这份文档改动。所以：**子模块 HEAD 停在上游提交，改动以补丁形式留在工作区**，不提交。

恢复或重新打补丁：

```powershell
git -C docs-site checkout -- .
git -C docs-site apply ../docs-site.pi-desktop.patch
```

补丁的权威副本同时存在 fork 的 `Techd81/docs` 分支 `docs/pi-desktop` 上。

之所以必须打上：`registry-invariants` 会核对 `docs-site` 里的平台计数和 init flag 列表，缺了 `--pi-desktop` 就会红（`beta/start/install-and-first-task.mdx` 等）。上游把子模块指针推进后，用 `git apply --3way` 重打，冲突按语义手工合并即可。

## 安装：`npm install -g @techd81/trellis@latest`

本 fork 以 `@techd81/trellis` 的名义发布，装到的就是这份带 `--pi-desktop` 的代码；官方包 `@mindfoldhq/trellis` 不含它。

不发布也能从源码装：

```powershell
pwsh ./scripts/install-fork.ps1
```

脚本顺序：`pnpm install` → PI-Desktop 靶向测试 → `pnpm build` → `pnpm pack`（把 `workspace:*` 重写成真实版本号）→ `npm i -g` → 校验 `--pi-desktop`。

`@mindfoldhq/trellis-core` 始终从 npm 拉取，本 fork 只改 CLI 包。

验证：

```powershell
trellis --version
trellis init --help | Select-String -- --pi-desktop
trellis pi-desktop --help
```

回退到官方版：

```powershell
npm install -g @mindfoldhq/trellis --force
```

### 发布（首次安装前，以及每次跟随上游之后）

```powershell
npm login                                   # 需要拥有 @techd81 作用域
pnpm build
cd packages/cli
Copy-Item ../../README.md ../../LICENSE .
npm publish --access public --ignore-scripts
```

- `--access public`：scoped 包默认私有，必须显式公开。
- `--ignore-scripts`：`prepublishOnly` 会跑全量测试（Windows 上有 23 个既有环境失败）并用 `cp` 复制文件（cmd 下没有该命令），所以本地发布时跳过脚本。
- 版本号跟上游保持一致：上游发 `0.6.18` → `sync-upstream.ps1` → 把 `packages/cli/package.json` 的 `version` 改成 `0.6.18` → 再 publish。这样 `trellis update` 的版本比较才有意义。

## 跟随上游更新

```powershell
pwsh ./scripts/sync-upstream.ps1
```

脚本按顺序做：脏工作区检查 → `fetch upstream` → `main` 快进 → 把 `feat/pi-desktop` 重基到新 `main` → 锁文件变了才 `pnpm install` → `pnpm build` → 铺进全局包 → 跑 PI-Desktop 靶向测试。

遇到重基冲突会停下并列出冲突文件，不会替你丢改动。人工解决后 `git rebase --continue` 即可。

冲突热点（上游一改这些，八成要手接）：`types/ai-tools.ts`、`commands/init.ts`、`cli/index.ts`、`configurators/pi.ts`、`templates/pi/extensions/trellis/index.ts.txt`。

## 更新后必做的验证

1. 靶向测试（脚本已跑）：
   `npx vitest run --maxWorkers=3 test/commands/pi-desktop.test.ts test/templates/pi-desktop.test.ts test/registry-invariants.test.ts`
2. 双胞胎字节一致：`.trellis/scripts/**` 与 `packages/cli/src/templates/trellis/scripts/**` 必须逐文件同哈希（28 个源码文件）。
3. 真机：重启 PI-Desktop → 在项目里跑一次含 `task.py current` 的 shell 命令 → `.trellis/.runtime/shell-tickets/` 应出现票据，`task.py current --source` 应显示 `session:pi_*`。
   桌面端不靠环境变量传递身份：宿主 shell 工具叫 `Bash`，且方言（PowerShell / cmd / git-bash / bash）由用户配置、事件里不报，所以走 shell ticket。

## 已知环境限制

Windows 本机跑全量测试有 23 个既有失败（`python3` 的 Store 别名、`chmod`、marketplace 的 CRLF 镜像、`TMPDIR=/tmp`、npm mock），与本 fork 无关，Linux CI 上不出现。脚本只跑靶向测试，正是为了绕开它们。
