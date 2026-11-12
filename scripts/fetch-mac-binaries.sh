#!/usr/bin/env bash
# 下载 macOS 打包需要的 yt-dlp 和 ffmpeg 到 vendor/mac/，并校验 SHA-256。
#   yt-dlp : 官方 GitHub release 的 yt-dlp_macos（universal，独立可执行）
#   ffmpeg : Martin Riedl 的 macOS 静态构建（ffmpeg.org 下载页列出的 macOS 构建来源）
set -euo pipefail

ARCH="$(uname -m)"           # arm64 或 x86_64
case "$ARCH" in
  arm64)  FF_ARCH=arm64 ;;
  x86_64) FF_ARCH=amd64 ;;
  *) echo "不支持的架构: $ARCH" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/vendor/mac"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

echo "==> yt-dlp_macos"
curl -fL --progress-bar -o "$TMP/yt-dlp_macos" \
  https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos
curl -fsSL -o "$TMP/SHA2-256SUMS" \
  https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS
( cd "$TMP" && grep ' yt-dlp_macos$' SHA2-256SUMS | shasum -a 256 -c - )
install -m 755 "$TMP/yt-dlp_macos" "$OUT/yt-dlp"

echo "==> ffmpeg + ffprobe ($FF_ARCH)"
# 从下载页取最新的正式版（目录名形如 <时间戳>_9.0.2，不要 N-xxxx 快照版）
FF_DIR="$(curl -fsSL https://ffmpeg.martin-riedl.de/ \
  | grep -oE "/download/macos/$FF_ARCH/[0-9]+_[0-9][0-9.]*/ffmpeg\.zip\"" \
  | tr -d '"' | sort -t/ -k5 -r | head -1 | sed 's#/ffmpeg\.zip$##')"
[ -n "$FF_DIR" ] || { echo "没找到 ffmpeg 正式版下载链接" >&2; exit 1; }

# ffmpeg 负责合并/转码；ffprobe 是 yt-dlp 提取音频（-x）时识别编码用的
for TOOL in ffmpeg ffprobe; do
  URL="https://ffmpeg.martin-riedl.de$FF_DIR/$TOOL.zip"
  echo "    $URL"
  curl -fL --progress-bar -o "$TMP/$TOOL.zip" "$URL"
  curl -fsSL -o "$TMP/$TOOL.zip.sha256" "$URL.sha256"
  EXPECTED="$(awk '{print $1}' "$TMP/$TOOL.zip.sha256")"
  ACTUAL="$(shasum -a 256 "$TMP/$TOOL.zip" | awk '{print $1}')"
  if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "$TOOL 校验失败: 期望 $EXPECTED 实际 $ACTUAL" >&2; exit 1
  fi
  unzip -o -q "$TMP/$TOOL.zip" -d "$TMP/$TOOL"
  install -m 755 "$TMP/$TOOL/$TOOL" "$OUT/$TOOL"
done

# 去掉下载隔离属性，避免打包后 Gatekeeper 拦截内置二进制
xattr -cr "$OUT" 2>/dev/null || true

echo "==> 完成"
file "$OUT/yt-dlp" "$OUT/ffmpeg" "$OUT/ffprobe"
