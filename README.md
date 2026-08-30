# cc-statusline

给 [Claude Code](https://claude.com/claude-code) 用的一个状态栏(statusline)脚本,一行命令装好。

效果大概长这样(加粗高对比度 ANSI 配色,深色/浅色终端背景都看得清;精简形不带文字标签,靠位置+颜色区分):

```
/home/you/project | Opus 5 [max] | [▓▓░░░░░░░░] 46.8K/200.0K (23%)
```

三段信息,中间用 `|` 隔开:

- **路径**:当前工作目录;超过阈值(默认 40 字符,`CC_STATUSLINE_PATH_MAX` 可调)会自动缩成 `.../上级目录/当前目录`,给窄终端窗口省字数,兼容 `/` 与 `\` 两种分隔符
- **模型 `[推理强度]`**:当前模型名,方括号里是推理强度档位(模型不支持 reasoning effort 时这半自动省略,不会瞎编)
- **`[进度条] 已用/窗口 (百分比%)`**:10 格进度条(长度可用 `CC_STATUSLINE_BAR_LEN` 调)+ 实际用了多少 token + 窗口总大小(自动格式化成 `1.0M` / `200.0K` 简写)+ 百分比;实际 token 数取不到时进度条仍在,只是分子退化成窗口大小本身

所有数值都来自 Claude Code 通过 stdin 传给 statusline 脚本的真实 JSON 数据(`model.display_name`、`effort.level`、`context_window.used_percentage`、`context_window.total_input_tokens`、`context_window.context_window_size`、`workspace.current_dir`),拿不到的字段直接跳过,不伪造。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/prehisle/cc-statusline/main/install.sh | bash
```

做了两件事:

1. 把 `statusline-command.sh` 下载到 `~/.claude/statusline-command.sh`
2. 把下面这段合并进 `~/.claude/settings.json`(已有配置会先备份成 `settings.json.bak` 再合并,不会丢你原有的其它设置)

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/statusline-command.sh"
}
```

装完重启 Claude Code(或新开一个会话)即可看到状态栏。

## 依赖

脚本用了 `jq` 和 `awk`:

- **macOS**:`awk` 自带,`jq` 需要 `brew install jq`
- **Debian/Ubuntu**:`awk` 自带,`jq` 需要 `sudo apt install jq`
- **Windows**:走 Git Bash,两者都自带

安装脚本本身也依赖 `jq`(用来安全合并 `settings.json`),没装会直接报错退出,不会静默失败。

## 手动安装

不想用一键脚本,也可以自己动手:

1. 把 [`statusline-command.sh`](./statusline-command.sh) 存到 `~/.claude/statusline-command.sh`,加可执行权限
2. 在 `~/.claude/settings.json` 里加上 `statusLine` 那段配置(见上)

## 项目级共享(团队/仓库统一 statusline)

不想每人手动装,也可以把脚本放进项目仓库里(比如 `.claude/statusline-command.sh`),然后在**项目级** `.claude/settings.json` 里用相对路径:

```json
"statusLine": {
  "type": "command",
  "command": "bash .claude/statusline-command.sh"
}
```

这样协作者 clone 仓库、打开 Claude Code 就自动生效,不用各自跑安装命令。

## 卸载

```bash
rm ~/.claude/statusline-command.sh
```

再手动把 `~/.claude/settings.json` 里的 `statusLine` 字段删掉(或者从 `settings.json.bak` 恢复)。

## 自定义

`statusline-command.sh` 是个几十行的 bash 脚本,直接改就行——想加 git 分支、加 rate limit 用量之类的字段,照着现有的 `jq -r '...'` 取值写法加一段即可。

## License

MIT
