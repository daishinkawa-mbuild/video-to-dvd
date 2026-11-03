# dvd-create.sh から source される入力検査・オプション処理の関数群。

usage() {
  cat <<'EOF'
使い方:
  dvd-create.sh [オプション] 入力動画.mp4

オプション:
  --output PATH          出力 ISO のパス（既定: 入力名.dvd.iso）
  --aspect auto|16:9|4:3 映像方式（既定: DAR から自動判定）
  --video-bitrate KBPS   MPEG-2 映像ビットレート（既定: 6000、1000〜8500）
  --max-bytes BYTES      ISO 容量上限（既定: 4200000000、最大: 4700000000）
  --burn                 ISO 作成後に hdiutil で DVD-R を書き込む
  --burn-iso PATH        既存 ISO を検証して DVD-R へ書き込む
  --keep-workdir         一時ファイルを残して調査できるようにする
  --force                既存の出力 ISO を上書きする
  -h, --help             このヘルプを表示する

既定では ISO までを作成し、DVD-R への書き込みは行いません。
EOF
}

die() {
  printf 'エラー: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 \
    || die "$1 が見つかりません。インストール後に再実行してください。"
}

file_size() {
  local path="$1"
  if stat -f %z "$path" >/dev/null 2>&1; then
    stat -f %z "$path"
  else
    stat -c %s "$path"
  fi
}

is_positive_integer() {
  # 桁数を先に制限し、Bash の整数範囲を超える入力で内部エラーを出さない。
  [[ "$1" =~ ^[0-9]+$ ]] && [ "${#1}" -le 18 ] && [ "$1" -gt 0 ]
}

parse_options() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --output|--aspect|--video-bitrate|--max-bytes|--burn-iso)
        [ "$#" -ge 2 ] || die "$1 には値が必要です。"
        case "$1" in
          --output) OUTPUT_ISO="$2" ;;
          --aspect) ASPECT="$2" ;;
          --video-bitrate) VIDEO_KBPS="$2" ;;
          --max-bytes) MAX_ISO_BYTES="$2" ;;
          --burn-iso) BURN_ISO="$2" ;;
        esac
        shift 2
        ;;
      --burn) DO_BURN=1; shift ;;
      --keep-workdir) KEEP_WORKDIR=1; shift ;;
      --force) FORCE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      --)
        shift
        [ "$#" -eq 1 ] || die "入力動画を1つだけ指定してください。"
        INPUT="$1"
        shift
        ;;
      -* ) die "不明なオプションです: $1" ;;
      *)
        [ -z "$INPUT" ] || die "入力動画を1つだけ指定してください。"
        INPUT="$1"
        shift
        ;;
    esac
  done
  if [ -n "$BURN_ISO" ]; then
    [ -z "$INPUT" ] || die "--burn-iso と入力動画は同時に指定できません。"
  else
    [ -n "$INPUT" ] || die "入力動画を指定してください。"
  fi
}

