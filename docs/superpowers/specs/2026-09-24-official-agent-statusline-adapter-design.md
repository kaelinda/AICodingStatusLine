# 官方 Agent 状态栏适配设计

## 背景

本项目同时服务 Claude Code 和 Codex CLI，但两者的官方扩展契约不同：Claude Code 的 `statusLine` 执行外部命令，并把会话 JSON 通过 stdin 传入；Codex CLI 的原生 footer 只接受 `tui.status_line` 中的内置 item，不接受任意脚本渲染。现有实现已经提供主题、宽度预算、bars/compact 布局、Codex tmux 增强层和 hooks/notify sidecar，但仍有以下偏差：

- Claude Code 仍把工作目录固定读作旧的 `cwd`，没有利用官方推荐的 `workspace.current_dir` 和 worktree 字段。
- Claude Code 在已有官方 `rate_limits` 时仍可能额外访问 OAuth usage API，启动延迟和离线行为不理想。
- Claude Code 新增的 session、fast mode、prompt cache、cost、PR 等官方字段没有统一的可选展示入口。
- 安装脚本会覆盖 Claude `statusLine` 对象，且 Codex 原生 item 列表和 hooks feature key 落后于官方当前配置契约。

官方参考：

- [Claude Code status line](https://code.claude.com/docs/en/statusline)
- [Codex configuration reference](https://developers.openai.com/codex/config-reference)
- [Codex hooks](https://developers.openai.com/codex/hooks)
- [Codex status-line item implementation](https://github.com/openai/codex/blob/main/codex-rs/tui/src/bottom_pane/status_line_setup.rs)

## 目标

1. 让 Bash 和 PowerShell 的 Claude 状态栏优先消费官方 stdin schema，并对旧版本输入保持兼容。
2. 在可选段落中暴露高价值的官方字段，同时保持默认输出紧凑、宽度预算和现有主题不变。
3. 减少不必要的外部请求：官方已提供 rate-limit 数据时不调用 OAuth usage API；没有数据时仍保留现有缓存和回退路径。
4. 让安装/卸载过程尊重用户已有配置，并写入 Claude Code 官方支持的 status-line 选项。
5. 让 Codex 原生模式使用官方当前 item 名称和 canonical hooks 配置，同时保留 tmux 增强模式作为补充。
6. 以测试覆盖 Bash、PowerShell（可用时）、安装迁移和降级场景，并更新用户文档。

## 非目标

- 不把 Codex tmux 脚本伪装成 Codex 原生 `status_line` command hook。
- 不重写现有主题系统、tmux 会话管理器或交互式配置器。
- 不强制启用网络请求、OAuth 认证或 Codex hooks；所有外部数据都必须可降级为空/不可用。
- 不删除用户未由本项目写入的 settings、hooks 或 config 项。

## 设计

### 1. Claude 输入归一化和数据优先级

在 `scripts/statusline.sh` 和 `scripts/statusline.ps1` 中建立同名的归一化字段，渲染层只读取归一化变量：

| 归一化值 | 首选官方字段 | 兼容回退 |
| --- | --- | --- |
| 当前目录 | `workspace.current_dir` | `cwd` |
| 项目目录 | `workspace.project_dir` | 当前目录 |
| worktree | `worktree.name` / `workspace.git_worktree` | 空 |
| 模型 | `model.display_name` | `model.id` / `Claude` |
| effort | `effort.level` | `CLAUDE_CODE_EFFORT_LEVEL`、settings `effortLevel`、`medium` |
| context 使用率 | `context_window.used_percentage` | 根据 current usage 计算 |
| 5h/7d 限额 | `rate_limits.*.used_percentage` 与 `resets_at` | OAuth usage API + 缓存 |
| session | `session_name` | 空 |
| fast mode | `fast_mode` | false |
| prompt cache | `prompt_cache.warm` / `hit_ratio` | 空 |
| cost | `cost.total_cost_usd` | 空 |
| PR | `pr.number` / `pr.review_state` | 空 |

官方字段存在但为 `null` 时视同缺失，不覆盖有效的旧字段。rate-limit 的来源优先级必须是：stdin 官方字段 → 有效缓存 → OAuth API；只有在需要 API 时才执行 token 查找和网络请求。

### 2. Claude 可选段落

保留现有段落名称和默认顺序，并新增以下可选名称：

`session,mode,cache,cost,pr`

默认不改变用户当前输出；当用户在 `CLAUDE_CODE_STATUSLINE_SEGMENTS` 中显式列出新名称时才显示。各段落的最小文案如下：

- `session`: `session:<name>`；优先显示自定义/AI 会话名，过长时按现有中间截断规则处理。
- `mode`: `fast`、`think` 或 `effort:<level>`；只显示有数据的标记。
- `cache`: `cache 91%` 或 `cache warm`；不暴露空对象。
- `cost`: `$0.42`；只在 `cost.total_cost_usd` 为有限数值时显示。
- `pr`: `PR#1234 pending`；状态缺失时只显示编号。

bars 布局仍只渲染 git、概览、5h、7d 四类核心行；新增段落进入概览/compact 的宽度裁剪流程，不改变进度条行数。

### 3. Claude 官方 statusLine 配置合并

`install.sh` 和 `scripts/post-install.sh` 使用 `jq` 对已有 `.statusLine` 做字段级合并：

- 强制更新本项目的 `type=command` 与 `command`。
- 仅在用户没有明确设置时写入 `padding`（默认 `0`）、`refreshInterval`（默认 `15` 秒）和 `hideVimModeIndicator`（默认 `false`）。
- 用户已有的其它键和 `env` 项保持不变。
- 增加可选安装参数/环境变量来覆盖三个官方选项；卸载只删除本项目写入的值，不清空用户自定义值。

`refreshInterval` 只用于让 reset time、cache、cost 等时间性字段在主会话空闲时更新；脚本内 API/cache TTL 仍独立控制，避免每次刷新都发网络请求。

### 4. Codex 原生适配

定义一个可审计的官方 item 常量（按重要性排序）：

```toml
[tui]
status_line = [
  "model-with-reasoning",
  "current-dir",
  "git-branch",
  "branch-changes",
  "context-remaining",
  "five-hour-limit",
  "weekly-limit",
  "approval-mode",
  "fast-mode",
  "task-progress",
]
status_line_use_colors = true
```

安装逻辑：

- `tui.status_line` 缺失、为空，或等于本项目旧版托管值时，迁移到新列表。
- 用户自定义的其它列表原样保留；安装输出提示如何用 `/statusline` 调整顺序。
- 使用 `status_line_use_colors` 控制官方主题色，避免把 tmux ANSI 配置写进原生 footer。
- 卸载只删除新旧两种本项目托管值，绝不删除用户自定义列表。

tmux 增强脚本继续从 session JSONL 读取 token/rate-limit，作为多行 bars、主题、Git diff 和 sidecar 状态的补充；文档明确说明两条数据路径。

### 5. Codex hooks canonical key 和信任提示

`--with-hooks` 写入 `[features].hooks = true`，同时识别旧的 `codex_hooks` 作为兼容别名。卸载时只删除值为 `true` 的本项目写入项，并保留其它 feature 配置。安装输出和文档说明：

- hooks 默认可用，但非托管 hook 需要在 Codex `/hooks` 中 review/trust 后才会执行。
- `~/.codex/hooks.json` 是官方支持的用户级位置。
- sidecar 的 `statusMessage`、超时和 matcher 遵循官方事件 schema。

### 6. 错误处理和跨平台降级

- jq/PowerShell JSON 解析失败时输出基础模型/目录，不打印 stderr 到状态栏 stdout。
- 官方字段缺失、null、过期、非法数字统一视为不可用，不显示误导性的 0% 或假 reset 时间。
- 网络超时、401、429、离线时使用最近有效缓存；缓存失效则显示 `-`/`unavailable`，不阻塞主界面。
- 所有新增段落都参与现有宽度预算；中文、emoji 和长分支名至少覆盖截断测试。

## 文件边界

- 修改：`scripts/statusline.sh`、`scripts/statusline.ps1`：归一化、段落、rate-limit 优先级和宽度裁剪。
- 修改：`install.sh`、`scripts/post-install.sh`：配置合并、官方选项、Codex item 和 hooks key。
- 修改：`tests/test_statusline.py`：新增失败测试与回归覆盖。
- 修改：`README.md`、`docs/claude-code.md`、`docs/codex-cli.md`：官方契约、迁移和兼容说明。
- 新增：`docs/superpowers/plans/2026-09-24-official-agent-statusline-adapter.md`（实现计划）。

## 验收标准

1. 给定官方 Claude JSON 时，Bash/PowerShell 使用 `workspace.current_dir` 和 stdin `rate_limits`，且不会读取/请求 OAuth usage API。
2. 给定旧版 Claude JSON 或缺字段时，现有 140 项测试行为保持不变，且能稳定回退到缓存/API/占位符。
3. 新段落只有显式配置才出现，窄宽度下输出不超过预算（去 ANSI 后）。
4. 安装已有 Claude settings/Codex config/hooks 时，用户自定义键不被覆盖；卸载只移除本项目托管值。
5. Codex 原生列表只使用官方实现支持的 item 名称，hooks 使用 canonical `features.hooks` 并提示 `/hooks` trust 流程。
6. 完整 Python 回归测试通过；Bash 冒烟通过；有 `pwsh` 时 PowerShell 对照通过；脚本语法检查无错误。
