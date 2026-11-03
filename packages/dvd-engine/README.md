# DVD処理エンジン

`dvd-create.sh` は、MP4/MOV を日本の家庭用プレイヤー向けの NTSC DVD-Video に変換し、DVD-Video のフォルダ構造を作成して ISO にまとめます。`--burn` を付けた場合だけ、最後に macOS の `hdiutil` で DVD-R へ書き込みます。

## 事前準備

スクリプトはツールを自動インストールしません。次のコマンドで存在を確認し、足りないものは Homebrew の公式 formula から導入してください。

```bash
command -v ffmpeg ffprobe dvdauthor dvdunauthor mkisofs hdiutil xmllint
```

未導入の場合の例:

```bash
brew install ffmpeg dvdauthor cdrtools
```

`dvdunauthor` は `dvdauthor` に付属し、`xmllint` は macOS 標準のコマンドです。DVD-Video 用の UDF とファイル配置を生成するため、`mkisofs` を必須とします。

## 実行例

以降のコマンドは、リポジトリのルートで実行してください。

まず ISO だけを作成し、Mac で再生できることを確認します。

```bash
bash packages/dvd-engine/dvd-create.sh \
  --output "/tmp/video.dvd.iso" \
  "input.mp4"
```

DVD-R へ書き込むときは、空の DVD-R をドライブへ入れて `--burn` を追加します。

```bash
bash packages/dvd-engine/dvd-create.sh --burn "input.mp4"
```

このスクリプトで作成した ISO を後から書き込む場合は、変換をやり直さず次のように実行できます。既存 ISO も、書き込み前に同じ内容検査を行います。

```bash
bash packages/dvd-engine/dvd-create.sh --burn-iso "/tmp/video.dvd.iso"
```

既定値は NTSC、720×480、29.97 fps、MPEG-2、YUV 4:2:0、2ch/48 kHz AC-3 192 kbps、映像 6000 kbps です。映像方式は入力の DAR から 16:9 または 4:3 に決めます。標準から外れた画面比率は、意図しない引き伸ばしを避けるため中断します。

## 安全策と残る制約

- `ffprobe` で添付画像ではない通常の動画ストリームを選び、音声も最初の音声ストリームだけを使います。カバーアート用の追加動画ストリームや字幕・データストリームは本編に混ざりません。
- HDR/BT.2020、インターレース、回転メタデータ付き入力は自動変換せず中断します。
- 入力の画面比率と指定方式が異なる場合は、引き伸ばしを避けるため中断します。NTSC DVD の 16:9/4:3 表示は `-aspect` に任せ、映像フレームは 720×480 に変換します。
- MPEG-2 生成後に全編デコードし、`dvdauthor` の XML で単一タイトルの自動再生と末尾停止を設定します。
- ISO は DVD-Video 用 `mkisofs -dvd-video -udf` で作成し、4.2 GB（既定）の上限を確認します。ISO は読み取り専用でマウントして内容を検査するため、`hdiutil imageinfo` の終了コードには依存しません。
- IFO の識別子・セクタ境界と BUP との一致を確認し、`dvdunauthor` / libdvdread で再生制御情報を解析します。解析された本編への自動遷移と末尾停止、参照先の映像を検査します。複数タイトル・メニュー付きなど、このスクリプトの出力と異なる構成の ISO は対象外です。
- すべての分割 VOB で MPEG-2/720×480/YUV 4:2:0/30000÷1001 fps/DAR、AC-3/48 kHz/2ch を確認し、VOB を連結して本編全体をデコードします。検証に失敗した ISO は書き込まず、既存の出力 ISO も置き換えません。
- `--burn` では `hdiutil burn -forceclose -verifyburn -nosynthesize` を使います。これは書き込みデータの検証であり、家庭用プレイヤーでの再生を保証しません。
- DVD-R の品質、ドライブ、プレイヤーの相性、ピックアップの状態はソフトウェアで排除できません。最初の1枚を対象プレイヤーで最初から最後まで再生してください。

DVD-R の書き込み失敗でメディアを消費する可能性があるため、最初は `--burn` なしで ISO を作成し、Mac 側の DVD プレイヤーで確認してから書き込みます。

検査のために本編を一時抽出するので、作成する ISO の数倍の空き領域が必要です。ソフトウェア検査を通っても、対象プレイヤーでの実機再生確認は必要です。
