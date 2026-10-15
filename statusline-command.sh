#!/usr/bin/env bash
# Claude Code statusline
# Layout: <path> (<git 分支>) | <model> [<effort>] | [进度条] <已用>/<窗口大小> (<pct>%) | sess $.. | 5h ... | 7d ...
# 精简形:去掉 "cwd:"/"Model:"/"Thinking:"/"Ctx(u) Used:" 这类文字标签,
# 靠位置 + 颜色区分各段,给窄终端窗口省字数。

input=$(cat)

# 一次 jq 把所有字段取出来(每起一次 jq 都要几十毫秒),用 \x1f 分隔——不能用 tab,
# read 会把连续的空白分隔符并成一个,空字段就错位了。
# used_percentage 就是按 total_input_tokens 算的(官方文档:input+cache_creation+cache_read),
# 取同一个字段,数字才跟百分比对得上。
# cost.total_cost_usd 是 Claude Code 自己算的本会话花费。
# rate_limits 是 5 小时限额 / 周限额,只有订阅账号、且会话里发过第一条请求后才有。
IFS=$'\x1f' read -r raw_cwd model effort used_pct win_size used_tokens h5_pct h5_reset d7_pct d7_reset sess_cost <<< "$(
  printf '%s' "$input" | jq -r '[
    .workspace.current_dir // .cwd // "",
    .model.display_name // "?",
    .effort.level // "",
    .context_window.used_percentage // "",
    .context_window.context_window_size // "",
    .context_window.total_input_tokens // "",
    .rate_limits.five_hour.used_percentage // "",
    .rate_limits.five_hour.resets_at // "",
    .rate_limits.seven_day.used_percentage // "",
    .rate_limits.seven_day.resets_at // "",
    .cost.total_cost_usd // ""
  ] | map(tostring) | join("\u001f")'
)"

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

# reset 时间(Unix 秒,或 ISO 字符串)统一成 Unix 秒;解析失败就返回空
to_epoch() {
  local ts="$1"
  case "$ts" in
    '') return ;;
    # 不用 date -d:那是 GNU 独有,macOS 的 BSD date 不认
    *[!0-9]*) jq -rn --arg t "$ts" '$t | sub("\\.[0-9]+"; "") | fromdateiso8601' 2>/dev/null ;;
    *) printf '%s' "$ts" ;;
  esac
}

# 把 reset 时间换算成还剩多久:3d4h / 2h13m / 45m
format_reset() {
  local ts="$1"
  [ -z "$ts" ] && return
  local left=$((ts - $(date +%s)))
  [ "$left" -lt 0 ] && left=0
  local d=$((left / 86400)) h=$((left % 86400 / 3600)) m=$((left % 3600 / 60))
  if [ "$d" -gt 0 ]; then
    printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then
    printf '%dh%dm' "$h" "$m"
  else
    printf '%dm' "$m"
  fi
}

