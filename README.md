# cc-statusline

给 [Claude Code](https://claude.com/claude-code) 用的一个状态栏(statusline)脚本,一行命令装好。

效果大概长这样(加粗高对比度 ANSI 配色,深色/浅色终端背景都看得清;精简形不带文字标签,靠位置+颜色区分):

```
/home/you/project (main) | Opus 5.5 [high] | [▓▓░░░░░░░░] 46.8K/200.0K (23%) | sess $1.38 | 5h 42% $12.30 ↻2h13m | 7d 18% $85.20 ↻3d4h
```

各段用 `|` 隔开:

- **路径 `(git 分支)`**:当前工作目录;超过阈值(默认 40 字符,`CC_STATUSLINE_PATH_MAX` 可调)会自动缩成 `.../上级目录/当前目录`,给窄终端窗口省字数,兼容 `/` 与 `\` 两种分隔符。在 git 仓库里时后面跟当前分支(detached HEAD 显示短 commit hash),不在仓库里就不显示
- **模型 `[推理强度]`**:当前模型名,方括号里是推理强度档位(模型不支持 reasoning effort 时这半自动省略,不会瞎编)
- **`[进度条] 已用/窗口 (百分比%)`**:10 格进度条(长度可用 `CC_STATUSLINE_BAR_LEN` 调)+ 实际用了多少 token + 窗口总大小(自动格式化成 `1.0M` / `200.0K` 简写)+ 百分比;实际 token 数取不到时进度条仍在,只是分子退化成窗口大小本身。用量达到阈值(默认 80%)整段变红
- **`sess $..`**:本会话花费,直接取 Claude Code 自己算的 `cost.total_cost_usd`
- **`5h` / `7d`**:5 小时限额和周限额的已用百分比 + 本机在这个窗口内的用量(按官方 API 价折成美元)+ 距离重置还剩多久。只有订阅账号(Pro/Max)才有这组数据,API key 用户自动不显示;用量达到阈值(默认 80%)变红

所有数值都来自 Claude Code 通过 stdin 传给 statusline 脚本的真实 JSON 数据(`model.display_name`、`effort.level`、`context_window.*`、`workspace.current_dir`、`cost.total_cost_usd`、`rate_limits.five_hour.*` / `rate_limits.seven_day.*`),拿不到的字段直接跳过,不伪造。

### 5h / 7d 里的美元数是怎么算的

扫描本机 `~/.claude/projects/**/*.jsonl` transcript,取窗口内(reset 时间往前推 5 小时 / 7 天)所有 assistant 消息的 `usage`,按 `message.id + requestId` 去重,再按脚本里 `def price:` 那张官方 API 单价表折算:

- 输入 / 输出 / 缓存读按各模型单价;缓存写 5 分钟 = 输入价 ×1.25,1 小时 = 输入价 ×2
- Haiku 5.5 prompt 超过 100K 整条 ×5;Opus 5 / 5.5 fast mode ×2
- 表里没有的模型按 0 计

注意:

- 只算得到**本机** Claude Code 的用量,别的设备、claude.ai 网页端的用量不在里面,所以跟百分比不是严格对应
- 实测比 Claude Code 自己的 `cost.total_cost_usd` 略低(几个百分点),有些后台请求不会写进 transcript
- 单价写死在脚本里,官方调价后需要手动改 `def price:`
- 扫 transcript 有开销,结果缓存在 `~/.cache/cc-statusline/cost`,默认 30 秒刷新一次

## 配置开关

都是环境变量,写在 `settings.json` 的 command 前面即可,例如:

```json
"statusLine": {
  "type": "command",
  "command": "CC_STATUSLINE_COST=0 CC_STATUSLINE_LIMIT_WARN=90 bash ~/.claude/statusline-command.sh"
}
```

| 变量 | 默认 | 作用 |
|---|---|---|
| `CC_STATUSLINE_GIT` | `1` | `0` 关掉 git 分支 |
| `CC_STATUSLINE_LIMITS` | `1` | `0` 关掉 5h / 7d 两段(`sess` 不受影响) |
| `CC_STATUSLINE_COST` | `1` | `0` 关掉所有美元数(`sess` 和 5h / 7d 里的 `$`),也就不再扫 transcript |
| `CC_STATUSLINE_CTX_WARN` | `80` | 上下文百分比达到多少变红 |
| `CC_STATUSLINE_LIMIT_WARN` | `80` | 5h / 7d 百分比达到多少变红 |
| `CC_STATUSLINE_COST_TTL` | `30` | 美元用量缓存秒数 |
| `CC_STATUSLINE_PATH_MAX` | `40` | 路径超过多少字符开始缩写 |
| `CC_STATUSLINE_BAR_LEN` | `10` | 进度条格数 |

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

装完不用重启,Claude Code 会自动重新读取配置,状态栏马上就出来。

## 依赖

脚本用了 `jq` 和 `awk`(`git` 可选,没有就不显示分支):

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
rm -rf ~/.cache/cc-statusline   # 美元用量缓存
```

再手动把 `~/.claude/settings.json` 里的 `statusLine` 字段删掉(或者从 `settings.json.bak` 恢复)。

## 自定义

`statusline-command.sh` 是个 bash 脚本,直接改就行——想加别的字段,照着开头那个 `jq` 取值的写法加一项即可(所有字段一次 `jq` 取完,每多起一次 jq 都要几十毫秒)。

## License

MIT
