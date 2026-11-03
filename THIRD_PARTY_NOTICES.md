# 外部ソフトウェアの一覧

確認日：2026年11月4日

自作コードの[MITライセンス](LICENSE)は、以下の外部ソフトウェアには適用しません。
現在のリポジトリは外部ツールを呼び出すコードと文書を配布し、外部バイナリを同梱しません。
この一覧は依存関係の説明であり、将来の同梱物に必要な原文ライセンスや通知文の代わりにはなりません。

## DVD処理が呼び出すプログラム

| プログラム | 用途 | ライセンスの確認結果 | 今回の確認対象 |
| --- | --- | --- | --- |
| `ffmpeg` / `ffprobe` | 動画・音声の検査、MPEG-2・AC-3への変換、全編デコード検証 | 開発環境の実体はGPL-3.0-or-later。上流のLGPL表記をそのまま適用できません。 | FFmpeg 8.0、Homebrew 8.0_1 |
| `dvdauthor` / `dvdunauthor` | DVD-Video構造の生成と再生制御情報の解析 | GPL-2.0-or-later。配布する版の原文と依存物は同梱前に確認します。 | Homebrewのdvdauthor 0.7.2の定義 |
| `mkisofs` | DVD-Video用のUDF/ISOイメージの生成 | cdrtoolsの構成別ライセンスが適用されます。mkisofsはGPL、関連ライブラリにはCDDLなどが含まれます。 | cdrtools 3.02a09の上流ソース |
| `hdiutil` | ISOのマウント、DVD-Rへの書き込みとデータ検証 | Appleが提供するmacOS付属プログラム。このプロジェクトでは再配布しません。 | 利用者のmacOS付属版 |
| `xmllint` | DVD再生制御XMLの検査 | 上流libxml2はMIT。このプロジェクトはmacOS付属コマンドを実行し、再配布しません。 | 利用者のmacOS付属版 |

DVD処理は、BashとmacOSの標準コマンドも実行します。それらの実行ファイルも同梱対象には含めません。

## FFmpegのビルドによる違い

開発環境では `ffmpeg -L` の表示がGPLv3以降であることを確認しました。
ビルド設定には `--enable-gpl`、`--enable-version3`、`--enable-libx264`、
`--enable-libx265` が含まれています。
エンジンが使わない機能でも、バイナリに組み込まれていればライセンス確認の対象です。

別のFFmpegを採用するときは、その実行ファイルとソースのライセンスを改めて確認します。
同梱時には、FFmpeg本体だけでなく、取り込んだコーデックや依存ライブラリも確認します。
`--enable-nonfree` による再配布不可の構成は、同梱候補にしません。

## cdrtoolsの構成による違い

cdrtools 3.02a09の `COPYING` は、サブプロジェクトごとにライセンスを区別しています。
`mkisofs/` はGPL、`libscg/` などはCDDL、`libparanoia/` はLGPLの対象です。
ここに挙げたサブプロジェクトのすべてを、DVD処理が直接使うわけではありません。

Homebrew formulaの `CDDL-1.0` というパッケージ全体の表示だけでは、
mkisofsと関連ライブラリの条件を分類しきれません。
同梱する版の `COPYING`、各ソースの表示、リンク先、ビルド方法を基準に再確認します。
原文ライセンスとソースを添えるだけで、GPL/CDDLの組み合わせの互換性まで確認済みとはしません。
採用する構成の扱いが確認できるまでは、mkisofsの同梱版を公開しません。

## 同梱版で追加する情報

将来の同梱版では、この一覧を実際の配布物に合わせて更新します。
配布者は各依存物の版、入手元、ビルド設定、ハッシュ値を固定し、
原文ライセンス、著作権表示、必要な通知文、対応ソースの取得先を配布物に含めます。
動的・静的に取り込んだ依存ライブラリの棚卸しは、配布バイナリが未確定のため未完了です。
具体的な作業は、[公開・同梱時のライセンス方針](docs/licensing.md)に記載しています。

## 確認資料

- [FFmpeg公式：ライセンスと法的事項](https://ffmpeg.org/legal.html)
- [FFmpeg公式：ビルド構成とライセンスの対応](https://github.com/FFmpeg/FFmpeg/blob/master/LICENSE.md)
- [dvdauthorの配布元](https://dvdauthor.sourceforge.net/)
- [Homebrew：dvdauthorの定義](https://formulae.brew.sh/formula/dvdauthor)
- [cdrtools 3.02a09の配布元ソース：COPYINGと各ソースの表示を参照](https://sourceforge.net/projects/cdrtools/files/alpha/cdrtools-3.02a09.tar.bz2/download)
- [Homebrew：cdrtoolsの定義](https://formulae.brew.sh/formula/cdrtools)
- [libxml2公式：Copyright](https://github.com/GNOME/libxml2/blob/master/Copyright)
