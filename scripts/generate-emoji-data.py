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


# ---------------------------------------------------------------------------
# Bangla "type-as-you-go" emoji suggestion artifact (emoji-bn.bin, OBEMOJIBN1).
#
# A tiny sorted-key binary mapping a normalized Bangla WORD -> up to 3 emoji
# (best first). Built from a hand-curated colloquial map (the quality core) laid
# over CLDR Bengali annotations (coverage). The Unicode emoji-frequency ranking
# is used ONLY here at build time to order/choose emoji — nothing frequency-
# related ships, so there's zero runtime cost or memory. Consumed by
# BanglaEmojiSuggestionStore via exact binary search.
# ---------------------------------------------------------------------------

CLDR_ANNOTATIONS_BN_URL = (
    "https://raw.githubusercontent.com/unicode-org/cldr-json/main/"
    "cldr-json/cldr-annotations-full/annotations/bn/annotations.json"
)
CLDR_ANNOTATIONS_DERIVED_BN_URL = (
    "https://raw.githubusercontent.com/unicode-org/cldr-json/main/"
    "cldr-json/cldr-annotations-derived-full/annotationsDerived/bn/annotations.json"
)
EMOJI_FREQUENCY_URL = "https://home.unicode.org/emoji/emoji-frequency/"
EMOJI_BN_BIN_MAGIC = b"OBEMOJIBN1"
EMOJI_BN_BIN_VERSION = 1
EMOJI_DATA_VERSION = 1700  # Emoji 17.0
EMOJI_BN_SEPARATOR = "\x1f"  # joins the (up to 3) emoji in a record's value
MAX_EMOJI_PER_WORD = 3
# A word earns a mapping if it NAMES an emoji centrally — appears in a tts (primary
# name) of at most this many tokens (1 = the emoji's whole name is the word) — or
# is unambiguous (maps to at most UNAMBIGUOUS_DF emoji). This keeps concrete nouns
# (নাক→👃, হাত→👋) and gets their ORDER right, without a blunt frequency count.
PRIMARY_TTS_MAX_SPAN = 3
UNAMBIGUOUS_DF = 2
ZWNJ = "‌"
ZWJ = "‍"

# Truly generic Bangla annotation tokens that carry no emoji signal on their own
# (they describe a body part / category shared by many emoji). Everything else in
# CLDR is trusted; the df ceiling above is the backstop for the rest.
GENERIC_BANGLA_TOKENS = {
    # Only genuinely abstract / grammatical / category words that smear across
    # many emoji with no single natural choice. Concrete nouns are deliberately
    # NOT blocked (হাত→👋, চোখ→👀, নাক→👃, কান→👂) — the df backstop plus the
    # primary-name (tts) + frequency ranking pick a good emoji for those.
    "মুখ", "শরীর",            # face / body — primary name of dozens of (animal) faces
    "রঙ", "রং", "রঙের",       # color
    "জিনিস", "বস্তু", "সরঞ্জাম",  # thing / object / tool
    "মানুষ", "ব্যক্তি", "লোক",   # person / human
    "প্রাণী", "পশু", "পশুপাখি",  # animal (category)
    "চিহ্ন", "প্রতীক",         # sign / symbol
    "ধরন", "ধরনের", "রকম",     # type / kind
    "একটি", "একটা",           # a / one
}


def normalize_bangla(value: str) -> str:
    """Byte-for-byte identical to BanglaEmojiSuggestionStore.normalize in Swift:
    NFC, strip ZWNJ/ZWJ, trim. (Do NOT strip combining marks — Bangla matras are
    essential, unlike the Latin `normalize` above.)"""
    composed = unicodedata.normalize("NFC", value.strip())
    composed = composed.replace(ZWNJ, "").replace(ZWJ, "")
    return composed.strip()


def load_curated_bangla_emoji() -> dict[str, str]:
    import sys as _sys

    _sys.path.insert(0, str(Path(__file__).resolve().parent))
    from curated_bangla_emoji import CURATED_BANGLA_EMOJI  # type: ignore

    return {normalize_bangla(word): emoji for word, emoji in CURATED_BANGLA_EMOJI.items()}


