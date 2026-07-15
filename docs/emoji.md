# Emoji: suggestions, search, and the data pipeline

The most portable part of the iOS codebase: the build pipeline, the ranking,
and the binary format have no iOS dependency and are directly reusable on
other platforms.

## Inline suggestions

When a Bangla word is being composed, up to three emoji appear in the
ribbon's third slot (the top two text candidates always survive), matching
the native keyboard. Tapping one **replaces** the composed word, because the
typed text was the emoji's query ("bhalobasha" + tap yields ❤️, not the word
plus the emoji), and the discarded query is not committed to autosuggest
learning.

## The data pipeline

Data is built offline by `scripts/generate-emoji-data.py` from Unicode CLDR
Bengali annotations laid *under* a hand-curated colloquial map: CLDR is
descriptive (হার্ট = heart) while people type colloquially (ভালোবাসা = love).
Candidates are ranked by name-centrality first (an emoji whose *primary
name* is the word beats one that merely mentions it, so নাক → 👃, not 😤),
then by Unicode usage frequency, which is used at build time only and never
ships.

The runtime artifact is a small sorted-key binary (word → up to 3 emoji)
answered by exact binary search.

## Search

The emoji key opens a local Unicode/CLDR panel with categories, recents, and
search. Search runs in English by default with an in-bar EN⇄BN toggle (the
default lives in the app's settings). The Bangla side reuses the suggestion
pipeline as a broader index with prefix and multi-term matching, plus a fuzzy
fallback: grapheme edit-distance against the closed keyword vocabulary,
which is safe to be aggressive with because the only candidates are emoji
keywords. Skin tones are picked by long-press and remembered per-emoji.

## Performance discipline

The typing path never touches the ~1 MB emoji catalog; inline suggestions are
a memory-mapped binary search over a ~110 KB index. The Bangla search index
(and its fuzzy fallback) load only when search is switched to Bangla, so the
English default pays nothing.
