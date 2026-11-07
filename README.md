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

標準の開発フローは次の1コマンドです

```sh
Scripts/build-app.sh --install --restart
```

1. release build
2. `dist/myss.app`を生成し、固定のcodesigning identityで署名
3. `codesign --verify`に成功した場合だけ`~/Applications/myss.app`へ配置
4. 旧myssの終了を確認してから新しいmyssを起動

myssはAccessibility権限を使うため、開発時も固定のcodesigning identityで署名します
同じbundle identifierと証明書で署名し続けることで、再ビルドしてもAccessibility権限が維持されます

署名identityの決め方

- `MYSS_CODESIGN_IDENTITY`が設定されていればそれを使う
- 未設定ならKeychain内の`Apple Development` identityを自動検出する
- 見つからない場合や複数ある場合はエラーで終了し、ad-hoc署名へは戻さない

```sh
export MYSS_CODESIGN_IDENTITY="Apple Development: ..."
```

ad-hoc署名が必要な場合だけ`--adhoc`を付けます（Accessibility権限は再ビルドごとに外れる可能性があります）

### 初回セットアップ

1. `security find-identity -v -p codesigning`でApple Development identityを確認
2. `Scripts/build-app.sh --install --restart`
3. システム設定の「プライバシーとセキュリティ」→「アクセシビリティ」でmyssを許可
4. 初回起動画面でAPIキーを保存して接続確認し、「開始」を押す

以降はコードを修正して`Scripts/build-app.sh --install --restart`を実行するだけで確認できます
TerminalやPythonは利用に不要です

Accessibility権限がない場合は、パネル上部に「アクセシビリティ権限がありません」と表示されます
設定の「詳細」→「選択取得診断」の`Accessibility trusted`でも確認できます

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
