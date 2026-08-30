#!/usr/bin/env bash
# Claude Code statusline
# Layout: cwd: <path> | Model: <name> Thinking: <effort> | Ctx(u) Used: <pct>% (<实际大小>) Win: <窗口大小>

input=$(cat)

raw_cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(printf '%s' "$input" | jq -r '.model.display_name // "?"')
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty')
used_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
win_size=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // empty')
# used_percentage 就是按 total_input_tokens 算的(官方文档:input+cache_creation+cache_read),
# 这里取同一个字段,数字才跟百分比对得上
used_tokens=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // empty')

# 把 token 数格式化成简写(1000 -> 1.0K, 1000000 -> 1.0M)
format_size() {
  local n="$1"
  if [ -z "$n" ] || [ "$n" = "null" ]; then
    printf ''
    return
  fi
  awk -v n="$n" 'BEGIN {
    if (n >= 1000000) printf "%.1fM", n / 1000000;
    else if (n >= 1000) printf "%.1fK", n / 1000;
    else printf "%d", n;
  }'
}

win_fmt=$(format_size "$win_size")
used_tokens_fmt=$(format_size "$used_tokens")

# ANSI colors(加粗 + 高对比度,暗色/亮色终端背景都看得清;分隔符用灰色不抢视线)
RESET="\033[0m"
C_DIR="\033[1;36m"
C_MODEL="\033[1;35m"
C_THINK="\033[1;33m"
C_CTX="\033[1;32m"
C_SEP="\033[90m"

parts=()
parts+=("$(printf "${C_DIR}cwd: %s${RESET}" "$raw_cwd")")

model_part=$(printf "${C_MODEL}Model: %s${RESET}" "$model")
if [ -n "$effort" ] && [ "$effort" != "null" ]; then
  model_part="$model_part $(printf "${C_THINK}Thinking: %s${RESET}" "$effort")"
fi
parts+=("$model_part")

if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
  used_fmt=$(awk -v u="$used_pct" 'BEGIN { printf "%.1f", u }')
  if [ -n "$used_tokens_fmt" ]; then
    ctx_part=$(printf "${C_CTX}Ctx(u) Used: %s%% (%s)${RESET}" "$used_fmt" "$used_tokens_fmt")
  else
    ctx_part=$(printf "${C_CTX}Ctx(u) Used: %s%%${RESET}" "$used_fmt")
  fi
  if [ -n "$win_fmt" ]; then
    ctx_part="$ctx_part $(printf "${C_CTX}Win: %s${RESET}" "$win_fmt")"
  fi
  parts+=("$ctx_part")
fi

sep=$(printf " ${C_SEP}|${RESET} ")
output=""
for i in "${!parts[@]}"; do
  if [ "$i" -eq 0 ]; then
    output="${parts[$i]}"
  else
    output="${output}${sep}${parts[$i]}"
  fi
done

printf "%b" "$output"
