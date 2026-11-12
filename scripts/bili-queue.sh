#!/usr/bin/env bash
# 按顺序下载多个 UP 主，下完的歌直接放进 Google Drive 的 Music/<文件夹名>。
#
# 用法：scripts/bili-queue.sh <文件夹1> <文件夹2> ...
#   每个文件夹里先放好 _ids.txt（BV 号列表），文件夹名就是 Drive 上的歌单名。
#   进度写到 ~/Downloads/Videdown/_queue.log，每个 UP 主自己的日志在各自文件夹的 _run.out。
#
# - 一次只下一个 UP 主（每个内部 3 个并行），同时开太多连接容易触发 B 站风控
# - 开始前先等正在跑的 bili-batch-audio.sh 结束
# - 中途断了，用同样的参数重新运行即可：已下载的会按 _archive.txt 跳过
set -uo pipefail
# 变量紧挨中文时一律写成 ${var}：C 语言环境下的 bash 3.2 会把中文字节当成变量名的一部分（2026-11-10 踩过）
export LANG="${LANG:-en_US.UTF-8}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$HOME/Downloads/Videdown/_queue.log"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# 防止 Mac 睡眠，直到本脚本结束。后面不用不带参数的 wait，所以不会和它互等。
caffeinate -i -w $$ >/dev/null 2>&1 &

log "队列开始：$*"
while pgrep -f "bili-batch-audio.sh" >/dev/null; do sleep 60; done

for D in "$@"; do
  name="$(basename "$D")"
  if [ ! -f "$D/_ids.txt" ]; then log "跳过 ${name}：没有 _ids.txt"; continue; fi
  log "开始 ${name}（$(tr -s ' \n' '\n' < "$D/_ids.txt" | grep -c '^BV') 个视频）"
  DRIVE_DEST="gdrive:Music/${name}" bash "$ROOT/scripts/bili-batch-audio.sh" "$D" > "$D/_run.out" 2>&1 < /dev/null
  log "结束 ${name}：已下载 $(wc -l < "$D/_archive.txt" 2>/dev/null | tr -d ' ') 个，报错 $(cat "$D/_errors.txt" 2>/dev/null | wc -l | tr -d ' ') 行；$(tail -1 "$D/_run.out")"
done
log "队列全部完成"
