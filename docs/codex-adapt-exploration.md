# Codex CLI 适配探索：更丝滑的使用方式

> 目标：在 `codex-native` / `codex-tmux` 两种模式基础上，探索让 Codex CLI 用起来更顺手、并且始终能看到分支/仓库信息的路径。
>
> **本文档状态**：探索性 RFC。方向 A 有可运行 prototype，其余为规划。文档明确区分「已实现」与「计划中」，避免与实际能力脱节。

## 现状盘点

Codex CLI 已经具备的能力（本仓库已适配）：

| 能力 | 现状 |
|------|------|
| 原生 `tui.status_line` | 由 `install.sh --target codex-native` 落地，展示 `model-with-reasoning / context-remaining / current-dir`。**枚举固定，不接受自定义命令，也没有 `working-branch` 项**。 |
| tmux 增强状态栏 | `codex-tmux` + `codex-statusline`，`bars` 布局 4 行（git / overview / 5h / weekly） |
| Git 分支显示 | `build_branch_segment` 已存在，`CODEX_STATUSLINE_GIT_DISPLAY=repo|branch`，仓库有改动追加 `(+N -N)` |
| 实验性 hooks | `codex-hook-sidecar` 桥接 Bash 事件到状态栏 |
| 桌面通知 | `codex-notify-bridge` 转发 `notify` payload |
| 主题 / 布局 / 进度条样式 | 与 Claude Code 状态栏共用 9 主题、`bars/compact` 布局、7 种进度条 |

痛点：

1. **入口分裂**：想用增强模式必须显式敲 `codex-tmux`，习惯直接敲 `codex` 的用户不会自动获得 HUD。
2. **首装摩擦**：新用户不清楚该选 native / tmux；`--interactive` 只在 tmux 分支存在。
3. **分支感知只有一处**：仅 `bars` 布局第 1 行显示 `repo@branch`，`compact` 或 native 模式看不到分支信息。
4. **切分支不即时**：状态栏基于 `status-interval` 刷新，切分支后要等下一轮 tick。
5. **无 tmux 用户断档**：Codex CLI 本身不强制 tmux，用户不装 tmux 就没有增强 HUD。

## 五条探索方向（A–E）

### 方向 A：智能启动器 `codex-launch` ✅ 本次已 prototype

一条命令把「选模式 / 保证分支展示 / 缺依赖时降级」串起来。

**已实现**：
- 在 git 仓库内 + 已装 tmux + `~/.codex/bin/codex-tmux` 存在 → 走 tmux 增强模式，通过环境变量把 `CODEX_STATUSLINE_GIT_DISPLAY=repo` / `CODEX_STATUSLINE_SHOW_GIT_LINE=1` 一路透传到状态栏（`codex_tmux.sh` 现已把 `GIT_DISPLAY` 加入 `tmux set-environment` 同步列表）。
- 无 tmux 或无 wrapper：优雅回退到直接 `exec codex`，避免报错。
- 支持 `--force-tmux` / `--force-native` / `--dry-run` / `--session NAME`。
- `--session` 现已校验缺参和 flag-like 值，防止吞掉下一个 flag。

**已知限制**（本次不覆盖，见方向 B/D）：
- native fallback 只在启动前打印一次性 repo/branch 日志。**进入 Codex TUI 后仍受官方 `tui.status_line` 固定枚举限制，不会显示分支段落**。要实现「无 tmux 也能持续看到 branch」，需等方向 B/D 完成。
- 未纳入 `install.sh` 安装流程，需手动 `chmod +x scripts/codex_launch.sh` 后使用；后续方向 F 会补齐 install/uninstall 与 README 引导。

### 方向 B：给原生 `tui.status_line` 注入分支感知（阻塞在上游）

Codex 官方 `tui.status_line` 只接受一组固定枚举值（`model-with-reasoning`、`context-remaining`、`current-dir` 等），暂不支持自定义命令，也没有 `working-branch`。

计划分两步：
- 短期：跟进 Codex 官方 changelog，一旦官方新增 `working-branch` 之类的枚举项，就在 `install.sh --target codex-native` 里默认写入。
- 中期：如果官方长期不支持，改由方向 D 的 inline HUD 兜底。

