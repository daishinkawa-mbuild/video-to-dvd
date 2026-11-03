# DVD の再生制御情報と本編を検査し、書き込み可能な ISO だけを受け入れる。

# IFO の識別子・セクタ境界と、バックアップの完全一致を確認する。
validate_ifo_pair() {
  local path="$1" magic="$2" size signature
  [ -f "$path" ] && [ -s "$path" ] || iso_die "IFO がありません: $path"
  size="$(file_size "$path")"
  [ "$size" -ge 2048 ] && [ $((size % 2048)) -eq 0 ] \
    || iso_die "IFO のサイズが DVD のセクタ境界と一致しません: $path"
  signature="$(dd if="$path" bs=12 count=1 2>/dev/null)"
  [ "$signature" = "$magic" ] || iso_die "IFO の識別子が不正です: $path"
  cmp -s "$path" "${path%.IFO}.BUP" \
    || iso_die "IFO と BUP が一致しません: $path"
}

# 分割 VOB ごとに映像・音声の規格を確認し、途中だけ方式が変わる入力も拒否する。
validate_vob_format() {
  local path="$1" video audio field expected_dar="$2"
  video="$(ffprobe -v error -select_streams v:0 -of default=nw=1 \
    -show_entries stream=codec_name,width,height,pix_fmt,r_frame_rate,display_aspect_ratio "$path")" \
    || iso_die "VOB の映像を検査できません: $path"
  audio="$(ffprobe -v error -select_streams a:0 -of default=nw=1 \
    -show_entries stream=codec_name,sample_rate,channels "$path")" \
    || iso_die "VOB の音声を検査できません: $path"
  for field in codec_name=mpeg2video width=720 height=480 pix_fmt=yuv420p \
    r_frame_rate=30000/1001 "display_aspect_ratio=$expected_dar"; do
    printf '%s\n' "$video" | grep -qx "$field" \
      || iso_die "VOB の映像が NTSC DVD の設定と異なります（$field）: $path"
  done
  for field in codec_name=ac3 sample_rate=48000 channels=2; do
    printf '%s\n' "$audio" | grep -qx "$field" \
      || iso_die "VOB の音声が AC-3/48kHz/2ch ではありません: $path"
  done
}

