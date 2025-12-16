# Lazuli TODO List

## 優先度: 高 (Core Features)

- [x] **CLIツールの実装 (`lazuli` コマンド)**
    - [x] `lazuli new <project_name>`: 新規プロジェクトの作成
    - [x] `lazuli server`: RubyサーバーとDenoサーバーを同時に起動するコマンド（簡易ホットリロード付き）
    - [x] `lazuli generate resource <name>`: Resource, Struct, Pageの雛形生成
- [x] **ホットリロード (Hot Reload) の実装**
    - [x] Ruby/TSXファイルの変更検知とサーバー再起動（簡易ウォッチャ）
    - [x] TSXファイルの変更検知とブラウザリロード (Live Reload) ※ポーリングによる簡易版
- [x] **TypeScript型定義の自動生成**
    - [x] `Lazuli::Struct` から `client.d.ts` を生成する機能（`lazuli types`）
    - [x] Struct変更検知→自動生成（`lazuli server --reload` の再起動時に追従）
- [x] **Live Reload の高度化**
    - [x] EventSource (SSE) での通知（ポーリング廃止）
    - [x] ファイル変更をサーバープロセス再起動なしでpushする（Deno/Rubyのwatch統合）
- [x] **TypeGenerator の精緻化**
    - [x] Array/Optional/Struct参照の型推論強化
    - [x] Union型（非配列含む）の正確化（`Lazuli::Types.any_of` 等）
    - [x] 型の重複出力回避とテスト追加
    - [x] 名前衝突ガード（例: `Admin::User` と `User`）
- [x] **次の実装順（提案）**
    - [x] 1) ルーティング/params（path params + 404/405）
    - [x] 2) Resource RPC メタデータ保持（`Resource.rpc`）
    - [x] 3) Turbo Streams MVP（最小API + example）

- [x] **ルーティング/params の改善**
    - [x] `/users/123` の `123` を `params[:id]` に渡す（path params）
    - [x] 405時にAllowヘッダを返す
- [x] **Resource RPC メタデータの整備**
    - [x] `Resource.rpc` で定義を保持（name/returns/params など）
    - [ ] `lazuli types` に RPC 型（request/response）やクライアントスタブ生成を追加するか検討
+
+- [ ] **Deno adapter テスト整備**
+    - [x] `/render_turbo_stream` の最小Denoテスト（invalid fragment / targets remove）
+    - [ ] CIで `deno test` を回す（実行環境にDenoを含める）

- [ ] **ServerRunner 改善**
    - [x] ウォッチ対象に config/deno.json を含める
    - [x] 終了時にDeno/Rackを停止しソケットをクリーンアップ（基本）
    - [ ] プロセスグループ/子プロセス含む完全停止
    - [ ] ログ簡素化・リトライ制御
- [ ] **プロセスモデルの整理（App/ServerRunner）**
    - [x] 方針: Deno管理は `Lazuli::ServerRunner`（CLI）に集約し、`Lazuli::App` はRackアプリとして純粋に保つ
    - [ ] (任意) opt-inで `Lazuli::App#start_deno_process` を実装するか（rackup単体起動でもDenoをspawnできるようにする）
    - [ ] spawnする場合: socket ready のヘルスチェック/リトライ、終了時クリーンアップ、ログ制御

- [x] **Turbo Drive の統合**
    - [x] Turbo Drive をJSで自動注入（esm.sh）
    - [ ] **Turbo Frames/Streams の統合（hooks最小方針）**
        - [ ] Turbo Frames: フレームワーク側は特別な仕組みを増やさず、ユーザーが `<turbo-frame id="...">` を書けば動く前提を明文化
        - [ ] Turbo Streams: Ruby側に最小APIを追加（Content-Type: `text/vnd.turbo-stream.html`）
            - [ ] `Lazuli::TurboStream` ビルダー（`append/prepend/replace/update/remove/before/after` 等）
            - [ ] `Lazuli::Resource#turbo_stream`（または `render_turbo_stream`）で複数操作をまとめて返せるようにする
            - [ ] Content negotiation: `Accept: text/vnd.turbo-stream.html`（+ `?format=turbo_stream` の逃げ道）
            - [ ] Turboが期待するリダイレクト/ステータス（302/303）と互換になるように整理
        - [ ] `<template>` 内HTMLの生成戦略を決める
            - [ ] 推奨案: Deno側に fragment render 用エンドポイント（例: `POST /render_fragment`）を追加してJSXで断片SSR
            - [ ] 代替案: Rubyで文字列生成（最小）※HTML escape/安全性の取り扱い要注意
            - [ ] どちらをデフォルトにするか決定・ドキュメント化
        - [ ] exampleアプリでStreams実例（create/deleteでlistにappend/remove、Framesと併用）
        - [ ] テスト: RackレベルでContent-Typeとturbo-streamタグ構造の検証

## 優先度: 中 (Enhancements)

- [x] **Sorbet/Ruby LSP の開発環境整備**
    - [x] monorepo rootにGemfile/sorbet configを配置（VSCodeで動作）
    - [x] Rack向けの最小RBI shim追加

- [ ] **テスト実行の整備**
    - [ ] `packages/lazuli` のテストが `minitest` に依存しているので、開発依存に追加して `bundle exec ruby -Itest test/**/*_test.rb` を通す
    - [ ] (任意) CI でテスト実行

- [ ] **Islands Architecture の自動化**
    - [ ] `"use hydration"` ディレクティブの自動検出
    - [ ] Hydration用スクリプトの自動注入（現状: ユーザーが `<Island ...>` を書く必要がある）
- [ ] **エラーハンドリングの強化**
    - [ ] Deno側でのレンダリングエラーをRuby側で適切にキャッチして表示
    - [ ] 開発モードでの詳細なエラー画面
- [ ] **データベース連携の強化**
    - [ ] マイグレーション機能の統合
    - [ ] `Lazuli::Repository` のベースクラス実装
- [ ] **CLI UX拡張**
    - [ ] `generate resource`でslug/route指定とテンプレートコメント挿入
- [ ] **ドキュメント整備**
    - [ ] `packages/lazuli/README.md` を実用レベルに拡充（server/types/islands/turbo など）
    - [ ] `packages/lazuli/docs/ARCHITECTURE.md` のディレクトリマッピング（views→pages/layouts/components等）を現状に合わせる
- [ ] **サンプル拡充**
    - [ ] exampleにCRUDフローと複数Island例を追加
    - [ ] READMEに生成物/サンプルの利用手順を追記

## 優先度: 低 (Future)

- [ ] **デプロイメントガイド**
    - [ ] Dockerfile の作成
    - [ ] VPS (Kamal等) へのデプロイ手順
- [ ] **テストフレームワークの統合**
    - [ ] Ruby側のRSpec統合
    - [ ] Deno側のテスト統合
- [ ] **ベンチマーク**
    - [ ] Rails, Hanami との比較

## 完了済み (Done)

- [x] **アーキテクチャの確立** (Ruby + Deno + Hono JSX)
- [x] **Zero Node Modules の実現** (esm.sh + Import Map)
- [x] **SSRの実装** (Hono JSX)
- [x] **クライアントサイドハイドレーションの実装** (Hono JSX DOM)
- [x] **Unix Domain Socket 通信の実装**
- [x] **Denoアダプターの堅牢化** (Import Map挿入の修正、アセットMIME判定・404対応、ソケット初期化)
- [x] **Ruby側レンダラー/ルーティング改善** (ソケット設定を環境依存化、AssetレスポンスのContent-Type適用、HTTPメソッドによる簡易RESTマッピング)
