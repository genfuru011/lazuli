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
- [ ] **ServerRunner 改善**
    - [x] ウォッチ対象に config/deno.json を含める
    - [x] 終了時にDeno/Rackを停止しソケットをクリーンアップ（基本）
    - [ ] プロセスグループ/子プロセス含む完全停止
    - [ ] ログ簡素化・リトライ制御
- [x] **Turbo Drive の統合**
    - [x] Turbo Drive をJSで自動注入（esm.sh）
    - [ ] Turbo Frames/Streams の統合（必要なら）

## 優先度: 中 (Enhancements)

- [x] **Sorbet/Ruby LSP の開発環境整備**
    - [x] monorepo rootにGemfile/sorbet configを配置（VSCodeで動作）
    - [x] Rack向けの最小RBI shim追加

- [ ] **Islands Architecture の自動化**
    - [ ] `"use hydration"` ディレクティブの自動検出
    - [ ] Hydration用スクリプトの自動注入 (現在は手動で `script` タグを書いている)
- [ ] **エラーハンドリングの強化**
    - [ ] Deno側でのレンダリングエラーをRuby側で適切にキャッチして表示
    - [ ] 開発モードでの詳細なエラー画面
- [ ] **データベース連携の強化**
    - [ ] マイグレーション機能の統合
    - [ ] `Lazuli::Repository` のベースクラス実装
- [ ] **CLI UX拡張**
    - [ ] `generate resource`でslug/route指定とテンプレートコメント挿入
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