**当前状态**：未实现，本次不承诺。

### 方向 C：切分支 / 切目录时主动刷新

- 在 shell 层（zsh `chpwd` / bash `PROMPT_COMMAND`）加 hook，检测到 `HEAD` 变化时执行 `tmux refresh-client -S`。
- 仅在检测到用户处于 `codex-*` 命名的 tmux 会话时启用，避免污染全局 shell。
- 落地：`scripts/codex_shell_integration.sh`，用户 `source` 进 `.zshrc`。

**当前状态**：规划中。

### 方向 D：无 tmux 场景的 inline HUD

面向不愿装 tmux 的用户，把 `codex-statusline --once` 拼进 shell prompt：

- 输出 `[codex gpt-5.4 · eff xhigh · ctx 41% · main]` 之类的 PS1 片段。
- 提供 `scripts/codex_prompt_segment.sh`。
- 首屏渲染成本可控（无 tmux 子进程）。

**当前状态**：规划中。方向 A 的 native fallback 需要它才能兑现「持续显示 branch」承诺。

### 方向 E：更聪明的 session 定位

- `codex_launch --session <name>` 显式命名（本次已加）。
- 检测同名 session 已 attach，则 `switch-client` 而不是新建。
- 集成 Codex 端 `session_index.jsonl`，把 tmux session 与 Codex 会话 ID 对齐。

**当前状态**：仅命名参数已实现，其余规划中。

## 本次实际交付

1. `docs/codex-adapt-exploration.md`（本文）— 现状 / 痛点 / A–E 方向。
2. `scripts/codex_launch.sh` — 方向 A prototype。
3. `scripts/codex_tmux.sh` — 补 `CODEX_STATUSLINE_GIT_DISPLAY` 到 tmux 环境同步列表，兑现「tmux 模式下 `git_display=repo` 一定生效」的承诺。
4. `docs/codex-cli.md` — 顶部加「智能启动器（可选）」小节，链接到本文档。

## 冒烟

```bash
# 直接运行（在任意 git 仓库中）
./scripts/codex_launch.sh --dry-run     # 只打印决策不真的拉起 codex
./scripts/codex_launch.sh               # 智能选模式并启动 codex

# 强制模式
./scripts/codex_launch.sh --force-native
./scripts/codex_launch.sh --force-tmux

# --session 校验
./scripts/codex_launch.sh --session          # → 报错并 exit 2
./scripts/codex_launch.sh --session --dry-run # → 报错并 exit 2
./scripts/codex_launch.sh --session myproj --dry-run  # ✅
```

`--dry-run` 输出示例（在本仓库内、已装 tmux）：

```
[codex-launch] repo=AICodingStatusLine branch=feat/adapt-codex
[codex-launch] mode=tmux (tmux found, git repo detected)
[codex-launch] statusline: git_display=repo, show_git_line=1
[codex-launch] would exec: /Users/you/.codex/bin/codex-tmux
```

## Review 反馈应对

| Review 项 | 应对 |
|-----------|------|
| tmux 模式 `git_display=repo` 无法透传 | 已把 `CODEX_STATUSLINE_GIT_DISPLAY` 加进 `codex_tmux.sh:90` 的 `tmux set-environment` 同步列表 |
| native fallback 文档承诺过度 | 本文档 A 方向明确降级为「启动日志显示 branch；持续显示需等方向 D」 |
| `--session` 吞掉下一个 flag | 已在 `codex_launch.sh:30-38` 加校验，缺参或值以 `-` 开头即 `exit 2` |
| launcher 未进入 install/README | 已在 `docs/codex-cli.md` 顶部注明为可选实验入口；进入 install 走单独 PR（本 RFC 之外） |
| 既有测试 `test_codex_tmux_launcher_binds_statusline_to_new_session_file` 失败 | 与本分支 diff 无关（`/tmp` vs `/private/tmp` 路径归一化，见既有 issue）；建议单独跟进 |

## 下一步排序

推荐按 A → C → D → E → B 推进。B 有上游依赖，最后处理。
