#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import tarfile
import urllib.request
import xml.etree.ElementTree as ET

WORDNET_URL = "https://bond-lab.github.io/wnja/"
WORDNET_ATTRIBUTION = "日本語ワードネット 2.1"
MODEL_ID = "cl-nagoya/ruri-v3-70m"
WORDNET_ARCHIVE_URL = "https://github.com/bond-lab/wnja/releases/download/v2.1/wnja-2.1.tar.xz"


def parse_wordnet(xml_path: Path):
    synset_words = {}
    records = []
    for _, element in ET.iterparse(xml_path, events=("end",)):
        tag = element.tag.rsplit("}", 1)[-1]
        if tag == "LexicalEntry":
            lemma = element.find("Lemma")
            if lemma is not None:
                headword = lemma.get("writtenForm", "")
                part_of_speech = lemma.get("partOfSpeech")
                forms = [
                    form.get("writtenForm", "")
                    for form in element.findall("Form")
                    if not form.get("script")
                ]
                for sense in element.findall("Sense"):
                    synset_id = sense.get("synset")
                    if not synset_id:
                        continue
                    count = sum(int(node.text or "0") for node in sense.findall("Count"))
                    synset_words.setdefault(synset_id, []).append({
                        "headword": headword,
                        "partOfSpeech": part_of_speech,
                        "forms": forms,
                        "count": count,
                    })
            element.clear()
        elif tag == "Synset":
            synset_id = element.get("id", "")
            words = synset_words.get(synset_id, [])
            definitions = [node.text.strip() for node in element.findall("Definition") if node.text and node.text.strip()]
            examples = [node.text.strip() for node in element.findall("Example") if node.text and node.text.strip()]
            if words and definitions:
                words.sort(key=lambda item: (-item["count"], len(item["headword"]), item["headword"]))
                primary = words[0]
                aliases = []
                for word in words:
                    candidates = ([word["headword"]] if word is not primary else []) + word["forms"]
                    for candidate in candidates:
                        if candidate and candidate != primary["headword"] and candidate not in aliases:
                            aliases.append(candidate)
                records.append({
                    "id": synset_id,
                    "headword": primary["headword"],
                    "partOfSpeech": primary["partOfSpeech"],
                    "summary": definitions[0],
                    "definitions": definitions,
                    "aliases": aliases,
                    "examples": examples,
                    "relatedWords": [],
                })
            element.clear()
    return records


def mps_available():
    try:
        import torch
        return torch.backends.mps.is_available()
    except Exception:
        return False


