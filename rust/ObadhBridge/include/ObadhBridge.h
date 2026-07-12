#ifndef ObadhBridge_h
#define ObadhBridge_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

size_t obadh_bridge_version_utf8(uint8_t *_Nullable output_ptr, size_t output_capacity);

size_t obadh_transliterate_utf8(
    const uint8_t *_Nullable input_ptr,
    size_t input_len,
    uint8_t *_Nullable output_ptr,
    size_t output_capacity
);

size_t obadh_transliterate_lenient_utf8(
    const uint8_t *_Nullable input_ptr,
    size_t input_len,
    uint8_t *_Nullable output_ptr,
    size_t output_capacity
);

size_t obadh_composition_suggestions_utf8(
    const uint8_t *_Nullable roman_ptr,
    size_t roman_len,
    size_t limit,
    uint8_t *_Nullable output_ptr,
    size_t output_capacity
);

bool obadh_configure_autocorrect_utf8(
    const uint8_t *_Nullable fst_path_ptr,
    size_t fst_path_len,
    const uint8_t *_Nullable loanword_path_ptr,
    size_t loanword_path_len
);

bool obadh_configure_autosuggest_utf8(
    const uint8_t *_Nullable artifact_path_ptr,
    size_t artifact_path_len
);

size_t obadh_autocorrect_suggestions_utf8(
    const uint8_t *_Nullable roman_ptr,
    size_t roman_len,
    size_t limit,
    uint8_t *_Nullable output_ptr,
    size_t output_capacity
);

size_t obadh_is_lexicon_word_utf8(
    const uint8_t *_Nullable word_ptr,
    size_t word_len
);

size_t obadh_word_alternatives_utf8(
    const uint8_t *_Nullable word_ptr,
    size_t word_len,
    size_t limit,
    uint8_t *_Nullable output_ptr,
    size_t output_capacity
);

size_t obadh_autosuggest_suggestions_utf8(
    const uint8_t *_Nullable context_ptr,
    size_t context_len,
    size_t limit,
    uint8_t *_Nullable output_ptr,
    size_t output_capacity
);

size_t obadh_autosuggest_session_suggestions_utf8(
    size_t limit,
    uint8_t *_Nullable output_ptr,
    size_t output_capacity
);

bool obadh_autosuggest_commit_token_utf8(
    const uint8_t *_Nullable token_ptr,
    size_t token_len
);

void obadh_autosuggest_clear_session(void);

void obadh_autosuggest_clear_personal(void);

size_t obadh_autosuggest_personal_snapshot_len(void);

size_t obadh_autosuggest_export_personal_snapshot(
    uint8_t *_Nullable output_ptr,
    size_t output_capacity
);

bool obadh_autosuggest_import_personal_snapshot(
    const uint8_t *_Nullable input_ptr,
    size_t input_len
);

#ifdef __cplusplus
}
#endif

#endif
