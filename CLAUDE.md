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

## 指示解釈と実行ゲート（再発防止）

- 「続けて」「進めて」「OK」などは、次工程を実行してよいという許可ではない。
  直前に合意した範囲の中だけで続行する。
- 指示が「確認だけ」とも「次の生成・変更・実行」とも読める場合は、
  必ず狭いほう（確認・報告・停止）として扱い、次の一手に進む前に明示許可を取る。
- 次の各工程は、それぞれ独立した明示許可が必要。前工程の許可は次工程の許可を含まない。
  調査 → 設計 → ファイル作成 → git add → commit → push → PR作成 → PR merge → DB実行 → docs記録
- 明示指示がない限り、次を実行しない（曖昧な指示は許可とみなさない）。
  - Write / Edit（ファイル作成・編集）
  - git add / commit / push
  - PR作成 / PR merge
  - SQL実行、REVOKE / GRANT / DROP / TRUNCATE / DELETE / UPDATE / INSERT などの DB変更
  - Supabase CLI / psql
- SQL実行・DB変更は、設計や SQLファイルが用意済みでも勝手に実行しない。DB実行はユーザーが行う。
- 迷ったら止まって聞く。手を動かす前に「次はこれをやってよいか」を一言確認する。

## 詳細ルール

詳細は `docs/workflow-rules.md` を正本とする。
