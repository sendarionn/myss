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
