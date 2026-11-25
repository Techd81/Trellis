# 私有 fork 维护说明（PI-Desktop 适配）

本仓库是 [mindfold-ai/Trellis](https://github.com/mindfold-ai/Trellis) 的私有 fork，唯一目的是让 **PI-Desktop** 成为 Trellis 的一等平台（第 23 个）。上游不合并这份改动，所以维护方式固定为：**上游跟进 + 本地重基**。

| 远端 | 地址 | 用途 |
| --- | --- | --- |
| `upstream` | `mindfold-ai/Trellis` | 只读，跟随官方发布 |
| `origin` | `Techd81/Trellis` | 本 fork，自用 |

分支模型：

- `main` —— **本 fork 的产品分支**：上游 + PI-Desktop 适配。GitHub 默认分支、npm 发布源都是它。
- 跟随上游：`scripts/sync-upstream.ps1` 把 `upstream/main` 合并进 `main` 并推送。

## 相对上游改了什么

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

## 安装：`npm install -g @awesome_dura/trellis@latest`

本 fork 以 `@awesome_dura/trellis` 的名义发布，装到的就是这份带 `--pi-desktop` 的代码；官方包 `@mindfoldhq/trellis` 不含它。

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
npm login                                # 账号 awsome_dura；@awesome_dura 作用域挂在 org 上
pwsh ./scripts/publish-fork.ps1 -DryRun  # 只看清单，不上传
pwsh ./scripts/publish-fork.ps1          # 真发布
pwsh ./scripts/publish-fork.ps1 -Otp 123456   # 账号 2FA 覆盖写操作时，带上一次性验证码
```

脚本会：校验在 `main` 且工作区干净 → `pnpm build` → 把根目录的 `README.md`/`LICENSE` 复制进 `packages/cli` → 临时把 `workspace:*` 钉成真实版本号 → `npm publish --access public --ignore-scripts` → 回读 registry 并校验依赖不再是 workspace → 还原 `package.json`。

- `--access public`：scoped 包默认私有，必须显式公开。
- `--ignore-scripts`：`prepublishOnly` 会跑全量测试（Windows 上有 23 个既有环境失败）并用 `cp` 复制文件（cmd 下没有该命令），所以发布时跳过脚本。
- 版本号默认跟上游保持一致；确实需要单独发版时按补丁位递增，并在这里记一笔。`0.6.18` 就是这么来的：`0.6.17` 已发布，但依赖写成了 `workspace:*` 装不上，而 npm 不允许重发同一版本。
- 脚本发布前会把 `@mindfoldhq/trellis-core: workspace:*` 临时钉成 `packages/core` 的真实版本号，发完自动还原。`npm publish` 不做这个重写，直接发会让所有人装不上（`EUNSUPPORTEDPROTOCOL`）。
- 新版本发布后 `PUT` 返回 **202**，registry 要 3~6 分钟才看得到，这期间 `npm view` / `npm i` 会 404 —— 不是失败，等就行。
- bypass-2FA 的 granular token 能发布，但**不能 unpublish**（403）。发废的版本只能去 npm 的包设置页 `Delete version` 手动删。

## 跟随上游更新

```powershell
pwsh ./scripts/sync-upstream.ps1
```

脚本按顺序做：脏工作区检查（必须在 `main` 上）→ `fetch upstream` → 把 `upstream/main` 合并进 `main` 并推送 → 锁文件变了才 `pnpm install` → `pnpm build` → 打包并安装全局 CLI → 跑 PI-Desktop 靶向测试。

遇到合并冲突会停下并列出冲突文件，不会替你丢改动。人工解决后 `git add` + `git merge --continue`（或 `git merge --abort`）即可。

冲突热点（上游一改这些，八成要手接）：`types/ai-tools.ts`、`commands/init.ts`、`cli/index.ts`、`configurators/pi.ts`、`templates/pi/extensions/trellis/index.ts.txt`。

## 更新后必做的验证

1. 靶向测试（脚本已跑）：
   `npx vitest run --maxWorkers=3 test/commands/pi-desktop.test.ts test/templates/pi-desktop.test.ts test/registry-invariants.test.ts`
2. 双胞胎字节一致：`.trellis/scripts/**` 与 `packages/cli/src/templates/trellis/scripts/**` 必须逐文件同哈希（28 个源码文件）。
3. 真机：重启 PI-Desktop → 在项目里跑一次含 `task.py current` 的 shell 命令 → `.trellis/.runtime/shell-tickets/` 应出现票据，`task.py current --source` 应显示 `session:pi_*`。
   桌面端不靠环境变量传递身份：宿主 shell 工具叫 `Bash`，且方言（PowerShell / cmd / git-bash / bash）由用户配置、事件里不报，所以走 shell ticket。

## 已知环境限制

Windows 本机跑全量测试有 23 个既有失败（`python3` 的 Store 别名、`chmod`、marketplace 的 CRLF 镜像、`TMPDIR=/tmp`、npm mock），与本 fork 无关，Linux CI 上不出现。脚本只跑靶向测试，正是为了绕开它们。
