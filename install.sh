#!/usr/bin/env bash
# cc-statusline installer
# 用法: curl -fsSL https://raw.githubusercontent.com/prehisle/cc-statusline/main/install.sh | bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/prehisle/cc-statusline/main"
CLAUDE_DIR="$HOME/.claude"
SCRIPT_PATH="$CLAUDE_DIR/statusline-command.sh"
SETTINGS_PATH="$CLAUDE_DIR/settings.json"

echo "==> 安装 cc-statusline"

if ! command -v jq >/dev/null 2>&1; then
  echo "错误:需要 jq,但没找到,请先装好再重跑本脚本。" >&2
  echo "  macOS:            brew install jq" >&2
  echo "  Debian/Ubuntu:    sudo apt install jq" >&2
  echo "  Windows(Git Bash 自带,若没有可去 https://jqlang.github.io/jq/ 下载)" >&2
  exit 1
fi

mkdir -p "$CLAUDE_DIR"

echo "==> 下载 statusline 脚本到 $SCRIPT_PATH"
curl -fsSL "$REPO_RAW/statusline-command.sh" -o "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

echo "==> 写入 $SETTINGS_PATH"
if [ -f "$SETTINGS_PATH" ]; then
  cp "$SETTINGS_PATH" "$SETTINGS_PATH.bak"
  tmp=$(mktemp)
  jq '.statusLine = {"type":"command","command":"bash ~/.claude/statusline-command.sh"}' "$SETTINGS_PATH" > "$tmp"
  mv "$tmp" "$SETTINGS_PATH"
  echo "    已合并进现有配置(原文件已备份到 $SETTINGS_PATH.bak)"
else
  cat > "$SETTINGS_PATH" <<'JSON'
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
JSON
  echo "    已新建 settings.json"
fi

echo "==> 完成!重启 Claude Code(或新开一个会话)即可看到状态栏。"