# libdvdread で IFO 内のテーブルと参照先を解析し、単一タイトルを取り出せることを確認する。
validate_navigation() {
  local root="$1" inspect_dir xml vob
  inspect_dir="$(mktemp -d "$WORKDIR/navigation.XXXXXX")"
  if ! (cd "$inspect_dir" && dvdunauthor "$root" >decode.log 2>&1); then
    cat "$inspect_dir/decode.log" >&2
    iso_die "DVD の再生制御情報を解析できません。"
  fi
  # libdvdread は IFO の異常を報告しても終了コード 0 を返す場合がある。
  if grep -Eiq '((^|[[:space:]])ERR:|CHECK_VALUE|Invalid IFO|failed to read|Can.t read)' "$inspect_dir/decode.log"; then
    cat "$inspect_dir/decode.log" >&2
    iso_die "DVD の解析中に再生制御情報の異常が見つかりました。"
  fi
  xml="$inspect_dir/dvdauthor.xml"
  [ -s "$xml" ] && xmllint --noout --nonet "$xml" 2>/dev/null \
    || iso_die "DVD の再生制御情報を XML として復元できません。"
  [ "$(xmllint --xpath 'count(/dvdauthor/titleset)' "$xml")" = 1 ] \
    && [ "$(xmllint --xpath 'count(/dvdauthor/titleset/titles/pgc)' "$xml")" = 1 ] \
    && [ "$(xmllint --xpath 'count(/dvdauthor/vmgm/menus/pgc | /dvdauthor/titleset/menus/pgc)' "$xml")" = 0 ] \
    || iso_die "このスクリプトでは単一タイトルの DVD だけを書き込めます。"
  [ "$(xmllint --xpath 'normalize-space(/dvdauthor/vmgm/fpc)' "$xml")" = 'jump title 1;' ] \
    && [ "$(xmllint --xpath 'normalize-space(/dvdauthor/titleset/titles/pgc/post)' "$xml")" = 'exit;' ] \
    && [ -z "$(xmllint --xpath 'normalize-space(/dvdauthor/titleset/titles/pgc/pre)' "$xml")" ] \
    || iso_die "DVD の再生制御が本編の自動再生・末尾停止になっていません。"
  # ライブラリが終了コードを返さず失敗する場合も、実データの抽出を必須にする。
  find "$inspect_dir" -type f -name '*.vob' -size +0c -print | grep -q . \
    || iso_die "再生制御情報が本編の映像データを参照していません。"
  # IFO が参照する抽出データもデコードし、参照先の破損を検出する。
  for vob in "$inspect_dir"/*.vob; do
    [ -s "$vob" ] || iso_die "再生制御情報が空の映像を参照しています。"
    ffmpeg -hide_banner -loglevel error -xerror -err_detect explode \
      -i "$vob" -map 0:v:0 -map 0:a:0 -f null - >/dev/null \
      || iso_die "IFO が参照する映像データをデコードできません。"
  done
}

# 本編の分割番号とセクタを確認し、VOB を連結して全編デコードする。
validate_title_vobs() {
  local video_dir="$1" path size expected=1 dar
  local vobs=()
  for path in "$video_dir"/VTS_01_[1-9].VOB; do
    [ -f "$path" ] || iso_die "本編 VOB がありません。"
    [ "$(basename "$path")" = "VTS_01_${expected}.VOB" ] \
      || iso_die "本編 VOB の分割番号が連続していません。"
    size="$(file_size "$path")"
    [ "$size" -gt 0 ] && [ "$size" -le 1073741824 ] && [ $((size % 2048)) -eq 0 ] \
      || iso_die "VOB のサイズが DVD の規定と異なります: $path"
    if [ "$expected" -eq 1 ]; then
      dar="$(ffprobe -v error -select_streams v:0 -of default=nw=1:nk=1 \
        -show_entries stream=display_aspect_ratio "$path" | sed -n '1p')"
      case "$dar" in 16:9|4:3) ;; *) iso_die "VOB の画面比率が 16:9/4:3 ではありません。" ;; esac
    fi
    validate_vob_format "$path" "$dar"
    vobs+=("$path")
    expected=$((expected + 1))
  done
  printf 'ISO 内の本編 VOB を全編デコード検査しています…\n'
  if ! cat "${vobs[@]}" | ffmpeg -hide_banner -loglevel error -xerror -err_detect explode \
    -i pipe:0 -map 0:v:0 -map 0:a:0 -f null - >/dev/null; then
    iso_die "ISO 内の本編を最後までデコードできません。"
  fi
}

# imageinfo の終了コードには依存せず、実際の読み取り専用マウントと内容を検証する。
validate_iso_file() {
  local iso="$1" attach_output attach_status=0 video_dir count
  ISO_SIZE="$(file_size "$iso")"
  is_positive_integer "$ISO_SIZE" && [ "$ISO_SIZE" -le "$MAX_ISO_BYTES" ] \
    || die "ISO が空、または容量上限を超えています。"
  MOUNT_DIR="$WORKDIR/iso-mount"
  mkdir -p "$MOUNT_DIR"
  attach_output="$(hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$iso" 2>&1)" \
    || attach_status=$?
  ISO_DEVICE="$(printf '%s\n' "$attach_output" | awk '$1 ~ /^\/dev\/disk/ { print $1; exit }')"
  if [ "$attach_status" -ne 0 ]; then
    # 接続前の失敗なら detach を呼ばない。デバイスだけ接続された場合は cleanup に任せる。
    [ -n "$ISO_DEVICE" ] || MOUNT_DIR=""
    die "ISO を読み取り専用でマウントできません: $attach_output"
  fi
  video_dir="$MOUNT_DIR/VIDEO_TS"
  [ -d "$video_dir" ] && [ -d "$MOUNT_DIR/AUDIO_TS" ] \
    || iso_die "ISO 直下に VIDEO_TS と AUDIO_TS がありません。"
  count="$(find "$video_dir" -name 'VTS_[0-9][0-9]_0.IFO' -type f | wc -l | tr -d ' ')"
  [ "$count" = 1 ] || iso_die "このスクリプトでは単一タイトルセットだけを書き込めます。"
  validate_ifo_pair "$video_dir/VIDEO_TS.IFO" DVDVIDEO-VMG
  validate_ifo_pair "$video_dir/VTS_01_0.IFO" DVDVIDEO-VTS
  validate_navigation "$MOUNT_DIR"
  validate_title_vobs "$video_dir"
  detach_iso || die "ISO のマウントを解除できません。"
  printf 'ISO の構造・再生制御情報・本編の検査が完了しました。\n'
}
