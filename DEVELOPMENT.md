# 開発メモ

## 2026-11-07 初回セットアップ失敗

- runtime作成とpip依存導入は完了
- WordNet取得前にDataとDownloadsが空のまま停止
- Python 3.12の`urllib.request.urlretrieve`がGitHub接続時に`SSL: CERTIFICATE_VERIFY_FAILED`で失敗
- UIはPipeを読み取らず、終了コード1だけを表示していた
- 通常ユーザー経路からWordNet取得と57,885語義のEmbedding生成を削除
- 事前生成indexをアプリへ同梱し、SHA-256検証後にatomic配置する方式へ変更

## 2026-11-07 AI言語アシスタントへ方針転換

- WordNet + Ruriのsemantic search、Python backend、検索データの初回セットアップを削除
- 削除前の実装は`archive/wordnet-ruri`ブランチに残している
- 選択文字列、周辺文脈、追加指示をAIへ渡し、structured outputsで`intent`、`summary`、`candidates`を受け取る
- 追加指示は400ms debounce、古い応答はgeneration IDで破棄
- 既存ユーザーの`~/Library/Application Support/myss`は自動削除しない

## 2026-11-07 AI ProviderをOpenAIへ変更

- Anthropic実装を削除し、OpenAI Responses API（`gpt-6-luna`）へ移行
- Keychainのアカウントは`openai-api-key`　旧`anthropic-api-key`は参照せず移行もしない
- 接続確認は`/v1/models`ではなく`/v1/responses`で行い、`Model capabilities: Request`だけで完結させる
- APIキー保存後はKeychainから読み戻して一致を確認する

## 2026-11-08 意図判定をAIへ集約

- system promptから「選択あり＋指示なし → explain_expression」「選択なし → find_expression」の判断目安を削除
- 意図は入力全体からAIが推定し、判断例はfew-shotとして渡す
- Structured Outputに`target_expression`（string | null、必須）を追加
- 対象外の説明に「プログラミング」が含まれ、分野の用語説明まで断られる恐れがあったため、語句・表現の質問は分野を問わず答えるよう修正
