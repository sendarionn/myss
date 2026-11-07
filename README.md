# myss

日本語の語と意味を双方向に検索するmacOSアプリ

Codexを使用して開発しています

## 現在の機能

- `⌃⌥⌘K`で任意のアプリから検索パネルを表示
- 選択テキスト、またはカーソルがある現在文を最大600文字で取得
- Secure Text Fieldからは取得しない
- 入力から検索意図を自動判定
  - 入力全体が見出し語 → 語義を表示
  - `リリース ビジネス`のように先頭が見出し語で空白の後に文脈 → 文脈に近い語義を上位に表示
  - それ以外 → 意味から語の候補を表示
- 語を選択して開いた場合は選択箇所の文を文脈として語義を並べ替え
- 日本語WordNet 2.1の語義をRuri v3 70mでsemantic search
- 語義ごとに定義、同義語、用例、典拠を表示
- 入力を100msでdebounceし、古い検索タスクを破棄
- `↑`と`↓`で候補を移動
- `Enter`で元の入力位置へ挿入
- `⌘Enter`でクリップボードへコピー
- `Esc`で閉じる

## アプリのビルド

```sh
Scripts/build-app.sh
```

`dist/myss.app`が生成されます

開発中のMacへインストールする場合は以下を実行します

```sh
Scripts/build-app.sh --install
```

`~/Applications/myss.app`へ配置され、以降はFinderから起動できます

ビルド時に開発環境のindexを事前生成済み成果物としてアプリへ同梱します

初回起動後はアプリ内の案内から検索データとアクセシビリティ権限を準備します
Terminalでのセットアップは不要です

## 開発用セットアップ

`swift run myss`で開発する場合だけ使用します

```sh
Scripts/setup-semantic-search.sh
```

開発者向け処理ではWordNet取得、57,885語義のEmbedding生成、index生成を行います

通常のアプリでは事前生成済みindexを検証して`~/Library/Application Support/myss/Data`へ配置します
通常利用時に57,885語義のEmbeddingは生成しません
RuriモデルとPython runtimeは同じApplication Support以下へ準備します

セットアップの詳細ログは`~/Library/Logs/myss/setup.log`へ保存します
失敗時はアプリ内の「詳細を表示」で失敗段階、実行コマンド、終了コード、stderr末尾を確認できます

## 開発用実行

```sh
swift run myss
```

初回起動時にmacOSのアクセシビリティ許可を求めます

許可後に反映されない場合は、システム設定の「プライバシーとセキュリティ」→「アクセシビリティ」で実行元のターミナルを許可してから再起動します

## テスト

```sh
swift test
python3 -I Tests/backend/test_semantic_backend.py
```

## データとライセンス

- [日本語ワードネット 2.1](https://bond-lab.github.io/wnja/) © 2009-2011 NICT, 2012-2015 Francis Bond and 2016-2024 Francis Bond, Takayuki Kuribayashi
- Ruri v3 70mはApache License 2.0
- 日本語WordNetを再配布する場合は公式アーカイブ内のライセンスも同梱が必要

## 現時点の制約

- Wiktionary、Wikipedia、Wikidata、macOS Dictionary連携は未実装
- Ruriの初回セットアップにはモデル取得とPythonパッケージ準備の時間が必要
- 現在のruntime作成には明示検出したPython 3.10以降を使用するため、Python非依存化は未完了
- Accessibility APIで選択範囲への直接挿入ができないアプリでは、クリップボードとペースト操作へフォールバック
- アプリ署名と配布用バンドルは未整備
- グローバルショートカットの初期値は`⌃⌥⌘K`
- キーコードと修飾キーは`HotKeyConfiguration`に分離済み

## 次の作業

1. 実利用で検索順位を確認し、必要な場合だけrerankingを追加
2. WiktionaryとWikipediaを段階的に取得
3. `.app`バンドル、署名、権限導線を整備
4. ショートカット変更とログイン時起動を設定画面へ追加
