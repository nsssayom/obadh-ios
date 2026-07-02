#!/usr/bin/env python3
from __future__ import annotations

import argparse
import struct
import json
import re
import unicodedata
import urllib.request
from dataclasses import dataclass
from pathlib import Path


EMOJI_TEST_URL = "https://unicode.org/Public/emoji/latest/emoji-test.txt"
CLDR_ANNOTATIONS_URL = (
    "https://raw.githubusercontent.com/unicode-org/cldr-json/main/"
    "cldr-json/cldr-annotations-full/annotations/en/annotations.json"
)
EMOJI_BIN_MAGIC = b"OBEMOJI1"
EMOJI_BIN_VERSION = 1
KEYWORD_SEPARATOR = "\x1f"
CATEGORY_CODES = {
    "Smileys & Emotion": 1,
    "People & Body": 2,
    "Animals & Nature": 3,
    "Food & Drink": 4,
    "Activities": 5,
    "Travel & Places": 6,
    "Objects": 7,
    "Symbols": 8,
    "Flags": 9,
}


@dataclass(frozen=True)
class EmojiRecord:
    emoji: str
    group: str
    subgroup: str
    name: str
    keywords: tuple[str, ...]


def fetch_text(url: str) -> str:
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read().decode("utf-8")


def load_annotations(url: str) -> dict[str, dict[str, list[str]]]:
    payload = json.loads(fetch_text(url))
    return payload["annotations"]["annotations"]


def clean_field(value: str) -> str:
    return re.sub(r"\s+", " ", value.replace("\t", " ")).strip()


def normalize(value: str) -> str:
    decomposed = unicodedata.normalize("NFKD", value.strip().lower())
    return "".join(character for character in decomposed if not unicodedata.combining(character))


def tokenise(value: str) -> list[str]:
    tokens = re.split(r"[^0-9a-zA-Z]+", normalize(value))
    return [token for token in tokens if token]


def parse_emoji_test(
    emoji_test: str,
    annotations: dict[str, dict[str, list[str]]],
) -> list[EmojiRecord]:
    group = ""
    subgroup = ""
    records: list[EmojiRecord] = []
    seen: set[str] = set()

    for raw_line in emoji_test.splitlines():
        line = raw_line.strip()
        if line.startswith("# group:"):
            group = clean_field(line.removeprefix("# group:"))
            continue
        if line.startswith("# subgroup:"):
            subgroup = clean_field(line.removeprefix("# subgroup:"))
            continue
        if not line or line.startswith("#") or "; fully-qualified" not in line:
            continue
        if group == "Component":
            continue

        _, comment = line.split("#", 1)
        parts = comment.strip().split(" ", 2)
        if len(parts) < 3:
            continue
        emoji = parts[0]
        version_and_name = parts[2]
        name = clean_field(version_and_name)

        annotation = annotations.get(emoji, {})
        tts_values = annotation.get("tts", [])
        default_values = annotation.get("default", [])
        if tts_values:
            name = clean_field(tts_values[0])

        keywords = []
        for value in [name, *default_values, *tts_values]:
            cleaned = clean_field(value).lower()
            if cleaned and cleaned not in keywords:
                keywords.append(cleaned)

        if emoji in seen:
            continue
        seen.add(emoji)
        records.append(
            EmojiRecord(
                emoji=emoji,
                group=group,
                subgroup=subgroup,
                name=name,
                keywords=tuple(keywords),
            )
        )

    return records


