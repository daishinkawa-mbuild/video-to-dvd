# dvd-create.sh から source される変換・オーサリング・書き込みの関数群。

encode_mpeg() {
  local filter="scale=720:480:flags=lanczos,setdar=${ASPECT}"
  MPEG="$WORKDIR/video.mpg"
  if [ -n "$AUDIO_INDEX" ]; then
    ffmpeg -hide_banner -y -i "$INPUT" -map "0:${VIDEO_INDEX}" -map "0:${AUDIO_INDEX}" \
      -vf "$filter" -r 30000/1001 -fps_mode cfr -target ntsc-dvd -aspect "$ASPECT" \
      -pix_fmt yuv420p -b:v "${VIDEO_KBPS}k" -maxrate:v 9000k -minrate:v 0 \
      -c:a ac3 -b:a "${AUDIO_KBPS}k" -ar 48000 -ac 2 -map_metadata -1 -sn -dn \
      -af apad -shortest -max_muxing_queue_size 4096 "$MPEG"
  else
    # 音声なし入力には、DVD 規格で許容される無音 AC-3 を追加する。
    ffmpeg -hide_banner -y -i "$INPUT" -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
      -map "0:${VIDEO_INDEX}" -map 1:a:0 -vf "$filter" -r 30000/1001 -fps_mode cfr \
      -target ntsc-dvd -aspect "$ASPECT" -pix_fmt yuv420p -b:v "${VIDEO_KBPS}k" \
      -maxrate:v 9000k -minrate:v 0 -c:a ac3 -b:a "${AUDIO_KBPS}k" \
      -ar 48000 -ac 2 -map_metadata -1 -sn -dn -shortest -max_muxing_queue_size 4096 "$MPEG"
  fi
  [ -s "$MPEG" ] || die "DVD 用 MPEG-2 の生成に失敗しました。"
}

validate_encoded_mpeg() {
  printf '生成した MPEG-2 を全編デコード検査しています…\n'
  ffmpeg -hide_banner -loglevel error -xerror -i "$MPEG" \
    -map 0:v:0 -map 0:a:0 -f null - >/dev/null
}

author_dvd() {
  DVD_ROOT="$WORKDIR/dvd"
  mkdir -p "$DVD_ROOT/AUDIO_TS"
  # First Play ではタイトル番号で移動し、規格と画面比率を明示する。
  cat > "$WORKDIR/dvd.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<dvdauthor dest="dvd" format="ntsc">
  <vmgm>
    <fpc>jump title 1;</fpc>
  </vmgm>
  <titleset>
    <titles>
      <video format="ntsc" aspect="$ASPECT" resolution="720x480" />
      <audio format="ac3" channels="2" samplerate="48khz" />
      <pgc>
        <vob file="video.mpg" />
      </pgc>
    </titles>
  </titleset>
</dvdauthor>
EOF
  (cd "$WORKDIR" && dvdauthor -x dvd.xml)
  for required in VIDEO_TS.IFO VIDEO_TS.BUP VTS_01_0.IFO VTS_01_0.BUP; do
    [ -s "$DVD_ROOT/VIDEO_TS/$required" ] || die "DVD 構造に必要なファイルがありません: $required"
  done
  find "$DVD_ROOT/VIDEO_TS" -type f -name 'VTS_01_[1-9]*.VOB' -print -quit | grep -q . \
    || die "DVD 構造に本編 VOB がありません。"
}

make_iso() {
  # ISO の生成は cdrtools の mkisofs に固定し、DVD-Video 用の配置を任せる。
  local tool="mkisofs"
  # hdiutil は拡張子のない raw ISO を認識しないため、一時名も .iso にする。
  ISO_STAGE_DIR="$(mktemp -d "$(dirname "$OUTPUT_ISO")/.dvd-video.XXXXXX")"
  ISO_TEMP="$ISO_STAGE_DIR/dvd.iso"
  command -v mkisofs >/dev/null 2>&1 \
    || die "mkisofs が見つかりません。cdrtools を導入してください。"
  mkisofs -dvd-video -udf -V DVDVIDEO -o "$ISO_TEMP" "$DVD_ROOT"
  [ -s "$ISO_TEMP" ] || die "ISO の生成に失敗しました。"
  ISO_SIZE="$(file_size "$ISO_TEMP")"
  is_positive_integer "$ISO_SIZE" || die "ISO サイズを取得できません。"
  [ "$ISO_SIZE" -le "$MAX_ISO_BYTES" ] \
    || die "ISO が容量上限を超えています: ${ISO_SIZE} bytes > ${MAX_ISO_BYTES} bytes"
  # 検証に失敗した ISO で、既存の出力を置き換えない。
  validate_iso_file "$ISO_TEMP"
  if [ -e "$OUTPUT_ISO" ] && [ "$FORCE" -ne 1 ]; then
    die "検査中に出力先が作成されました。上書きせず中断します: $OUTPUT_ISO"
  fi
  mv "$ISO_TEMP" "$OUTPUT_ISO"
  ISO_TEMP=""
  rmdir "$ISO_STAGE_DIR"
  ISO_STAGE_DIR=""
  printf 'ISO 作成完了（%s, %s bytes）\n' "$tool" "$ISO_SIZE"
}

detach_iso() {
  if [ -n "${ISO_DEVICE:-}" ]; then
    hdiutil detach "$ISO_DEVICE" >/dev/null 2>&1 || return 1
  elif [ -n "${MOUNT_DIR:-}" ] && [ -d "$MOUNT_DIR" ]; then
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || return 1
  fi
  ISO_DEVICE=""; MOUNT_DIR=""
}

iso_die() {
  local message="$1"
  if ! detach_iso; then message="$message ISO のマウント解除にも失敗しました。"; fi
  die "$message"
}

burn_iso() {
  [ "$DO_BURN" -eq 1 ] || return 0
  printf '空の DVD-R をドライブに挿入してください。書き込みと検証を開始します。\n'
  hdiutil burn -forceclose -verifyburn -nosynthesize "$OUTPUT_ISO"
  printf 'DVD-R の書き込みとデータ検証が完了しました。対象プレイヤーで実機再生を確認してください。\n'
}

cleanup() {
  local status=$?
  if ! detach_iso; then
    printf '警告: ISO のマウント解除に失敗したため、一時ディレクトリを残します。\n' >&2
    KEEP_WORKDIR=1
  fi
  if [ "$KEEP_WORKDIR" -ne 1 ]; then
    if [ -n "${ISO_TEMP:-}" ] && [ -e "$ISO_TEMP" ]; then rm -f "$ISO_TEMP"; fi
    if [ -n "${ISO_STAGE_DIR:-}" ] && [ -d "$ISO_STAGE_DIR" ]; then rmdir "$ISO_STAGE_DIR"; fi
    if [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ]; then rm -rf "$WORKDIR"; fi
  fi
  exit "$status"
}
