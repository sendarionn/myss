# myss

文章入力中に、選択文字列と周辺の文章をAIへ渡して語・意味・表現を相談し、その場で挿入できるmacOSアプリ

Codexを使用して開発しています

## 使い方

1. 任意のアプリで文章を書いている途中に`⌃⌥⌘K`を押す
2. パネルが開くと同時に、選択文字列と周辺の文章を使ってAIへ問い合わせる
   - 語を選択している場合 → その文脈での意味を表示
   - 選択せずに説明的な文を書いている場合 → その意味に合う語の候補を表示
3. 必要なら上部の欄に追加の指示を入力する（例: `もっと堅く`、`名詞で`、`短く`）
   - 入力が止まって400ms経つと、現在の回答を踏まえて再問い合わせする
   - 別の指示に書き換えると、直前の回答を踏まえて続けて修正する
4. 候補を選んで確定する
   - `↑` / `↓`: 候補を移動
   - `Enter`: 選択中の候補を元の位置へ挿入（選択文字列があれば置き換え）
     - 説明だけの回答では何も挿入しない
   - `⌘Enter`: 選択中の候補、または説明をコピー
   - `Esc`: 閉じる（パネル内の修正履歴はリセット）

検索モードの選択はなく、意図はAIが判定します

## AIへ送信する内容

- 選択文字列（最大600文字）
- 選択箇所またはカーソルを含む文と前後1文（最大400文字）
- パネルで入力した追加の指示と、同じパネル内での直前の回答
- 選択文字列は次の順に取得します
  1. `AXSelectedText`
  2. `AXSelectedTextRange` + `AXValue`から切り出し
  3. `AXStringForRangeParameterizedAttribute`
  4. 上記で取得できなければ、ショートカットの修飾キーが離されるのを待ってから`⌘C`を送り、元のクリップボードを全形式で復元
- `⌘C`で`changeCount`が変わらなければ選択なしとして扱い、古いクリップボードの内容は使いません
- 設定の「詳細」→「選択取得診断」で、直近の取得経路と文字数を確認できます（文字列そのものは保存しません）
- パスワード欄（Secure Text Field）とパスワード入力中（Secure Event Input）は読み取らず、`⌘C`も送りません
- 文書全体は送信しません
- 設定の「詳細」→「最後にAIへ送信した内容を表示」で確認できます

同じ内容の問い合わせは10分間メモリキャッシュから返します

## AI Provider

- 現在のAI ProviderはOpenAI
- モデルは`gpt-6-luna`（reasoning effort `none`）
- Responses API（`POST /v1/responses`）+ Structured Outputsを使用
- APIキーはmacOSキーチェーンへ保存します
- 接続確認も`/v1/responses`への最小の問い合わせで行います
- Providerは`LanguageAssistantProvider`で抽象化しているため、他のサービスやmyss側バックエンドへ差し替えられます

必要なAPIキー権限

- Restricted
- Model capabilities: Request
- その他: None（`List models`は不要）

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

修正後の確認では、配置後に旧プロセスを終了して新しいappを起動する`--restart`を付けます

```sh
Scripts/build-app.sh --install --restart
```

初回起動時の画面でアクセシビリティを許可し、APIキーを保存して「開始」を押すと利用できます
TerminalやPythonは不要です

## 開発用実行

```sh
swift run myss
```

Debug buildでは選択文字列の取得経路を`[myss][context]`で出力します（文字列そのものは出力しません）
`MYSS_AX_ATTRIBUTES=1 swift run myss`で、対象要素が公開している属性名も出力します

許可後に反映されない場合は、システム設定の「プライバシーとセキュリティ」→「アクセシビリティ」で実行元のターミナルを許可してから再起動します

## テスト

```sh
swift test
```

## 現時点の制約

- AI応答はストリーミングせず、回答全体の受信後に表示
- Accessibility APIで選択範囲への直接挿入ができないアプリでは、クリップボードとペースト操作へフォールバック
- アプリはad-hoc署名のため、再ビルド後にキーチェーンへのアクセス許可を求められる場合がある
- 以前のWordNet + Ruriによる辞書検索は`archive/wordnet-ruri`ブランチに残しています