# 统计本机 transcript 在当前 5h / 7d 窗口内的用量,按官方 API 标价折成美元,输出 "<5h> <7d>"。
# 窗口起点 = reset 时间往前推 5 小时 / 7 天;流式分片会把同一条消息写多行,按 message.id+requestId 去重取最后一行。
# 单价($/MTok,输入/输出/缓存读):缓存写 5m = 输入 x1.25,1h = 输入 x2;表里没有的模型不计价。
# ⚠ 只算得到本机 Claude Code 的 transcript,别的设备 / claude.ai 的用量不在里面,所以跟百分比不是严格对应。
# 扫一遍 transcript 不便宜,结果缓存 CC_STATUSLINE_COST_TTL 秒(默认 30)。
window_costs() {
  local h5_reset="$1" d7_reset="$2"
  [ -z "$h5_reset$d7_reset" ] && return
  local now cache_dir cache_file
  now=$(date +%s)
  cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/cc-statusline"
  cache_file="$cache_dir/cost"
  if [ -f "$cache_file" ]; then
    local c_time c_h5r c_d7r c_h5 c_d7
    read -r c_time c_h5r c_d7r c_h5 c_d7 < "$cache_file"
    if [ "$c_h5r" = "${h5_reset:--}" ] && [ "$c_d7r" = "${d7_reset:--}" ] \
      && [ $((now - ${c_time:-0})) -lt "${CC_STATUSLINE_COST_TTL:-30}" ]; then
      printf '%s %s' "$c_h5" "$c_d7"
      return
    fi
  fi
  local oldest="$now"
  [ -n "$h5_reset" ] && oldest=$((h5_reset - 18000))
  [ -n "$d7_reset" ] && oldest=$((d7_reset - 604800))
  local mmin=$(((now - oldest) / 60 + 1))
  [ "$mmin" -lt 1 ] && mmin=1
  local res
  res=$(find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" -name '*.jsonl' -mmin "-$mmin" -exec cat {} + 2>/dev/null \
    | jq -nRr --arg h5e "$h5_reset" --arg d7e "$d7_reset" '
      def price:
        if test("fable-5-1|mythos-5-1") then {i: 10, o: 50, r: 0.25}
        elif test("fable-5|mythos-5") then {i: 10, o: 50, r: 1}
        elif test("opus-5-5") then {i: 4, o: 20, r: 0.2}
        elif test("opus-5|opus-4-8|opus-4-7|opus-4-6") then {i: 5, o: 25, r: 0.5}
        elif test("sonnet-5") then {i: 2, o: 10, r: 0.2}
        elif test("sonnet-4-6") then {i: 3, o: 15, r: 0.3}
        elif test("haiku-5-5") then {i: 0.1, o: 0.5, r: 0.01}
        elif test("haiku-4-5") then {i: 1, o: 5, r: 0.1}
        else null end;
      def cost:
        (.m | price) as $p
        | if $p == null then 0 else
            .u as $u
            | ($u.input_tokens // 0) as $in
            | ($u.cache_read_input_tokens // 0) as $rd
            | ($u.cache_creation.ephemeral_1h_input_tokens // 0) as $w1
            | (if $u.cache_creation then ($u.cache_creation.ephemeral_5m_input_tokens // 0)
               else ($u.cache_creation_input_tokens // 0) end) as $w5
            # Haiku 5.5 的 prompt 超过 100K 整条按 5 倍价;Opus 5 / 5.5 fast mode 是 2 倍价
            | (if (.m | test("haiku-5-5")) and ($in + $rd + $w1 + $w5) > 100000 then 5
               elif $u.speed == "fast" and (.m | test("opus-5")) then 2
               else 1 end) as $k
            | ($in * $p.i + $w5 * $p.i * 1.25 + $w1 * $p.i * 2 + $rd * $p.r
               + ($u.output_tokens // 0) * $p.o) * $k / 1000000
          end;
      # 窗口起点转成 UTC ISO 串(去掉末尾 Z)跟 timestamp 按字典序比;在 jq 里转,不依赖 GNU date。
      # 没有的窗口起点设成 "9",比任何时间戳都大,自然累计为 0
      def start($e; $len): if $e == "" then "9" else ($e | tonumber - $len | todate | .[:-1]) end;
      start($h5e; 18000) as $h5 | start($d7e; 604800) as $d7 |
      reduce (inputs | fromjson?
              | select(.type == "assistant" and .message.usage != null
                       and .timestamp >= ([$h5, $d7] | min))) as $e
        ({}; .[($e.message.id // $e.uuid // "") + ":" + ($e.requestId // "")]
               = {t: $e.timestamp, m: ($e.message.model // ""), u: $e.message.usage})
      | reduce .[] as $x ({h5: 0, d7: 0};
          ($x | cost) as $c
          | (if $x.t >= $d7 then .d7 += $c else . end)
          | (if $x.t >= $h5 then .h5 += $c else . end))
      | "\(.h5) \(.d7)"' 2>/dev/null)
  [ -z "$res" ] && return
  mkdir -p "$cache_dir" 2>/dev/null \
    && printf '%s %s %s %s\n' "$now" "${h5_reset:--}" "${d7_reset:--}" "$res" > "$cache_file.$$" 2>/dev/null \
    && mv -f "$cache_file.$$" "$cache_file" 2>/dev/null
  printf '%s' "$res"
}

# 拼一段限额:<标签> <pct>% $<本机用量> ↻<还剩多久>,没有百分比就整段不出
limit_part() {
  local label="$1" pct="$2" reset="$3" cost="$4"
  [ -z "$pct" ] && return
  local out reset_fmt
  out=$(awk -v l="$label" -v u="$pct" 'BEGIN { printf "%s %d%%", l, u + 0.5 }')
  [ -n "$cost" ] && out="$out $(awk -v c="$cost" 'BEGIN { printf "$%.2f", c }')"
  reset_fmt=$(format_reset "$reset")
  [ -n "$reset_fmt" ] && out="$out ↻$reset_fmt"
  printf '%s' "$out"
}

# 当前目录所在仓库的 git 分支;游离 HEAD 时退化成短 commit 号,不在仓库里就返回空。
# CC_STATUSLINE_GIT=0 可以关掉。
git_branch() {
  local dir="$1"
  [ "${CC_STATUSLINE_GIT:-1}" = "0" ] && return
  [ -z "$dir" ] && return
  git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null \
    || git -C "$dir" rev-parse --short HEAD 2>/dev/null
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
C_LIMIT=$'\033[1;94m'
C_GIT=$'\033[1;33m'
C_WARN=$'\033[1;31m'
C_SEP=$'\033[90m'

parts=()
dir_part=$(printf "${C_DIR}%s${RESET}" "$dir_fmt")
branch=$(git_branch "$raw_cwd")
[ -n "$branch" ] && dir_part="$dir_part $(printf "${C_GIT}(%s)${RESET}" "$branch")"
parts+=("$dir_part")

model_part=$(printf "${C_MODEL}%s${RESET}" "$model")
if [ -n "$effort" ] && [ "$effort" != "null" ]; then
  model_part="$model_part $(printf "${C_THINK}[%s]${RESET}" "$effort")"
fi
parts+=("$model_part")

if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
  used_fmt=$(awk -v u="$used_pct" 'BEGIN { printf "%d", u + 0.5 }')
  bar=$(draw_bar "$used_pct")
  # 上下文用量达到阈值(默认 80%,可用 CC_STATUSLINE_CTX_WARN 覆盖)就换成红色
  ctx_color="$C_CTX"
  awk -v u="$used_pct" -v w="${CC_STATUSLINE_CTX_WARN:-80}" 'BEGIN { exit !(u + 0 >= w + 0) }' \
    && ctx_color="$C_WARN"
  if [ -n "$used_tokens_fmt" ] && [ -n "$win_fmt" ]; then
    frac="$used_tokens_fmt/$win_fmt"
  elif [ -n "$win_fmt" ]; then
    frac="$win_fmt"
  else
    frac=""
  fi
  if [ -n "$frac" ]; then
    ctx_part=$(printf "${ctx_color}[%s] %s (%s%%)${RESET}" "$bar" "$frac" "$used_fmt")
  else
    ctx_part=$(printf "${ctx_color}[%s] %s%%${RESET}" "$bar" "$used_fmt")
  fi
  parts+=("$ctx_part")
fi

# 限额用量达到阈值(默认 80%,可用 CC_STATUSLINE_LIMIT_WARN 覆盖)就换成红色
limit_color() {
  awk -v u="$1" -v w="${CC_STATUSLINE_LIMIT_WARN:-80}" 'BEGIN { exit !(u + 0 >= w + 0) }' \
    && printf '%s' "$C_WARN" || printf '%s' "$C_LIMIT"
}

# 本会话花费,直接用 Claude Code 给的数;跟下面两段的金额一样受 CC_STATUSLINE_COST=0 控制
if [ "${CC_STATUSLINE_COST:-1}" != "0" ] && [ -n "$sess_cost" ]; then
  parts+=("$(printf "${C_LIMIT}%s${RESET}" "$(awk -v c="$sess_cost" 'BEGIN { printf "sess $%.2f", c }')")")
fi

# 限额两段:输入里有 rate_limits 才出(订阅账号才有),CC_STATUSLINE_LIMITS=0 可以整个关掉;
# 不出的时候连 transcript 也不扫
if [ "${CC_STATUSLINE_LIMITS:-1}" != "0" ] && [ -n "$h5_pct$d7_pct" ]; then
  h5_reset=$(to_epoch "$h5_reset")
  d7_reset=$(to_epoch "$d7_reset")
  # 美元用量可以用 CC_STATUSLINE_COST=0 单独关掉(关掉后不扫 transcript)
  h5_cost="" d7_cost=""
  if [ "${CC_STATUSLINE_COST:-1}" != "0" ]; then
    read -r h5_cost d7_cost <<< "$(window_costs "$h5_reset" "$d7_reset")"
  fi
  h5_part=$(limit_part "5h" "$h5_pct" "$h5_reset" "$h5_cost")
  [ -n "$h5_part" ] && parts+=("$(printf "%s%s${RESET}" "$(limit_color "$h5_pct")" "$h5_part")")
  d7_part=$(limit_part "7d" "$d7_pct" "$d7_reset" "$d7_cost")
  [ -n "$d7_part" ] && parts+=("$(printf "%s%s${RESET}" "$(limit_color "$d7_pct")" "$d7_part")")
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
