# JSZip

## Purpose

CSV出力パッケージZIPの生成・読込に使用するため、JSZipをローカル同梱する。

## Library

- Name: JSZip
- Version: 3.10.1
- Source: npm package `jszip@3.10.1`
- Homepage: https://github.com/Stuk/jszip#readme
- Repository: https://github.com/Stuk/jszip
- License: MIT OR GPL-3.0-or-later
- Bundled file: vendor/jszip/jszip.min.js
- License file: vendor/jszip/LICENSE.markdown

## Policy

- 外部CDNから読み込まない
- リポジトリ内にバージョン固定で同梱する
- file:// で動作するローカルCSVビューアー運用を維持する
- 管理コンソールZIP出力とローカルCSVビューアーZIP読込で共通利用する予定
- むやみに最新版へ更新せず、更新時はZIP生成・ZIP読込・file://動作確認を行う

## Notes

このフェーズではライブラリ本体を同梱するのみ。
管理コンソールやローカルCSVビューアーからの読み込み・利用実装は次フェーズ以降で行う。
