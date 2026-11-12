#!/usr/bin/env bash
# 批量下载 B 站视频的原始音轨（m4a，不转码）到同一个文件夹。
#
# 用法：scripts/bili-batch-audio.sh <目标文件夹> [ID 列表文件]
#   ID 列表默认是 <目标文件夹>/_ids.txt，内容为空格或换行分隔的 BV 号。
#
# 直接存到 Google Drive（本地只临时放正在下载的那几首）：
#   DRIVE_DEST="gdrive:Music/歌单名" scripts/bili-batch-audio.sh <目标文件夹>
#   每下完一首就移到 Drive（核对 MD5 后删本地），Folia 在 ~/Music/GDrive/歌单名 里就能看到。
#   需要先配置好 rclone 的 gdrive（见 ~/Library/Application Support/rclone-gdrive/）。
#
# - 已下载的记录在 <目标文件夹>/_archive.txt，中断后重新运行会自动跳过，不会重复下载
#   （设了 DRIVE_DEST 时，本地没有 _archive.txt 会先从 Drive 取回，结束后再备份回 Drive）
# - 日志写到 <目标文件夹>/_download.<n>.log，错误汇总在 _errors.txt，上传日志在 _drive.log
# - 每个视频之间随机停 3–8 秒，降低触发 B 站风控的概率
# - 用 caffeinate 防止 Mac 睡眠导致下载中断
set -uo pipefail

DEST="${1:?用法: $0 <目标文件夹> [ID 列表文件]}"
IDS="${2:-$DEST/_ids.txt}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
YTDLP="$ROOT/vendor/mac/yt-dlp"
FFMPEG="$ROOT/vendor/mac/ffmpeg"

[ -x "$YTDLP" ] || { echo "缺少 ${YTDLP}，先运行 scripts/fetch-mac-binaries.sh" >&2; exit 1; }
[ -f "$IDS" ] || { echo "找不到 ID 列表: $IDS" >&2; exit 1; }
mkdir -p "$DEST"

# 可选：每下完一首就移到 Google Drive
DRIVE_DEST="${DRIVE_DEST:-}"
RCLONE=/opt/homebrew/bin/rclone
EXEC_ARGS=()
if [ -n "$DRIVE_DEST" ]; then
  [ -x "$RCLONE" ] || { echo "设了 DRIVE_DEST，但找不到 $RCLONE" >&2; exit 1; }
  export DRIVE_DEST
  # rclone 只连 Google，不能走 Folia 注入的大陆出口代理
  rclone_np() { env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy -u ALL_PROXY -u all_proxy "$RCLONE" "$@"; }
  rclone_np lsjson --max-depth 1 "${DRIVE_DEST%%:*}:" >/dev/null 2>&1 \
    || { echo "连不上 ${DRIVE_DEST%%:*}:，检查 rclone 授权和网络" >&2; exit 1; }
  # 本地没有下载记录时，从 Drive 取回，避免把已经在 Drive 上的歌重新下一遍
  if [ ! -f "$DEST/_archive.txt" ]; then
    rclone_np copy "$DRIVE_DEST/_archive.txt" "$DEST" 2>/dev/null \
      && echo "已从 Drive 取回 _archive.txt（$(wc -l < "$DEST/_archive.txt" | tr -d ' ') 条记录）"
  fi
  EXEC_ARGS=(--exec "after_move:$ROOT/scripts/drive-move.sh %(filepath)q")
  echo "下完的每一首会移到 $DRIVE_DEST"
fi

URLS="$DEST/_urls.txt"
tr -s ' \t\r' '\n' < "$IDS" | grep -E '^BV[0-9A-Za-z]{10}$' \
  | sed 's#^#https://www.bilibili.com/video/#' > "$URLS"
JOBS="${JOBS:-3}"   # 同时下载的数量，可用环境变量 JOBS=1 改成逐个下载
echo "共 $(wc -l < "$URLS" | tr -d ' ') 个视频 → ${DEST}（${JOBS} 个并行）"

# 防止 Mac 睡眠，直到本脚本结束（-w $$：脚本退出它就退出）
caffeinate -i -w $$ >/dev/null 2>&1 &

run_worker() {
  local n="$1"
  # 按行号轮流分给各个 worker
  awk -v n="$n" -v j="$JOBS" 'NR % j == n' "$URLS" > "$DEST/_urls.$n.txt"
  "$YTDLP" \
  --batch-file "$DEST/_urls.$n.txt" \
  --download-archive "$DEST/_archive.txt" \
  --paths "$DEST" \
  --output "%(title)s [%(id)s].%(ext)s" \
  --format "bestaudio[ext=m4a]/bestaudio" \
  --http-chunk-size 10M \
  --ffmpeg-location "$FFMPEG" \
  --embed-metadata \
  --embed-thumbnail \
  --sleep-interval 3 --max-sleep-interval 8 \
  --retries 10 --fragment-retries 10 \
  --ignore-errors \
  --no-overwrites --continue \
  --newline --no-progress \
  ${EXEC_ARGS[@]+"${EXEC_ARGS[@]}"} \
  >> "$DEST/_download.$n.log" 2>&1
}

pids=()
for ((i = 0; i < JOBS; i++)); do
  run_worker "$i" &
  pids+=($!)
done
# 只等下载 worker。不能用不带参数的 wait：它也会等上面的 caffeinate，
# 而 caffeinate 在等本脚本退出，两边互等，脚本永远停在这里。
wait "${pids[@]}"

done_count=$(wc -l < "$DEST/_archive.txt" 2>/dev/null | tr -d ' ')
echo "完成：已下载 ${done_count:-0} 个。失败的可以直接重新运行本脚本重试。"
grep -h "^ERROR" "$DEST"/_download.*.log > "$DEST/_errors.txt" 2>/dev/null || true

if [ -n "$DRIVE_DEST" ]; then
  # 补传：逐首上传时失败、留在本地的文件。跳过下载记录（_*）和没下完的临时文件。
  echo "补传留在本地的文件到 $DRIVE_DEST …"
  rclone_np move "$DEST" "$DRIVE_DEST" \
    --exclude "_*" --exclude ".DS_Store" \
    --exclude "*.part" --exclude "*.part-Frag*" --exclude "*.ytdl" --exclude "*.temp.*" \
    --retries 5 --log-level NOTICE --log-file "$DEST/_drive.log"
  # 下载记录备份到 Drive，换电脑或删了本地文件夹也能接着下
  rclone_np copy "$DEST/_archive.txt" "$DRIVE_DEST" 2>/dev/null || true
  left=$(find "$DEST" -maxdepth 1 -type f ! -name '_*' ! -name '.DS_Store' \
    ! -name '*.part' ! -name '*.part-Frag*' ! -name '*.ytdl' ! -name '*.temp.*' | wc -l | tr -d ' ')
  partial=$(find "$DEST" -maxdepth 1 -type f \( -name '*.part' -o -name '*.part-Frag*' -o -name '*.ytdl' \) | wc -l | tr -d ' ')
  echo "本地还剩 $left 个下完但没传上去的文件（0 才算全部在 Drive 上），$partial 个没下完的临时文件（重新运行本脚本会接着下）。详见 $DEST/_drive.log"
fi