normalise_input_path() {
  [ -f "$INPUT" ] || die "入力ファイルがありません: $INPUT"
  case "$INPUT" in /*) ;; *) INPUT="$(pwd)/$INPUT" ;; esac
}

normalise_output_path() {
  [ -n "$OUTPUT_ISO" ] || OUTPUT_ISO="${INPUT%.*}.dvd.iso"
  case "$OUTPUT_ISO" in /*) ;; *) OUTPUT_ISO="$(pwd)/$OUTPUT_ISO" ;; esac
  local output_dir
  output_dir="$(dirname "$OUTPUT_ISO")"
  [ -d "$output_dir" ] || die "出力先ディレクトリがありません: $output_dir"
  if [ -L "$OUTPUT_ISO" ]; then
    die "出力先がシンボリックリンクのため安全のため中断します: $OUTPUT_ISO"
  fi
  [ ! -e "$OUTPUT_ISO" ] || [ -f "$OUTPUT_ISO" ] \
    || die "出力先には通常ファイルのパスを指定してください: $OUTPUT_ISO"
  if [ -e "$OUTPUT_ISO" ] && [ "$INPUT" -ef "$OUTPUT_ISO" ]; then
    die "入力動画と同じ実体を持つ出力先です（ハードリンク等を含む）。"
  fi
  if [ -e "$OUTPUT_ISO" ] && [ "$FORCE" -ne 1 ]; then
    die "出力 ISO が既にあります（上書きには --force）: $OUTPUT_ISO"
  fi
  [ "$INPUT" != "$OUTPUT_ISO" ] || die "入力動画と出力 ISO は同じパスです。"
}

normalise_burn_iso_path() {
  [ -f "$BURN_ISO" ] || die "ISO ファイルがありません: $BURN_ISO"
  case "$BURN_ISO" in /*) ;; *) BURN_ISO="$(pwd)/$BURN_ISO" ;; esac
  OUTPUT_ISO="$BURN_ISO"
}

require_iso_tool() {
  # UDF と DVD-Video 用ファイル配置を生成できる cdrtools の mkisofs を使う。
  require_command mkisofs
}

validate_max_bytes() {
  is_positive_integer "$MAX_ISO_BYTES" || die "--max-bytes は正の整数です。"
  [ "$MAX_ISO_BYTES" -le 4700000000 ] \
    || die "--max-bytes は DVD-R 片面一層の上限 4700000000 bytes 以下です。"
}

select_streams() {
  local video_rows audio_rows
  video_rows="$(ffprobe -v error -select_streams v \
    -show_entries stream=index:stream_disposition=attached_pic -of csv=p=0 "$INPUT")" \
    || die "動画ストリームを調査できません。"
  VIDEO_INDEX="$(printf '%s\n' "$video_rows" | awk -F, '$2 != "1" && NF { print $1; exit }')"
  [ -n "$VIDEO_INDEX" ] || die "通常の動画ストリームが見つかりません。"
  audio_rows="$(ffprobe -v error -select_streams a \
    -show_entries stream=index -of csv=p=0 "$INPUT")" \
    || die "音声ストリームを調査できません。"
  AUDIO_INDEX="$(printf '%s\n' "$audio_rows" | awk 'NF { print $1; exit }')"
  STREAM_INFO="$(ffprobe -v error \
    -show_entries stream=index,codec_type,width,height,display_aspect_ratio,pix_fmt,field_order,color_transfer,color_primaries:stream_tags=rotate:stream_side_data=rotation \
    -of default=nw=1 "$INPUT")" \
    || die "入力ストリームの属性を調査できません。"
}

stream_field() {
  local field="$1"
  printf '%s\n' "$STREAM_INFO" | awk -F= -v target="$VIDEO_INDEX" -v key="$field" '
    $1 == "index" { current = $2 }
    current == target && $1 == key { print substr($0, index($0, "=") + 1); exit }
  '
}

validate_input() {
  local width height dar ratio duration field_order transfer primaries rotate side_rotation
  width="$(stream_field width)"; height="$(stream_field height)"
  [ -n "$width" ] && [ -n "$height" ] || die "動画の解像度を取得できません。"
  is_positive_integer "$width" && is_positive_integer "$height" \
    || die "動画の解像度が不正です。"
  field_order="$(stream_field field_order)"
  case "$field_order" in tt|bb|tb|bt) die "インターレース入力は安全のため中断します。" ;; esac
  transfer="$(stream_field color_transfer)"; primaries="$(stream_field color_primaries)"
  case "$transfer,$primaries" in *smpte2084*|*arib-std-b67*|*bt2020*)
    die "HDR/BT.2020 入力は色変換を指定しないまま DVD 化できません。" ;;
  esac
  rotate="$(stream_field TAG:rotate)"; side_rotation="$(stream_field rotation)"
  [ -z "$rotate" ] || [ "$rotate" = "0" ] || die "回転メタデータ付き入力は中断します。"
  [ -z "$side_rotation" ] || [ "$side_rotation" = "0" ] \
    || die "回転サイドデータ付き入力は中断します。"
  dar="$(stream_field display_aspect_ratio)"
  if [[ "$dar" =~ ^[0-9]+:[0-9]+$ ]]; then
    ratio="$(awk -F: '{ printf "%.6f", $1 / $2 }' <<< "$dar")"
  else
    ratio="$(awk -v w="$width" -v h="$height" 'BEGIN { printf "%.6f", w / h }')"
  fi
  if [ "$ASPECT" = "auto" ]; then
    if awk -v r="$ratio" 'BEGIN { exit !((r > 1.69) && (r < 1.86)) }'; then ASPECT="16:9"
    elif awk -v r="$ratio" 'BEGIN { exit !((r > 1.26) && (r < 1.42)) }'; then ASPECT="4:3"
    else die "入力比率が DVD 標準外です。--aspect を明示してください。"; fi
  fi
  if ! awk -v r="$ratio" -v a="$ASPECT" 'BEGIN {
    target = (a == "16:9") ? 1.777778 : 1.333333
    exit !((r > target - 0.08) && (r < target + 0.08))
  }'; then
    die "入力比率と指定方式が異なります。引き伸ばしを避けるため --aspect を変更してください。"
  fi
  SOURCE_RATIO="$ratio"
  case "$ASPECT" in 16:9|4:3) ;; *) die "--aspect は auto、16:9、4:3 のいずれかです。" ;; esac
  duration="$(ffprobe -v error -show_entries format=duration \
    -of default=nw=1:nk=1 "$INPUT" | head -n 1)"
  awk -v d="$duration" 'BEGIN { exit !(d ~ /^[0-9.]+$/ && d > 0) }' \
    || die "動画の長さを取得できません。"
  DURATION="$duration"
}