def write_tsv(records: list[EmojiRecord], destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("# emoji\tgroup\tsubgroup\tname\tkeywords\n")
        for record in records:
            keywords = ",".join(record.keywords)
            handle.write(
                "\t".join(
                    [
                        clean_field(record.emoji),
                        clean_field(record.group),
                        clean_field(record.subgroup),
                        clean_field(record.name),
                        clean_field(keywords),
                    ]
                )
                + "\n"
            )


def read_tsv(source: Path) -> list[EmojiRecord]:
    records: list[EmojiRecord] = []
    with source.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            columns = line.split("\t")
            if len(columns) < 5:
                continue
            records.append(
                EmojiRecord(
                    emoji=columns[0],
                    group=columns[1],
                    subgroup=columns[2],
                    name=columns[3],
                    keywords=tuple(keyword for keyword in columns[4].split(",") if keyword),
                )
            )
    return records


def write_binary(records: list[EmojiRecord], destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    strings = bytearray()
    string_offsets: dict[str, int] = {}

    def intern(value: str) -> int:
        if value in string_offsets:
            return string_offsets[value]
        offset = len(strings)
        string_offsets[value] = offset
        strings.extend(value.encode("utf-8"))
        strings.append(0)
        return offset

    item_records: list[tuple[int, tuple[int, ...]]] = []
    postings_by_token: dict[str, list[tuple[int, int]]] = {}

    for item_index, record in enumerate(records):
        normalized_name = normalize(record.name)
        normalized_keywords = []
        seen_keywords: set[str] = set()
        for keyword in record.keywords:
            for token in tokenise(keyword):
                if token not in seen_keywords:
                    seen_keywords.add(token)
                    normalized_keywords.append(token)
        search_text = normalize(
            " ".join([record.name, *record.keywords])
        )
        normalized_keywords_value = KEYWORD_SEPARATOR.join(normalized_keywords)
        category = CATEGORY_CODES.get(record.group, CATEGORY_CODES["Symbols"])
        item_records.append(
            (
                category,
                (
                    intern(clean_field(record.emoji)),
                    intern(clean_field(record.group)),
                    intern(clean_field(record.subgroup)),
                    intern(clean_field(record.name)),
                    intern(",".join(clean_field(keyword) for keyword in record.keywords)),
                    intern(normalized_name),
                    intern(normalized_keywords_value),
                    intern(search_text),
                ),
            )
        )

        best_weight_by_token: dict[str, int] = {}
        for token in tokenise(normalized_name):
            if len(token) > 1:
                best_weight_by_token[token] = min(best_weight_by_token.get(token, 99), 0)
        for token in normalized_keywords:
            if len(token) > 1:
                best_weight_by_token[token] = min(best_weight_by_token.get(token, 99), 2)
        for token in tokenise(record.subgroup):
            if len(token) > 1:
                best_weight_by_token[token] = min(best_weight_by_token.get(token, 99), 5)
        for token, weight in best_weight_by_token.items():
            postings_by_token.setdefault(token, []).append((item_index, weight))

    token_records: list[tuple[int, int, int]] = []
    posting_records: list[tuple[int, int]] = []
    for token in sorted(postings_by_token):
        start = len(posting_records)
        postings = sorted(postings_by_token[token])
        posting_records.extend(postings)
        token_records.append((intern(token), start, len(postings)))

    header_size = 44
    item_size = 36
    token_size = 12
    posting_size = 8
    item_offset = header_size
    token_offset = item_offset + len(item_records) * item_size
    posting_offset = token_offset + len(token_records) * token_size
    string_offset = posting_offset + len(posting_records) * posting_size

    payload = bytearray()
    payload.extend(
        struct.pack(
            "<8sIIIIIIIII",
            EMOJI_BIN_MAGIC,
            EMOJI_BIN_VERSION,
            len(item_records),
            len(token_records),
            len(posting_records),
            item_offset,
            token_offset,
            posting_offset,
            string_offset,
            len(strings),
        )
    )

    for category, offsets in item_records:
        payload.extend(struct.pack("<BBBBIIIIIIII", category, 0, 0, 0, *offsets))
    for token_string_offset, posting_start, posting_count in token_records:
        payload.extend(struct.pack("<III", token_string_offset, posting_start, posting_count))
    for item_index, weight in posting_records:
        payload.extend(struct.pack("<IHH", item_index, weight, 0))
    payload.extend(strings)

    destination.write_bytes(payload)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Obadh emoji resources from Unicode/CLDR data.")
    parser.add_argument(
        "--input-tsv",
        type=Path,
        help="Compile from an existing TSV instead of fetching Unicode/CLDR data.",
    )
    parser.add_argument(
        "--emoji-test-url",
        default=EMOJI_TEST_URL,
        help="Unicode emoji-test.txt URL.",
    )
    parser.add_argument(
        "--annotations-url",
        default=CLDR_ANNOTATIONS_URL,
        help="CLDR English annotations JSON URL.",
    )
    parser.add_argument(
        "--output",
        default="Data/emoji/emoji.tsv",
        type=Path,
        help="Destination source TSV path.",
    )
    parser.add_argument(
        "--binary-output",
        default="Resources/ObadhModels/emoji/emoji.bin",
        type=Path,
        help="Destination compiled binary path.",
    )
    args = parser.parse_args()

    if args.input_tsv:
        records = read_tsv(args.input_tsv)
    else:
        annotations = load_annotations(args.annotations_url)
        records = parse_emoji_test(fetch_text(args.emoji_test_url), annotations)
        write_tsv(records, args.output)
        print(f"Wrote {len(records):,} emoji records to {args.output}")

    write_binary(records, args.binary_output)
    print(f"Wrote {len(records):,} emoji records to {args.binary_output}")


if __name__ == "__main__":
    main()
