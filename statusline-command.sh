#!/usr/bin/env bash
# Claude Code statusline
# Layout: <path> | <model> [<effort>] | [进度条] <已用>/<窗口大小> (<pct>%)
# 精简形:去掉 "cwd:"/"Model:"/"Thinking:"/"Ctx(u) Used:" 这类文字标签,
# 靠位置 + 颜色区分三段,给窄终端窗口省字数。

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

# 路径太长时只留最后两段,前面补 "..."(阈值可用 CC_STATUSLINE_PATH_MAX 覆盖)
# ⚠ 纯 bash 实现,别改用 awk -v 传这个值——awk 的 -v/命令行赋值会按字符串字面量
# 规则处理转义,Windows 路径里的 "\U" "\p" 这类反斜杠+字母会被当成非法转义吞掉
# 反斜杠(真实栽过、每个反斜杠都会消失)。
shorten_path() {
  local p="$1"
  local max_len="${CC_STATUSLINE_PATH_MAX:-40}"
  if [ -z "$p" ] || [ "${#p}" -le "$max_len" ]; then
    printf '%s' "$p"
    return
  fi
  local sep='/'
  case "$p" in
    *'\'*) sep='\' ;;
  esac
  local -a segs
  IFS="$sep" read -r -a segs <<< "$p"
  local n="${#segs[@]}"
  if [ "$n" -gt 0 ] && [ -z "${segs[$((n-1))]}" ]; then
    n=$((n-1))
  fi
  if [ "$n" -le 2 ]; then
    printf '%s' "$p"
    return
  fi
  printf '...%s%s%s%s' "$sep" "${segs[$((n-2))]}" "$sep" "${segs[$((n-1))]}"
}

# 画进度条,长度可用 CC_STATUSLINE_BAR_LEN 覆盖(默认 10 格)
draw_bar() {
  local pct="$1"
  local len="${CC_STATUSLINE_BAR_LEN:-10}"
  local filled
  filled=$(awk -v p="$pct" -v l="$len" 'BEGIN {
    n = int(p / 100 * l + 0.5)
    if (n < 0) n = 0
    if (n > l) n = l
    print n
  }')
  local empty=$((len - filled))
  local bar="" i
  for ((i = 0; i < filled; i++)); do bar+="▓"; done
  for ((i = 0; i < empty; i++)); do bar+="░"; done
  printf '%s' "$bar"
}

dir_fmt=$(shorten_path "$raw_cwd")
win_fmt=$(format_size "$win_size")
used_tokens_fmt=$(format_size "$used_tokens")

# ANSI colors(加粗 + 高对比度,暗色/亮色终端背景都看得清;分隔符用灰色不抢视线)
# ⚠ 用 $'...' 让变量里直接装真实的 ESC 字节,别再写成 "\033" 这种文本反斜杠——
# 本脚本最终要靠 printf '%s' 原样吐出整段(含用户路径里的真实反斜杠),
# 如果这里存的是文本反斜杠就得靠 printf '%b' 才能变成颜色,而 %b 会把路径里
# 任意的 "\c" "\t" 这类反斜杠+字母也当转义指令解释掉,真实栽过(反斜杠+c 触发
# printf 的"到此为止"指令,整条状态栏被从中间截断且不报错)。
RESET=$'\033[0m'
C_DIR=$'\033[1;36m'
C_MODEL=$'\033[1;35m'
C_THINK=$'\033[1;33m'
C_CTX=$'\033[1;32m'
C_SEP=$'\033[90m'

parts=()
parts+=("$(printf "${C_DIR}%s${RESET}" "$dir_fmt")")

model_part=$(printf "${C_MODEL}%s${RESET}" "$model")
if [ -n "$effort" ] && [ "$effort" != "null" ]; then
  model_part="$model_part $(printf "${C_THINK}[%s]${RESET}" "$effort")"
fi
parts+=("$model_part")

if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
  used_fmt=$(awk -v u="$used_pct" 'BEGIN { printf "%d", u + 0.5 }')
  bar=$(draw_bar "$used_pct")
  if [ -n "$used_tokens_fmt" ] && [ -n "$win_fmt" ]; then
    frac="$used_tokens_fmt/$win_fmt"
  elif [ -n "$win_fmt" ]; then
    frac="$win_fmt"
  else
    frac=""
  fi
  if [ -n "$frac" ]; then
    ctx_part=$(printf "${C_CTX}[%s] %s (%s%%)${RESET}" "$bar" "$frac" "$used_fmt")
  else
    ctx_part=$(printf "${C_CTX}[%s] %s%%${RESET}" "$bar" "$used_fmt")
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

printf '%s' "$output"
