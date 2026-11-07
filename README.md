# myss

日本語の語と意味を双方向に検索するmacOSアプリ

Codexを使用して開発しています

## 現在の機能

- `⌃⌥⌘K`で任意のアプリから検索パネルを表示
- 選択テキスト、またはカーソルがある現在文を最大600文字で取得
- Secure Text Fieldからは取得しない
- 取得した文脈から検索方向を自動判定
- 日本語WordNet 2.1の語義をRuri v3 70mでsemantic search
- 語義ごとに定義、同義語、用例、典拠を表示
- 入力を100msでdebounceし、古い検索タスクを破棄
- `↑`と`↓`で候補を移動
- `Enter`で元の入力位置へ挿入
- `⌘Enter`でクリップボードへコピー
- `Esc`で閉じる

## 初回セットアップ

Ruri v3 70mと日本語WordNet 2.1からローカル検索indexを作成します

```sh
Scripts/setup-semantic-search.sh
```

モデルとPython実行環境は`.myss-runtime`、検索indexは`.myss-data`へ保存されます

## 実行

```sh
swift run myss
```

初回起動時にmacOSのアクセシビリティ許可を求めます

許可後に反映されない場合は、システム設定の「プライバシーとセキュリティ」→「アクセシビリティ」で実行元のターミナルを許可してから再起動します

## テスト

```sh
swift test
```

## データとライセンス

- [日本語ワードネット 2.1](https://bond-lab.github.io/wnja/) © 2009-2011 NICT, 2012-2015 Francis Bond and 2016-2024 Francis Bond, Takayuki Kuribayashi
- Ruri v3 70mはApache License 2.0
- 日本語WordNetを再配布する場合は公式アーカイブ内のライセンスも同梱が必要

## 現時点の制約

- Wiktionary、Wikipedia、Wikidata、macOS Dictionary連携は未実装
- Ruriの初回セットアップにはモデル取得とindex生成の時間が必要
- Accessibility APIで選択範囲への直接挿入ができないアプリでは、クリップボードとペースト操作へフォールバック
- アプリ署名と配布用バンドルは未整備
- グローバルショートカットの初期値は`⌃⌥⌘K`
- キーコードと修飾キーは`HotKeyConfiguration`に分離済み

## 次の作業

1. 実利用で検索順位を確認し、必要な場合だけrerankingを追加
2. WiktionaryとWikipediaを段階的に取得
3. `.app`バンドル、署名、権限導線を整備
4. ショートカット変更とログイン時起動を設定画面へ追加
