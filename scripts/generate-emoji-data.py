#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import urllib.request
from dataclasses import dataclass
from pathlib import Path


EMOJI_TEST_URL = "https://unicode.org/Public/emoji/latest/emoji-test.txt"
CLDR_ANNOTATIONS_URL = (
    "https://raw.githubusercontent.com/unicode-org/cldr-json/main/"
    "cldr-json/cldr-annotations-full/annotations/en/annotations.json"
)


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


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Obadh emoji TSV from Unicode/CLDR data.")
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
        default="Resources/ObadhModels/emoji/emoji.tsv",
        type=Path,
        help="Destination TSV path.",
    )
    args = parser.parse_args()

    annotations = load_annotations(args.annotations_url)
    records = parse_emoji_test(fetch_text(args.emoji_test_url), annotations)
    write_tsv(records, args.output)
    print(f"Wrote {len(records):,} emoji records to {args.output}")


if __name__ == "__main__":
    main()
