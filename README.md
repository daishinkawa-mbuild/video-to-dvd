# video-to-dvd

動画から家庭用DVDプレイヤー向けのDVD-Videoを作成するプロジェクトです。
DVD処理とmacOSアプリを、1つのモノレポで管理します。

現在はmacOS向けのDVD作成スクリプトを利用できます。
SwiftUIアプリと、必要なツールを同梱した署名・公証済みDMGの配布は、今後実装します。

## 使い方

macOS上で、必要な外部ツールを導入します。

```bash
brew install ffmpeg dvdauthor cdrtools
```

リポジトリを取得し、動画からISOを作成します。

```bash
git clone https://github.com/daishinkawa-mbuild/video-to-dvd.git
cd video-to-dvd
bash packages/dvd-engine/dvd-create.sh --output /tmp/video.dvd.iso input.mp4
```

作成したISOの再生を確認した後、空のDVD-Rへ書き込みます。

```bash
bash packages/dvd-engine/dvd-create.sh --burn-iso /tmp/video.dvd.iso
```

入力はSDR・プログレッシブの16:9または4:3動画を対象とし、
出力はNTSC DVD-Videoです。詳細な設定と制約は
[DVD処理エンジンのREADME](packages/dvd-engine/README.md)に記載しています。

## モノレポの構成

- `packages/dvd-engine/`：動画の検査、変換、DVD構造・ISOの作成、検証、書き込み
- `docs/`：リポジトリの構成計画
- `.github/workflows/`：シェルの構文とヘルプ起動のCI

今後は `apps/macos/` にアプリを、`scripts/` にビルド・配布処理を追加します。
各ディレクトリの責務と実装順序は、[構成計画](docs/repository-structure.md)を参照してください。

## ライセンス

自作コードのライセンスは[MIT](LICENSE)です。
外部ツールには、それぞれのライセンスが適用されます。
