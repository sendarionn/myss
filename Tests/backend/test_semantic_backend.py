import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Sources/myss/Backend"))
from semantic_backend import order_headword_senses, resolve_intent  # noqa: E402

LOOKUP = {"敷衍": [0], "リリース": [1, 2], "プリンス オヴ ウェールズ": [3], "決める": [4]}


class ResolveIntentTests(unittest.TestCase):
    def test_headword_only(self):
        self.assertEqual(resolve_intent("敷衍", "", LOOKUP), {"intent": "wordMeaning", "query": "敷衍", "headword": "敷衍"})

    def test_headword_with_manual_context(self):
        result = resolve_intent("リリース　ビジネスでの文脈", "", LOOKUP)
        self.assertEqual(result["intent"], "wordMeaningWithContext")
        self.assertEqual(result["headword"], "リリース")
        self.assertEqual(result["context"], "ビジネスでの文脈")

    def test_headword_containing_space_is_matched_first(self):
        result = resolve_intent("プリンス オヴ ウェールズ 歴史", "", LOOKUP)
        self.assertEqual(result["headword"], "プリンス オヴ ウェールズ")
        self.assertEqual(result["context"], "歴史")

    def test_captured_context_is_combined_with_manual_context(self):
        result = resolve_intent("リリース 営業資料で使う意味", "SaaSの新機能を来週公開する。", LOOKUP)
        self.assertEqual(result["context"], "SaaSの新機能を来週公開する。\n営業資料で使う意味")

    def test_captured_context_alone_makes_context_intent(self):
        result = resolve_intent("リリース", "新製品のリリース時期を来月に変更する。", LOOKUP)
        self.assertEqual(result["intent"], "wordMeaningWithContext")
        self.assertEqual(result["context"], "新製品のリリース時期を来月に変更する。")

    def test_short_phrase_not_in_dictionary_is_meaning_search(self):
        self.assertEqual(resolve_intent("自分で決める", "", LOOKUP)["intent"], "meaningToWord")

    def test_description_is_meaning_search_and_ignores_captured_context(self):
        result = resolve_intent("製品を公開すること", "新製品の発表", LOOKUP)
        self.assertEqual(result, {"intent": "meaningToWord", "query": "製品を公開すること"})

    def test_unknown_first_token_is_meaning_search(self):
        self.assertEqual(resolve_intent("問題を 一時的に抑える", "", LOOKUP)["intent"], "meaningToWord")


class OrderHeadwordSensesTests(unittest.TestCase):
    def test_primary_headword_senses_come_first(self):
        records = [{"headword": "発売"}, {"headword": "リリース"}]
        self.assertEqual(order_headword_senses("リリース", [0, 1], records), [1, 0])


if __name__ == "__main__":
    unittest.main()
