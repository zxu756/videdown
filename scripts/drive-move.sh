#!/bin/sh
# 由 bili-batch-audio.sh 通过 yt-dlp --exec 调用：每下完一首（元数据和封面都嵌好之后），
# 把这个文件移到 Google Drive 的 $DRIVE_DEST，并核对大小和 MD5，成功后删除本地文件。
#
# 用法：DRIVE_DEST=gdrive:Music/某歌单 drive-move.sh <文件>
#
# 永远返回 0：上传失败时文件留在本地，bili-batch-audio.sh 结束时会再统一补传一次。
# 如果这里返回非 0，yt-dlp 会把这一首当成失败、不记进 _archive.txt，下次会重复下载。

# Folia 的 proxy-env 可能往环境里塞了大陆出口代理，那条路连不上 Google。
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy

f="$1"
[ -n "${DRIVE_DEST:-}" ] || exit 0
[ -f "$f" ] || exit 0

/opt/homebrew/bin/rclone move "$f" "$DRIVE_DEST" \
  --retries 5 \
  --log-level NOTICE \
  --log-file "$(dirname "$f")/_drive.log" \
  || echo "$(date '+%F %T') 上传失败，留在本地: $f" >> "$(dirname "$f")/_drive.log"
exit 0
