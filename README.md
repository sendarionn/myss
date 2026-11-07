# myss

Apple IntelligenceのオンデバイスLLMを利用するmacOS言語アシスタント
選択文字列と周辺の文章から語・意味・表現をMac上で解釈し、その場で挿入できます

Codexを使用して開発しています

## 動作環境

- macOS 26以降
- Apple Intelligence対応Mac（Apple Intelligenceを有効にし、オンデバイスモデルの準備が完了していること）
- APIキー不要、AI利用料不要
- 文章を外部AIサービスへ送信しません

## 使い方

1. 任意のアプリで語や文章を選択して`⌃⌥⌘K`を押す
   - 選択した文字列がそのまま入力欄に入り、オンデバイスAIが意味や候補を表示する
2. 入力欄は普通のテキストとして編集できる
   - 例: `residency` → `residency APIでは` → `residency OpenAI APIでは`
   - 入力が止まって400ms経つと、古い生成をキャンセルし、現在の入力全体から意図を推定し直す
   - 過去の回答は会話として積まず、毎回現在の入力だけで結果を作る
3. 何も選択せずに起動するか、入力欄を空にすると履歴が表示される
   - 履歴を選ぶと、保存済みの結果を再生成せずに表示する
   - 履歴を開いて編集した結果は、元の履歴を変えずに新しい履歴として保存される
4. 操作
   - `↑` / `↓`: 候補または履歴を移動
   - `Enter`: 候補を元の選択位置へ挿入（説明だけの回答では何も挿入しない）　空欄では選択中の履歴を開く
   - `⌘Enter`: 選択中の候補、または説明をコピー
   - `Esc`: 閉じる

検索モードの選択はなく、意図はAIが判定します

### 履歴

- 保存するのは、パネルを閉じる・挿入・コピー・入力欄を空にする・別の履歴を開く時点の最新の成功結果だけ
- 入力途中の文字列は保存しない
- 直前の履歴と同じ内容、開いただけの履歴は保存しない
- `~/Library/Application Support/myss/history.json`へ新しい順に最大100件保存する

## オンデバイスAIで処理する内容

- 選択文字列（最大600文字）
- 選択箇所またはカーソルを含む文と前後1文（最大400文字）
- 入力欄の文字列（選択文字列が入力欄に残っている間だけ、周辺の文章も手がかりとして渡す）
- 選択文字列は次の順に取得します
  1. `AXSelectedText`
  2. `AXSelectedTextRange` + `AXValue`から切り出し
  3. `AXStringForRangeParameterizedAttribute`
  4. 上記で取得できなければ、ショートカットの修飾キーが離されるのを待ってから`⌘C`を送り、元のクリップボードを全形式で復元
- `⌘C`で`changeCount`が変わらなければ選択なしとして扱い、古いクリップボードの内容は使いません
- 設定の「詳細」→「選択取得診断」で、直近の取得経路と文字数を確認できます（文字列そのものは保存しません）
- パスワード欄（Secure Text Field）とパスワード入力中（Secure Event Input）は読み取らず、`⌘C`も送りません
- 文書全体は読み取りません
- 設定の「詳細」→「最後にオンデバイスAIへ渡した内容を表示」で確認できます

同じ内容の問い合わせは10分間メモリキャッシュから返し、再生成の計算量を減らします

## オンデバイスAI

- Foundation Modelsの`SystemLanguageModel.default`だけを使用します
- Guided Generation（`@Generable`）で`intent`、`targetExpression`、`summary`、`candidates`を構造化して受け取ります
- 問い合わせごとに新しい`LanguageModelSession`を作り、キャンセルした生成が次の結果へ混ざらないようにしています
- 起動時とショートカット押下時にモデルをprewarmします
- 利用できない場合は理由（Apple Intelligenceが無効、非対応Mac、モデル準備中）を表示して停止し、クラウドAIへは切り替えません

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
4. 初回起動画面でオンデバイスAIが「利用可能」になっていることを確認し、「開始」を押す

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