def build_index(xml_path: Path, output_path: Path, batch_size: int):
    import numpy as np
    from sentence_transformers import SentenceTransformer

    records = parse_wordnet(xml_path)
    documents = []
    for record in records:
        aliases = "、".join(record["aliases"][:12])
        examples = "。".join(record["examples"][:3])
        documents.append(f"検索文書: {record['headword']}。{record['summary']}。類義語: {aliases}。用例: {examples}")
    print(f"myss backend: loading {MODEL_ID}", flush=True)
    model = SentenceTransformer(MODEL_ID, device="mps" if mps_available() else "cpu")
    embeddings = model.encode(
        documents,
        batch_size=batch_size,
        normalize_embeddings=True,
        show_progress_bar=True,
    ).astype(np.float16)
    output_path.mkdir(parents=True, exist_ok=True)
    np.save(output_path / "embeddings.npy", embeddings)
    (output_path / "senses.json").write_text(
        json.dumps(records, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )
    finalize_metadata(output_path, len(records), embeddings.shape[1])
    print(f"myss backend: indexed {len(records)} lexical senses", flush=True)


def finalize_metadata(output_path: Path, sense_count=None, dimensions=384):
    senses_path = output_path / "senses.json"
    embeddings_path = output_path / "embeddings.npy"
    digest = hashlib.sha256()
    for path in (senses_path, embeddings_path):
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    if sense_count is None:
        sense_count = len(json.loads(senses_path.read_text(encoding="utf-8")))
    metadata = {
        "indexVersion": "1",
        "wordnetVersion": "2.1",
        "model": MODEL_ID,
        "embeddingDimensions": dimensions,
        "senseCount": sense_count,
        "sha256": digest.hexdigest(),
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }
    (output_path / "metadata.json").write_text(json.dumps(metadata, ensure_ascii=False), encoding="utf-8")


def prepare_model():
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer(MODEL_ID, device="cpu")
    vector = model.encode(["検索クエリ: 動作確認"], normalize_embeddings=True)
    if vector.shape != (1, 384):
        raise RuntimeError(f"unexpected Ruri embedding shape: {vector.shape}")
    print(json.dumps({"model": MODEL_ID, "dimensions": 384}), flush=True)


def setup(data_path: Path, downloads_path: Path, batch_size: int):
    downloads_path.mkdir(parents=True, exist_ok=True)
    archive_path = downloads_path / "wnja-2.1.tar.xz"
    xml_path = downloads_path / "wnja" / "wnja-2.1.xml"
    if not xml_path.exists():
        if not archive_path.exists():
            urllib.request.urlretrieve(WORDNET_ARCHIVE_URL, archive_path)
        with tarfile.open(archive_path, "r:xz") as archive:
            target = downloads_path.resolve()
            for member in archive.getmembers():
                destination = (downloads_path / member.name).resolve()
                if target not in destination.parents and destination != target:
                    raise ValueError("invalid WordNet archive path")
            archive.extractall(downloads_path)
    build_index(xml_path, data_path, batch_size)


class SearchRuntime:
    def __init__(self, data_path: Path):
        import numpy as np
        from sentence_transformers import SentenceTransformer

        self.records = json.loads((data_path / "senses.json").read_text(encoding="utf-8"))
        self.embeddings = np.load(data_path / "embeddings.npy", mmap_mode="r")
        self.model = SentenceTransformer(
            MODEL_ID,
            device="mps" if mps_available() else "cpu",
            local_files_only=True,
        )
        self.word_lookup = {}
        for index, record in enumerate(self.records):
            for word in [record["headword"], *record["aliases"]]:
                self.word_lookup.setdefault(word, []).append(index)

    def search(self, query: str, captured_context: str, limit: int):
        resolved = resolve_intent(query, captured_context, self.word_lookup)
        if resolved["intent"] == "meaningToWord":
            indexes, scores = self.semantic_search(resolved["query"], limit)
        else:
            indexes, scores = self.headword_senses(resolved["headword"], resolved.get("context"))
        senses = []
        for index, score in zip(indexes, scores):
            record = dict(self.records[index])
            headword = resolved.get("headword")
            if headword and headword != record["headword"] and headword in record["aliases"]:
                original_headword = record["headword"]
                record["headword"] = headword
                record["aliases"] = [original_headword, *[value for value in record["aliases"] if value != headword]]
            record["score"] = score
            record["sources"] = [{
                "name": WORDNET_ATTRIBUTION,
                "text": record["summary"],
                "url": WORDNET_URL,
                "license": "WordNet-style permissive license",
            }]
            senses.append(record)
        return {**resolved, "senses": senses, "phase": "embedding"}

    def encode_query(self, text: str):
        import numpy as np
        return self.model.encode([f"検索クエリ: {text}"], normalize_embeddings=True)[0].astype(np.float32)

    def semantic_search(self, query: str, limit: int):
        import numpy as np

        scores_all = self.embeddings @ self.encode_query(query)
        candidate_count = min(limit, len(scores_all))
        indexes = np.argpartition(scores_all, -candidate_count)[-candidate_count:]
        indexes = indexes[np.argsort(scores_all[indexes])[::-1]].tolist()
        return indexes, [float(scores_all[index]) for index in indexes]

    def headword_senses(self, headword: str, context):
        import numpy as np

        indexes = order_headword_senses(headword, self.word_lookup.get(headword, []), self.records)
        indexes = indexes[:MAX_HEADWORD_SENSES]
        if not context or len(indexes) < 2:
            return indexes, [1.0] * len(indexes)
        scores = np.asarray(self.embeddings[indexes], dtype=np.float32) @ self.encode_query(context)
        ranked = sorted(zip(indexes, scores.tolist()), key=lambda item: -item[1])
        return [index for index, _ in ranked], [float(score) for _, score in ranked]


MAX_HEADWORD_SENSES = 50


def normalize_query(text: str) -> str:
    return " ".join(text.split())


def resolve_intent(query: str, captured_context: str, word_lookup):
    normalized = normalize_query(query)
    captured = (captured_context or "").strip()
    headword, manual_context = None, None
    if normalized in word_lookup:
        headword = normalized
    else:
        tokens = normalized.split(" ")
        for count in range(len(tokens) - 1, 0, -1):
            candidate = " ".join(tokens[:count])
            if candidate in word_lookup:
                headword, manual_context = candidate, " ".join(tokens[count:])
                break
    if headword is None:
        return {"intent": "meaningToWord", "query": normalized}
    context = "\n".join(value for value in (captured, manual_context) if value)
    if not context:
        return {"intent": "wordMeaning", "query": normalized, "headword": headword}
    return {"intent": "wordMeaningWithContext", "query": normalized, "headword": headword, "context": context}


def order_headword_senses(headword: str, indexes, records):
    return sorted(indexes, key=lambda index: records[index]["headword"] != headword)


def serve(data_path: Path, port: int):
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    runtime = SearchRuntime(data_path)
    metadata_path = data_path / "metadata.json"
    metadata = json.loads(metadata_path.read_text()) if metadata_path.exists() else {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/health":
                self.send_error(404)
                return
            self.send_json(200, {
                "ready": True,
                "model": metadata.get("model", MODEL_ID),
                "senseCount": metadata.get("senseCount", len(runtime.records)),
                "message": None,
            })

        def do_POST(self):
            if self.path != "/search":
                self.send_error(404)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length))
                result = runtime.search(
                    str(body.get("query", "")),
                    str(body.get("capturedContext") or ""),
                    max(1, min(int(body.get("limit", 10)), 20)),
                )
                self.send_json(200, result)
            except Exception as error:
                self.send_json(500, {"error": str(error)})

        def send_json(self, status, value):
            data = json.dumps(value, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, format, *args):
            print("myss backend:", format % args, flush=True)

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"myss backend: ready on 127.0.0.1:{port}", flush=True)
    server.serve_forever()


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    build = subparsers.add_parser("build")
    build.add_argument("--xml", required=True, type=Path)
    build.add_argument("--output", required=True, type=Path)
    build.add_argument("--batch-size", type=int, default=64)
    setup_parser = subparsers.add_parser("setup")
    setup_parser.add_argument("--data", required=True, type=Path)
    setup_parser.add_argument("--downloads", required=True, type=Path)
    setup_parser.add_argument("--batch-size", type=int, default=64)
    subparsers.add_parser("prepare-model")
    finalize_parser = subparsers.add_parser("finalize-metadata")
    finalize_parser.add_argument("--data", required=True, type=Path)
    parse = subparsers.add_parser("parse")
    parse.add_argument("--xml", required=True, type=Path)
    serve_parser = subparsers.add_parser("serve")
    serve_parser.add_argument("--data", required=True, type=Path)
    serve_parser.add_argument("--port", type=int, default=52791)
    args = parser.parse_args()
    if args.command == "build":
        build_index(args.xml, args.output, args.batch_size)
    elif args.command == "setup":
        setup(args.data, args.downloads, args.batch_size)
    elif args.command == "prepare-model":
        prepare_model()
    elif args.command == "finalize-metadata":
        finalize_metadata(args.data)
    elif args.command == "parse":
        records = parse_wordnet(args.xml)
        print(json.dumps({"senseCount": len(records), "sample": records[:2]}, ensure_ascii=False))
    else:
        serve(args.data, args.port)


if __name__ == "__main__":
    main()