# Emoji skin-tone modifiers U+1F3FB…U+1F3FF. Suggestions use base/neutral emoji
# only — a specific skin tone is never imposed, and variants would look like
# duplicates (🙏 🙏🏻 🙏🏼).
SKIN_TONE_MODIFIERS = ("🏻", "🏼", "🏽", "🏾", "🏿")


def has_skin_tone(emoji: str) -> bool:
    return any(modifier in emoji for modifier in SKIN_TONE_MODIFIERS)


def load_cldr_bn() -> dict[str, dict[str, list[str]]]:
    # Only the BASE annotations. The DERIVED file is skin-tone/gender variants,
    # which we deliberately don't suggest (they'd surface as near-duplicate emoji);
    # dropping it also keeps the artifact leaner.
    try:
        payload = json.loads(fetch_text(CLDR_ANNOTATIONS_BN_URL))
        entries = payload["annotations"]["annotations"]
    except Exception as error:  # noqa: BLE001
        print(f"  (CLDR bn unavailable: {error})")
        return {}
    return {
        emoji: {"tts": annotation.get("tts", []), "default": annotation.get("default", [])}
        for emoji, annotation in entries.items()
    }


def load_emoji_frequency_rank() -> dict[str, int]:
    """emoji -> rank (lower = more used), scraped in document order from Unicode's
    frequency page. Best-effort: an empty dict just means we fall back to Unicode
    emoji-test order for tie-breaks. Build-time only."""
    try:
        html = fetch_text(EMOJI_FREQUENCY_URL)
    except Exception as error:  # noqa: BLE001
        print(f"  (emoji frequency unavailable, using catalog order: {error})")
        return {}
    emoji_pattern = re.compile(
        "[\U0001F300-\U0001FAFF\U00002600-\U000027BF\U0001F1E6-\U0001F1FF"
        "\U00002190-\U000021FF\U00002B00-\U00002BFF\U0000FE0F\U0000200D]+"
    )
    rank: dict[str, int] = {}
    order = 0
    for match in emoji_pattern.findall(html):
        token = match.strip("️‍")
        if token and token not in rank:
            rank[token] = order
            order += 1
    return rank


def bangla_tokens(text: str) -> list[str]:
    """Split a (possibly multi-word) annotation into normalized Bangla word
    tokens — this is how multi-word annotations are handled."""
    tokens: list[str] = []
    for part in re.split(r"[\s,;/|()৷।+\-–—:]+", text):
        token = normalize_bangla(part)
        if len(token) < 2:
            continue
        if not any("ঀ" <= character <= "৿" for character in token):
            continue
        tokens.append(token)
    return tokens


# Candidate source tiers (lower = stronger). Curated is an intentional human
# choice; a CLDR primary-name (tts) match is stronger than a mere keyword match.
TIER_CURATED = 0
TIER_CLDR_PRIMARY = 1
TIER_CLDR_KEYWORD = 2


