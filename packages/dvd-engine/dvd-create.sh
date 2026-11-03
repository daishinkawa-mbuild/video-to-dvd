#!/usr/bin/env bash
# DVD-Video の入力検査、変換、オーサリング、ISO 作成をまとめて実行する。
set -Eeuo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEFAULT_MAX_ISO_BYTES=4200000000
readonly DEFAULT_VIDEO_KBPS=6000
readonly AUDIO_KBPS=192
MAX_ISO_BYTES="${DVD_MAX_ISO_BYTES:-$DEFAULT_MAX_ISO_BYTES}"
VIDEO_KBPS="${DVD_VIDEO_KBPS:-$DEFAULT_VIDEO_KBPS}"
ASPECT="auto"
INPUT=""
OUTPUT_ISO=""
BURN_ISO=""
DO_BURN=0
KEEP_WORKDIR=0
FORCE=0
WORKDIR=""

# 入力検査と実行パイプラインを責務ごとに分割し、保守時の変更範囲を限定する。
# shellcheck source=dvd-input.sh
source "$SCRIPT_DIR/dvd-input.sh"
# shellcheck source=dvd-pipeline.sh
source "$SCRIPT_DIR/dvd-pipeline.sh"
# shellcheck source=dvd-verify.sh
source "$SCRIPT_DIR/dvd-verify.sh"

main() {
  parse_options "$@"
  validate_max_bytes
  # 作成済み ISO も、再生制御情報の解析と全編デコードを終えてから書き込む。
  for tool in hdiutil ffmpeg ffprobe dvdunauthor xmllint; do
    require_command "$tool"
  done
  if [ -n "$BURN_ISO" ]; then
    [ -z "$INPUT" ] || die "--burn-iso と入力動画は同時に指定できません。"
    normalise_burn_iso_path
    WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/dvd-video.XXXXXX")"
    trap cleanup EXIT
    validate_iso_file "$OUTPUT_ISO"
    DO_BURN=1
    burn_iso
    exit 0
  fi
  normalise_input_path
  normalise_output_path
  validate_max_bytes
  is_positive_integer "$VIDEO_KBPS" || die "--video-bitrate は正の整数です。"
  [ "$VIDEO_KBPS" -ge 1000 ] && [ "$VIDEO_KBPS" -le 8500 ] \
    || die "--video-bitrate は 1000〜8500 KBPS です。"

  require_command dvdauthor
  require_iso_tool
  select_streams
  validate_input

  WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/dvd-video.XXXXXX")"
  trap cleanup EXIT
  printf '入力: %s\n方式: NTSC / MPEG-2 / %s / %s kbps\n' \
    "$INPUT" "$ASPECT" "$VIDEO_KBPS"
  encode_mpeg
  validate_encoded_mpeg
  author_dvd
  make_iso
  burn_iso
  printf '完了: %s\n' "$OUTPUT_ISO"
}

main "$@"
