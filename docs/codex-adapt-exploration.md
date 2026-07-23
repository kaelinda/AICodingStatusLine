# Codex CLI 适配探索：更丝滑的使用方式

> 目标：在保持现有 `codex-native` / `codex-tmux` 两种模式之上，探索一条让 Codex CLI 用起来更顺手、并且始终能看到分支/仓库信息的路径。

## 现状盘点

Codex CLI 已经具备的能力（本仓库已适配）：

| 能力 | 现状 |
|------|------|
| 原生 `tui.status_line` | 由 `install.sh --target codex-native` 落地，展示 `model-with-reasoning / context-remaining / current-dir` |
| tmux 增强状态栏 | `codex-tmux` + `codex-statusline`，`bars` 布局 4 行（git / overview / 5h / weekly） |
| Git 分支显示 | `build_branch_segment` 已存在，`CODEX_STATUSLINE_GIT_DISPLAY=repo|branch`，仓库有改动追加 `(+N -N)` |
| 实验性 hooks | `codex-hook-sidecar` 桥接 Bash 事件到状态栏 |
| 桌面通知 | `codex-notify-bridge` 转发 `notify` payload |
| 主题 / 布局 / 进度条样式 | 与 Claude Code 状态栏共用 9 主题、`bars/compact` 布局、7 种进度条 |

痛点也很明确：

1. **入口分裂**：想用增强模式必须显式敲 `codex-tmux`，习惯直接敲 `codex` 的用户不会自动获得 HUD。
2. **首装摩擦**：新用户不清楚该选 native / tmux；`--interactive` 只在 tmux 分支存在。
3. **分支感知只有一处**：只有 `bars` 布局第 1 行显示 `repo@branch`，`compact` 或 native 模式看不到分支信息。
4. **切分支不即时**：状态栏基于 `status-interval` 刷新，切分支后要等下一轮 tick，无法在切换瞬间感知。
5. **无 tmux 用户断档**：Codex CLI 本身不强制 tmux，用户如果不装 tmux 就完全没有增强 HUD。

## 探索方向

### 方向 A：智能启动器 `codex-launch`（本次已 prototype）

一条命令把「选模式 / 保证分支展示 / 缺依赖时降级」串起来。

- 在 git 仓库内：优先 tmux 增强，自动把 `git_display` 强制为 `repo`（同时给 native fallback 也追加 `git-branch` 段落，见方向 B）。
- 无 tmux：自动回退到 native 模式，并临时给 `tui.status_line` 追加分支段落。
- 首次运行：如果 `~/.codex/bin` 不存在，提示走 `install.sh` 而不是直接失败。
- 支持 `--force-native` / `--force-tmux` 显式覆盖。

> 代码：`scripts/codex_launch.sh`，安装后可以做成 `~/.codex/bin/codex-launch` 或直接 alias 成 `codex`。

### 方向 B：给原生 `tui.status_line` 注入分支感知

Codex 原生 `tui.status_line` 只接受一组固定枚举值（`model-with-reasoning`、`context-remaining`、`current-dir` 等），暂不支持自定义命令。

短期可行做法：

- 提供一份「git-friendly preset」，在 native 模式下也写入 `current-dir` 之外补上 `working-branch`（如果后续 Codex 官方提供该值），作为向前兼容 Hook。
- 中期：将 `codex-statusline` 提取为纯管线脚本，允许 native 模式通过外部 wrapper 展示分支，具体见方向 D。

### 方向 C：切分支 / 切目录时主动刷新

依赖 tmux `respawn-window` 太重。更轻的做法：

- 在 shell 层（zsh `chpwd` / bash `PROMPT_COMMAND`）加一个 hook：检测 `git symbolic-ref HEAD` 变化时 `tmux refresh-client -S`。
- 依赖：仅在检测到用户处于 `codex-*` 命名的 tmux 会话时启用，避免污染全局 shell。
- 落地：新加 `scripts/codex_shell_integration.sh`，用户可 `source` 进 `.zshrc`。

### 方向 D：无 tmux 场景的 inline HUD

面向不愿装 tmux 的用户，提供一个「行式 HUD」：

- `codex-statusline --once` 已经能输出一行 ANSI，可以复用为 shell prompt 的一部分。
- 提供 `codex_prompt_segment.sh`，输出 ready-to-paste 的 `PS1` / `PROMPT` 片段：`[codex gpt-5.4 · eff xhigh · ctx 41% · main]`。
- 首屏渲染成本可控（无 tmux 拉起、无子进程 hang）。

### 方向 E：更聪明的 session 定位

`codex-tmux` 目前用 `AICODINGSTATUS_TMUX_SESSION_NAME` 或 `codex-<projectname>` 作为 session 名。可以：

- 引入 `codex_launch --session <name>` 显式命名；
- 检测同名 session 已 attach，则 `switch-client` 而不是新建；
- 集成 Codex 端 `session_index.jsonl`，把 tmux session 与 Codex 会话 ID 对齐，方便切换。

## 本次交付

1. `docs/codex-adapt-exploration.md`（本文）— 现状、痛点、方向盘点。
2. `scripts/codex_launch.sh` — 方向 A 的可运行原型。
3. 后续 PR 可基于以上方向拆多阶段推进（推荐顺序：A → C → D → E → B）。

## 冒烟

```bash
# 直接运行（在任意 git 仓库中）
./scripts/codex_launch.sh --dry-run   # 只打印决策不真的拉起 codex
./scripts/codex_launch.sh             # 智能选模式并启动 codex

# 强制模式
./scripts/codex_launch.sh --force-native
./scripts/codex_launch.sh --force-tmux
```

`--dry-run` 输出示例（在本仓库内、已装 tmux）：

```
[codex-launch] repo=AICodingStatusLine branch=feat/adapt-codex
[codex-launch] mode=tmux (tmux found, git repo detected)
[codex-launch] statusline: git_display=repo, show_git_line=1
[codex-launch] would exec: /Users/you/.codex/bin/codex-tmux
```