def build_bangla_emoji_map(
    records: list[EmojiRecord],
    cldr_bn: dict[str, dict[str, list[str]]],
    frequency_rank: dict[str, int],
    curated: dict[str, str],
) -> tuple[dict[str, list[str]], dict[str, int]]:
    """Word -> up to 3 emoji. Every candidate (curated or CLDR) is collected with
    a source tier, then ordered by (tier, Unicode frequency). Curated leads
    because it's deliberate, but frequency is a consistent, credible secondary
    sort for everything — so the curated list is a first-class ranked input, not
    a bypass. Returns the map plus stats for auditability."""
    from collections import defaultdict

    catalog_order = {record.emoji: index for index, record in enumerate(records)}

    def frequency_key(emoji: str) -> tuple[int, int]:
        # Lower is better: real usage frequency first, then Unicode catalog order.
        return (frequency_rank.get(emoji, 10_000), catalog_order.get(emoji, 10_000))

    # word -> {emoji: rank tuple}; the lowest tuple wins. Rank =
    #   (tier, primary_span, frequency_rank, catalog_order)
    #   tier         : 0 curated, 1 CLDR primary-name (tts), 2 CLDR keyword
    #   primary_span : token count of the SHORTEST tts naming the emoji — 1 means
    #                  the emoji's whole name IS the word (নাক→👃 beats 😤, whose
    #                  tts merely mentions নাক); large for keyword-only matches.
    candidates: dict[str, dict[str, tuple]] = defaultdict(dict)

    def consider(word: str, emoji: str, rank: tuple) -> None:
        current = candidates[word].get(emoji)
        if current is None or rank < current:
            candidates[word][emoji] = rank

    # Per token: shortest tts span per emoji (primary), keyword owners, and df.
    token_primary_span: dict[str, dict[str, int]] = defaultdict(dict)
    token_keyword: dict[str, set[str]] = defaultdict(set)
    token_df: dict[str, set[str]] = defaultdict(set)
    for record in records:
        if has_skin_tone(record.emoji):
            continue  # suggest base/neutral emoji only
        annotation = cldr_bn.get(record.emoji)
        if not annotation:
            continue
        for phrase in annotation.get("tts", []):
            tokens = bangla_tokens(phrase)
            for token in tokens:
                token_df[token].add(record.emoji)
                span = token_primary_span[token].get(record.emoji)
                if span is None or len(tokens) < span:
                    token_primary_span[token][record.emoji] = len(tokens)
        for phrase in annotation.get("default", []):
            for token in bangla_tokens(phrase):
                token_df[token].add(record.emoji)
                token_keyword[token].add(record.emoji)

    # A token earns a mapping only if it NAMES an emoji centrally (a short tts) or
    # is unambiguous (very few emoji) — not merely because it's a keyword on many.
    for token, owners in token_df.items():
        if token in GENERIC_BANGLA_TOKENS:
            continue
        primary = token_primary_span.get(token, {})
        has_central_primary = any(span <= PRIMARY_TTS_MAX_SPAN for span in primary.values())
        if not (has_central_primary or len(owners) <= UNAMBIGUOUS_DF):
            continue
        for emoji, span in primary.items():
            consider(token, emoji, (TIER_CLDR_PRIMARY, span) + frequency_key(emoji))
        for emoji in token_keyword.get(token, set()):
            if emoji not in primary:
                consider(token, emoji, (TIER_CLDR_KEYWORD, 99) + frequency_key(emoji))

    # Curated colloquial layer (top tier, always leads).
    for word, emoji in curated.items():
        consider(word, emoji, (TIER_CURATED, 0, 0, 0))

    mapping: dict[str, list[str]] = {}
    curated_words = 0
    for word, emoji_ranks in candidates.items():
        ordered = sorted(emoji_ranks.items(), key=lambda item: item[1])
        # Dedup presentation variants (e.g. ❤ vs ❤️ differ only by U+FE0F but look
        # identical) so a word never shows two of the "same" emoji. The list is
        # already best-first, so keep the first of each canonical form.
        deduped: list[str] = []
        seen_canonical: set[str] = set()
        for emoji, _ in ordered:
            canonical = emoji.replace("\ufe0f", "")  # strip VS16 (presentation selector)
            for modifier in SKIN_TONE_MODIFIERS:
                canonical = canonical.replace(modifier, "")
            if canonical in seen_canonical:
                continue
            seen_canonical.add(canonical)
            deduped.append(emoji)
            if len(deduped) == MAX_EMOJI_PER_WORD:
                break
        mapping[word] = deduped
        if any(rank[0] == TIER_CURATED for rank in emoji_ranks.values()):
            curated_words += 1

    stats = {
        "words": len(mapping),
        "curated_words": curated_words,
        "cldr_only_words": len(mapping) - curated_words,
        "with_frequency_rank": 1 if frequency_rank else 0,
    }
    return mapping, stats


MAX_SEARCH_EMOJI = 16


