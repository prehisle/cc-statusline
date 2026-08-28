#!/usr/bin/env bash
# Claude Code statusline
# Layout: cwd: <path> | Model: <name> Thinking: <effort> | Ctx(u) Used: <pct>% Win: <size>

input=$(cat)

raw_cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(printf '%s' "$input" | jq -r '.model.display_name // "?"')
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty')
used_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
win_size=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // empty')

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

# Dim ANSI colors
RESET="\033[0m"
C_DIR="\033[2;36m"
C_MODEL="\033[2;35m"
C_THINK="\033[2;33m"
C_CTX="\033[2;32m"
C_SEP="\033[2;37m"

parts=()
parts+=("$(printf "${C_DIR}cwd: %s${RESET}" "$raw_cwd")")

model_part=$(printf "${C_MODEL}Model: %s${RESET}" "$model")
if [ -n "$effort" ] && [ "$effort" != "null" ]; then
  model_part="$model_part $(printf "${C_THINK}Thinking: %s${RESET}" "$effort")"
fi
parts+=("$model_part")

if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
  used_fmt=$(awk -v u="$used_pct" 'BEGIN { printf "%.1f", u }')
  ctx_part=$(printf "${C_CTX}Ctx(u) Used: %s%%${RESET}" "$used_fmt")
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
