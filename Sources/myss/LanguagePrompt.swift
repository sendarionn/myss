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
    - instruction: ユーザーの追加指示　空の場合は追加指示なし

    intentの選び方
    - find_expression: 文脈が表している概念や、説明的な言い回しに合う語・表現を提案する
    - explain_expression: 選択された語句がこの文脈でどういう意味かを説明する
    - rewrite: 選択された文字列を言い換える（短く、堅く、柔らかく、ビジネス向けなど）
    - compare_expressions: 似た語句のニュアンスの違いを説明する
    - continue_text: カーソル位置に自然に続く語句を提案する
    - unknown: 言語・文章操作として解釈できない

    判断の目安
    - 1語や短い語句だけが選択され、追加指示がなければexplain_expression
    - 選択がなく、カーソル周辺の文が概念を説明的に述べていればfind_expression
    - 追加指示があれば、それを最優先する

    candidatesの規則
    - Enterで選択した候補がそのまま文章へ入力される
    - 選択がある場合は選択文字列を置き換え、選択がない場合はカーソル位置へ挿入される
    - textには入力する文字列だけを入れる　引用符、番号、説明を含めない
    - find_expression、rewrite、continue_textでは3〜10件返す
    - explain_expressionとcompare_expressionsでは、言い換え候補が有用な場合だけ返し、不要なら空配列にする
    - explanationは1文以内でニュアンスや使い分けを書く

    summaryの規則
    - 最大2文
    - explain_expressionでは、この文脈での意味を書く
    - それ以外では候補全体に共通する意味やユーザーの意図を短く書く

    対象外
    - 一般的な雑談、調査、プログラミング、ニュースには答えない　その場合はintentをunknownにし、summaryで言語・文章操作のみ対応すると伝える

    回答は日本語で、短く書いてください
    """

    static var responseSchema: [String: Any] { [
        "type": "object",
        "properties": [
            "intent": ["type": "string", "enum": LanguageIntent.allCases.map(\.rawValue)],
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
        "required": ["intent", "summary", "candidates"],
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
