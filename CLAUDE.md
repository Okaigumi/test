# CLAUDE.md

このリポジトリで Claude Code / CLI が作業する際の基本ルール。

## 最優先ルール

作業前に必ず `docs/workflow-rules.md` を確認し、そのルールに従うこと。

## 基本方針

- 原則、同時に進める実装は1つだけにする
- 現在の本流を確認してから作業する
- 本流以外の作業は保留扱いにする
- 実装チャットと進捗管理チャットを混ぜない
- 読み取り専用確認と変更作業を混ぜない
- 作業範囲を超えそうになったら、作業を止めて報告する

## 作業開始時の確認

作業開始時は、原則として以下を確認する。

- 現在ブランチ
- git status
- git log --oneline -5
- origin/main との ahead / behind
- 未コミット変更の有無

## git操作の注意

以下は明示指示がある場合のみ行う。

- git add
- commit
- push
- pull
- merge
- rebase
- reset
- stash
- checkout
- branch作成
- ファイル削除
- 破棄操作

local-only commit がある場合は、勝手に消さないこと。

## 詳細ルール

詳細は `docs/workflow-rules.md` を正本とする。