def build_bangla_search_map(
    records: list[EmojiRecord],
    cldr_bn: dict[str, dict[str, list[str]]],
    frequency_rank: dict[str, int],
) -> dict[str, list[str]]:
    """Bangla token -> up to 16 emoji, for the emoji-panel SEARCH (broad recall,
    unlike the high-precision suggestion map): every CLDR bn token is indexed
    (generics included — searching মুখ should find faces), ranked by primary-name
    centrality then frequency. Same OBEMOJIBN1 binary; the Swift store adds prefix
    + multi-term matching."""
    from collections import defaultdict

    catalog_order = {record.emoji: index for index, record in enumerate(records)}

    def frequency_key(emoji: str) -> tuple[int, int]:
        return (frequency_rank.get(emoji, 10_000), catalog_order.get(emoji, 10_000))

    candidates: dict[str, dict[str, tuple]] = defaultdict(dict)

    def consider(token: str, emoji: str, rank: tuple) -> None:
        current = candidates[token].get(emoji)
        if current is None or rank < current:
            candidates[token][emoji] = rank

    for record in records:
        if has_skin_tone(record.emoji):
            continue
        annotation = cldr_bn.get(record.emoji)
        if not annotation:
            continue
        for phrase in annotation.get("tts", []):
            tokens = bangla_tokens(phrase)
            for token in tokens:
                consider(token, record.emoji, (0, len(tokens)) + frequency_key(record.emoji))
        for phrase in annotation.get("default", []):
            for token in bangla_tokens(phrase):
                consider(token, record.emoji, (1, 99) + frequency_key(record.emoji))

    result: dict[str, list[str]] = {}
    for token, emoji_ranks in candidates.items():
        ordered = sorted(emoji_ranks.items(), key=lambda item: item[1])
        deduped: list[str] = []
        seen_canonical: set[str] = set()
        for emoji, _ in ordered:
            canonical = emoji.replace("️", "")
            for modifier in SKIN_TONE_MODIFIERS:
                canonical = canonical.replace(modifier, "")
            if canonical in seen_canonical:
                continue
            seen_canonical.add(canonical)
            deduped.append(emoji)
            if len(deduped) == MAX_SEARCH_EMOJI:
                break
        result[token] = deduped
    return result


def write_bangla_binary(mapping: dict[str, list[str]], destination: Path) -> tuple[int, int]:
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

    # Sorted by the key's UTF-8 bytes so the Swift side can binary-search bytewise.
    keys = sorted(mapping.keys(), key=lambda key: key.encode("utf-8"))
    key_records: list[tuple[int, int]] = []
    for key in keys:
        emoji_value = EMOJI_BN_SEPARATOR.join(mapping[key])  # already capped by the builder
        key_records.append((intern(key), intern(emoji_value)))

    header_size = 30
    key_records_offset = header_size
    string_blob_offset = key_records_offset + len(key_records) * 8

    payload = bytearray()
    payload.extend(
        struct.pack(
            "<10sHHIIII",
            EMOJI_BN_BIN_MAGIC,
            EMOJI_BN_BIN_VERSION,
            EMOJI_DATA_VERSION,
            len(key_records),
            key_records_offset,
            string_blob_offset,
            len(strings),
        )
    )
    for key_offset, emoji_offset in key_records:
        payload.extend(struct.pack("<II", key_offset, emoji_offset))
    payload.extend(strings)

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)
    return len(key_records), len(payload)


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
    parser.add_argument(
        "--bangla-binary-output",
        default="Resources/ObadhModels/emoji/emoji-bn.bin",
        type=Path,
        help="Destination Bangla suggestion binary (OBEMOJIBN1) path.",
    )
    parser.add_argument(
        "--bangla-search-output",
        default="Resources/ObadhModels/emoji/emoji-bn-search.bin",
        type=Path,
        help="Destination Bangla emoji-search index (OBEMOJIBN1) path.",
    )
    parser.add_argument(
        "--skip-bangla",
        action="store_true",
        help="Skip building the Bangla artifacts (needs network for CLDR bn).",
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

    if not args.skip_bangla:
        print("Building Bangla artifacts…")
        curated = load_curated_bangla_emoji()
        cldr_bn = load_cldr_bn()
        frequency_rank = load_emoji_frequency_rank()

        mapping, stats = build_bangla_emoji_map(records, cldr_bn, frequency_rank, curated)
        count, size = write_bangla_binary(mapping, args.bangla_binary_output)
        print(
            f"  suggestion: {count:,} words ({stats['curated_words']:,} curated + "
            f"{stats['cldr_only_words']:,} CLDR, frequency={'yes' if stats['with_frequency_rank'] else 'catalog-order'}) "
            f"→ {args.bangla_binary_output} ({size / 1024:.1f} KB)"
        )

        search_map = build_bangla_search_map(records, cldr_bn, frequency_rank)
        search_count, search_size = write_bangla_binary(search_map, args.bangla_search_output)
        print(f"  search: {search_count:,} tokens → {args.bangla_search_output} ({search_size / 1024:.1f} KB)")


if __name__ == "__main__":
    main()
