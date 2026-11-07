import Foundation

enum LanguagePrompt {
    static let cursorMarker = "【カーソル】"
    static let maximumHistoryTurns = 4

    static let system = """
    あなたはmacOSで文章を入力している人のための言語アシスタントです
    ユーザーは文章を書いている途中でショートカットを押しました
    与えられた情報から、今必要としている言語操作を推定して答えてください

    与えられる情報
    - selected_text: ユーザーが選択している文字列　空の場合は選択なし
    - context: 選択箇所またはカーソル周辺の文章　\(cursorMarker)はカーソル位置
    - instruction: パネルに入力された文字列　追加指示の場合も、それ自体が質問の場合もある　空の場合は入力なし

    意図の推定
    - selected_text、context、instruction、直前のやり取りの全体から、ユーザーが何を求めているかを推定する
    - 表面的な語順、文字数、特定の助詞だけでintentを決めない
    - 選択文字列の有無だけでintentを決めない　選択文字列は強いヒントだが、instructionの要求を優先する
    - 自然な省略表現や断片的な入力も、会話的に意図を補って解釈する
    - 特定の語句が提示され、その語句について特定の分野・状況・文脈での意味を知りたがっている場合はexplain_expression
    - 特定の語句は提示されず、意味・特徴・用途・定義などの説明から適切な語を探している場合はfind_expression
    - 説明対象として認識した語句をtarget_expressionに入れる　説明対象がなければnull

    intent
    - find_expression: 説明や文脈が表している概念に合う語・表現を提案する
    - explain_expression: 提示された語句の、指定された分野や文脈での意味を説明する
    - rewrite: 選択された文字列や指定された表現を言い換える（短く、堅く、柔らかく、ビジネス向けなど）
    - compare_expressions: 似た語句のニュアンスの違いを説明する
    - continue_text: カーソル位置に自然に続く語句を提案する
    - unknown: 言語・文章操作として解釈できない

    判断例（規則ではなく例）
    - 「プレーンテキスト プログラミングでは」→ explain_expression、target_expressionは「プレーンテキスト」
    - 「プログラミングなどでの、シンプルなテキストファイルのこと」→ find_expression、target_expressionはnull、候補に「プレーンテキスト」
    - 「リリース ビジネスでは」→ explain_expression、target_expressionは「リリース」
    - 「製品やサービスを公開・提供開始すること」→ find_expression、候補に「リリース」
    - 「営業でいうリード」→ explain_expression、target_expressionは「リード」
    - 「変更内容を履歴として確定して保存する操作」→ find_expression、候補に「コミット」
    - 「リリース」を選択し、instructionが「もっと堅く」→ rewrite
    - 「リリース」を選択し、instructionが空 → 多くの場合explain_expression

    candidatesの規則
    - Enterで選択した候補がそのまま文章へ入力される
    - 選択がある場合は選択文字列を置き換え、選択がない場合はカーソル位置へ挿入される
    - textには入力する文字列だけを入れる　引用符、番号、説明を含めない
    - find_expression、rewrite、continue_textでは3〜10件返し、最も適切なものを先頭に置く
    - explain_expressionでは原則として空配列にする　類義語、別の言い方、似た表現を求められた場合だけ返す
    - compare_expressionsでは、比較対象の語句を候補として返してよい
    - explanationは1文以内でニュアンスや使い分けを書く

    summaryの規則
    - 最大2文
    - explain_expressionでは、指定された分野や文脈での意味を書く
    - それ以外では候補全体に共通する意味やユーザーの意図を短く書く

    対象外
    - 語句や文章表現に関する質問であれば、プログラミング、ビジネス、医療など分野を問わず答える
    - 語句や文章表現と無関係な雑談、調査、コード作成、ニュースには答えない　その場合はintentをunknownにし、summaryで言語・文章操作のみ対応すると伝える

    回答は日本語で、短く書いてください
    """

    static var responseSchema: [String: Any] { [
        "type": "object",
        "properties": [
            "intent": ["type": "string", "enum": LanguageIntent.allCases.map(\.rawValue)],
            "target_expression": ["type": ["string", "null"]],
            "summary": ["type": "string"],
            "candidates": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string"],
                        "explanation": ["type": "string"]
                    ],
                    "required": ["text", "explanation"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["intent", "target_expression", "summary", "candidates"],
        "additionalProperties": false
    ] }

    /// 最初のユーザーメッセージ　文脈と最初の指示を含む
    static func contextMessage(for request: LanguageRequest, instruction: String) -> String {
        var context = request.surroundingContext
        if let offset = request.cursorOffset {
            let nsContext = context as NSString
            let location = max(0, min(offset, nsContext.length))
            context = nsContext.replacingCharacters(in: NSRange(location: location, length: 0), with: cursorMarker)
        }
        return """
        <selected_text>\(request.selectedText)</selected_text>
        <context>\(context)</context>
        <instruction>\(instruction)</instruction>
        """
    }

    static func followUpMessage(_ instruction: String) -> String {
        "<instruction>\(instruction)</instruction>"
    }

    /// Messages APIへ渡す会話　過去の回答を挟んで追加指示を連ねる
    static func messages(for request: LanguageRequest) -> [[String: String]] {
        let history = Array(request.history.suffix(maximumHistoryTurns))
        let instructions = history.map(\.instruction) + [request.manualInstruction]
        var messages = [["role": "user", "content": contextMessage(for: request, instruction: instructions[0])]]
        for (index, turn) in history.enumerated() {
            messages.append(["role": "assistant", "content": encode(turn.response)])
            messages.append(["role": "user", "content": followUpMessage(instructions[index + 1])])
        }
        return messages
    }

    /// 設定画面の確認用に送信内容を読みやすく整形する
    static func transcript(for request: LanguageRequest) -> String {
        messages(for: request)
            .map { "[\($0["role"] ?? "")]\n\($0["content"] ?? "")" }
            .joined(separator: "\n\n")
    }

    private static func encode(_ response: LanguageResponse) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(response) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
