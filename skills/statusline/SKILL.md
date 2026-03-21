# StatusLine Skill

Claude Code 状态栏配置管理工具。

## 触发命令

`/statusline`

## 默认配置

| 配置项 | 默认值 |
|--------|--------|
| theme | `default` |
| layout | `bars` |
| bar-style | `ascii` |
| max-width | `750` |

## 功能说明

在 Claude Code 对话中直接管理状态栏配置，无需手动编辑 JSON 文件。

## 支持的子命令

| 命令 | 说明 |
|------|------|
| `/statusline` | 显示当前配置 + 帮助信息 |
| `/statusline show` | 显示当前配置表格 |
| `/statusline theme [值]` | 切换主题（9 种可选） |
| `/statusline layout [值]` | 切换布局（compact / bars） |
| `/statusline bar-style [值]` | 切换进度条样式（7 种 + 自定义） |
| `/statusline max-width [值]` | 设置最大宽度（正整数或 auto） |
| `/statusline reset` | 恢复默认配置 |

## 可用主题

- `default` - 默认蓝色主调（高对比度）
- `forest` - 绿色主调（柔和自然）
- `dracula` - 紫色主调（暗色背景）
- `monokai` - 青色主调（经典编辑器风格）
- `solarized` - 蓝色主调（护眼低对比度）
- `ocean` - 青蓝主调（清爽海洋风）
- `sunset` - 珊瑚橙主调（温暖日落）
- `amber` - 琥珀金主调（沉稳大地色）
- `rose` - 玫瑰粉主调（柔和优雅）

## 可用布局

- `compact` - 所有信息压缩在一行
- `bars` - 多行布局，含进度条（**默认**）

## 进度条样式

仅 `bars` 布局生效：

- `ascii` - `[===-------]` 默认
- `dots` - `[●●●○○○○○○○]`
- `squares` - `[■■■□□□□□□□]`
- `blocks` - `[███░░░░░░░]`
- `braille` - `[⣿⣿⣿⣀⣀⣀⣀⣀⣀⣀]`
- `shades` - `[▓▓▓░░░░░░░]`
- `diamonds` - `[◆◆◆◇◇◇◇◇◇◇]`
- `custom:X:Y` - 自定义字符

## 最大宽度

控制状态栏的最大字符宽度：

- 正整数：如 `750`、`100`
- `auto`：自动检测终端宽度

## 使用示例

```
/statusline                    # 查看当前配置和帮助
/statusline theme dracula      # 切换到 dracula 主题
/statusline layout bars        # 切换到 bars 布局
/statusline bar-style dots     # 使用圆点进度条
/statusline max-width 1000     # 设置最大宽度为 1000
/statusline reset              # 恢复默认
```

## 配置存储

配置保存在 `~/.claude/settings.json` 的 `env` 字段：

```json
{
  "env": {
    "CLAUDE_CODE_STATUSLINE_THEME": "dracula",
    "CLAUDE_CODE_STATUSLINE_LAYOUT": "bars",
    "CLAUDE_CODE_STATUSLINE_BAR_STYLE": "dots",
    "CLAUDE_CODE_STATUSLINE_MAX_WIDTH": "750"
  }
}
```

## 注意事项

- `bar-style` 配置仅在 `layout: bars` 时生效
- 未知主题/样式会自动回退到默认值
- 修改配置后新会话立即生效
