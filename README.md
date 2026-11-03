# video-to-dvd

動画から家庭用DVDプレイヤー向けのDVD-Videoを作成するプロジェクトです。
DVD処理とmacOSアプリを、1つのモノレポで管理します。

最初に[リポジトリの構成計画](docs/repository-structure.md)を定義し、
既存のDVD作成スクリプトを `packages/dvd-engine/` へ取り込みます。
SwiftUIアプリと署名・公証済みDMGの配布は、今後実装します。

自作コードのライセンスは[MIT](LICENSE)です。
