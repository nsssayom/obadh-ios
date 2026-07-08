use obadh_engine::{
    key_slip_repaired_outputs, roman_repaired_outputs, AutosuggestLm, AutosuggestOptions,
    AutosuggestSession, FstLexicon, FstLoanwordMatch, FstRepairedBaseline, FstSuggestOptions,
    LoanwordLexicon, LoanwordSearchOptions, ObadhEngine, PersonalAutosuggestConfig,
    RomanRepairOptions, FST_MAX_LEVENSHTEIN_DISTANCE,
};
use std::fs::File;
use std::path::Path;
use std::slice;
use std::sync::{Mutex, OnceLock};

static ENGINE: OnceLock<ObadhEngine> = OnceLock::new();
static AUTOCORRECT: OnceLock<AutocorrectAssets> = OnceLock::new();
static AUTOSUGGEST: OnceLock<AutosuggestAssets> = OnceLock::new();
static AUTOSUGGEST_SESSION: OnceLock<Mutex<AutosuggestSession<'static, memmap2::Mmap>>> =
    OnceLock::new();
const VERSION: &[u8] = env!("CARGO_PKG_VERSION").as_bytes();
const AUTOCORRECT_POOL_LIMIT: usize = 24;
const AUTOCORRECT_RESPONSE_LIMIT: usize = 5;
const AUTOSUGGEST_RESPONSE_LIMIT: usize = 5;

struct AutocorrectAssets {
    lexicon: FstLexicon<memmap2::Mmap>,
    loanwords: Option<LoanwordLexicon<Vec<u8>>>,
}

struct AutosuggestAssets {
    lm: AutosuggestLm<memmap2::Mmap>,
}

#[no_mangle]
pub extern "C" fn obadh_bridge_version_utf8(
    output_ptr: *mut u8,
    output_capacity: usize,
) -> usize {
    write_bytes(VERSION, output_ptr, output_capacity)
}

#[no_mangle]
pub extern "C" fn obadh_transliterate_utf8(
    input_ptr: *const u8,
    input_len: usize,
    output_ptr: *mut u8,
    output_capacity: usize,
) -> usize {
    let Some(input) = utf8_input(input_ptr, input_len) else {
        return 0;
    };
    let output = engine().transliterate(input);
    write_bytes(output.as_bytes(), output_ptr, output_capacity)
}

#[no_mangle]
pub extern "C" fn obadh_transliterate_lenient_utf8(
    input_ptr: *const u8,
    input_len: usize,
    output_ptr: *mut u8,
    output_capacity: usize,
) -> usize {
    let Some(input) = utf8_input(input_ptr, input_len) else {
        return 0;
    };
    let output = engine().transliterate_lenient(input);
    write_bytes(output.as_bytes(), output_ptr, output_capacity)
}

#[no_mangle]
pub extern "C" fn obadh_composition_suggestions_utf8(
    roman_ptr: *const u8,
    roman_len: usize,
    limit: usize,
    output_ptr: *mut u8,
    output_capacity: usize,
) -> usize {
    let Some(roman_input) = utf8_input(roman_ptr, roman_len) else {
        return 0;
    };
    if roman_input.trim().is_empty() {
        return 0;
    }

    let response_limit = limit.clamp(1, AUTOCORRECT_RESPONSE_LIMIT);
    let deterministic = engine().transliterate(roman_input);
    let mut candidates = Vec::with_capacity(response_limit);
    candidates.push(deterministic.clone());

    let correction_limit = response_limit.saturating_sub(1);
    if correction_limit > 0 {
        for candidate in autocorrect_candidates(roman_input, &deterministic, correction_limit) {
            if candidates.iter().all(|existing| existing != &candidate) {
                candidates.push(candidate);
                if candidates.len() == response_limit {
                    break;
                }
            }
        }
    }

    write_joined(candidates.into_iter().take(response_limit), output_ptr, output_capacity)
}

#[no_mangle]
pub extern "C" fn obadh_configure_autocorrect_utf8(
    fst_path_ptr: *const u8,
    fst_path_len: usize,
    loanword_path_ptr: *const u8,
    loanword_path_len: usize,
) -> bool {
    if AUTOCORRECT.get().is_some() {
        return true;
    }

    let Some(fst_path) = utf8_input(fst_path_ptr, fst_path_len) else {
        return false;
    };
    let loanword_path = utf8_input(loanword_path_ptr, loanword_path_len).filter(|path| !path.is_empty());

    let Ok(lexicon) = mmap_fst_lexicon(fst_path) else {
        return false;
    };
    let loanwords = match loanword_path {
        Some(path) => {
            let Ok(bytes) = std::fs::read(path) else {
                return false;
            };
            let Ok(loanwords) = LoanwordLexicon::from_bytes(bytes) else {
                return false;
            };
            Some(loanwords)
        }
        None => None,
    };

    AUTOCORRECT
        .set(AutocorrectAssets { lexicon, loanwords })
        .is_ok()
        || AUTOCORRECT.get().is_some()
}

#[no_mangle]
pub extern "C" fn obadh_configure_autosuggest_utf8(
    artifact_path_ptr: *const u8,
    artifact_path_len: usize,
) -> bool {
    if AUTOSUGGEST.get().is_none() {
        let Some(path) = utf8_input(artifact_path_ptr, artifact_path_len) else {
            return false;
        };
        let Ok(lm) = AutosuggestLm::from_path(path) else {
            return false;
        };

        if AUTOSUGGEST.set(AutosuggestAssets { lm }).is_err() && AUTOSUGGEST.get().is_none() {
            return false;
        }
    }

    configure_autosuggest_session()
}

#[no_mangle]
pub extern "C" fn obadh_autocorrect_suggestions_utf8(
    roman_ptr: *const u8,
    roman_len: usize,
    limit: usize,
    output_ptr: *mut u8,
    output_capacity: usize,
) -> usize {
    let Some(roman_input) = utf8_input(roman_ptr, roman_len) else {
        return 0;
    };
    if roman_input.trim().is_empty() {
        return 0;
    }

    let deterministic = engine().transliterate(roman_input);
    let candidates = autocorrect_candidates(
        roman_input,
        &deterministic,
        limit.clamp(1, AUTOCORRECT_RESPONSE_LIMIT),
    );
    write_joined(candidates.into_iter(), output_ptr, output_capacity)
}

fn autocorrect_candidates(
    roman_input: &str,
    obadh_output: &str,
    response_limit: usize,
) -> Vec<String> {
    let Some(assets) = AUTOCORRECT.get() else {
        return Vec::new();
    };
    let mut repaired_outputs = roman_repaired_outputs(
        roman_input,
        obadh_output,
        RomanRepairOptions::default(),
        |text| engine().transliterate(text),
    );
    // QWERTY fat-finger (key-slip) repairs: single adjacent-key rewrites of the
    // roman input whose transliteration is a real lexicon word. The helper gates
    // itself to non-word baselines (baseline_frequency == None) and lexicon-
    // validates each variant internally, so a correctly-typed word is never
    // second-guessed. Mirrors the engine's reference CLI/WASM wiring.
    repaired_outputs.extend(key_slip_repaired_outputs(
        roman_input,
        obadh_output,
        assets.lexicon.exact_frequency(obadh_output),
        |text| engine().transliterate(text),
        |word| assets.lexicon.exact_frequency(word).is_some(),
    ));
    let repaired_baselines = repaired_outputs
        .iter()
        .map(|repair| FstRepairedBaseline {
            roman_input: repair.roman_input.as_str(),
            bangla_output: repair.bangla_output.as_str(),
            repair_kind: repair.repair_kind,
            repair_cost: repair.repair_cost,
        })
        .collect::<Vec<_>>();
    let loanword_suggestions = match &assets.loanwords {
        Some(loanwords) => loanwords
            .suggestions(roman_input, LoanwordSearchOptions::for_input(roman_input))
            .unwrap_or_default(),
        None => Vec::new(),
    };
    let loanword_matches = loanword_suggestions
        .iter()
        .map(|entry| FstLoanwordMatch {
            roman_input,
            roman_repair: entry.english.as_str(),
            bangla_output: entry.bangla.as_str(),
            frequency: entry.frequency,
            repair_kind: entry.kind.as_str(),
            repair_cost: entry.edit_cost,
        })
        .collect::<Vec<_>>();

    let options = FstSuggestOptions {
        max_distance: FST_MAX_LEVENSHTEIN_DISTANCE,
        max_candidates: AUTOCORRECT_POOL_LIMIT,
        response_candidates: response_limit.clamp(1, AUTOCORRECT_RESPONSE_LIMIT),
        max_prefix_candidates: response_limit.clamp(1, AUTOCORRECT_RESPONSE_LIMIT),
        ..FstSuggestOptions::default()
    };
    let Ok(result) = assets.lexicon.suggest_with_repaired_baselines_and_loanwords(
        obadh_output,
        &repaired_baselines,
        &loanword_matches,
        options,
    ) else {
        return Vec::new();
    };

    result
        .candidates
        .into_iter()
        .map(|candidate| candidate.text)
        .take(response_limit.clamp(1, AUTOCORRECT_RESPONSE_LIMIT))
        .collect()
}

#[no_mangle]
pub extern "C" fn obadh_autosuggest_suggestions_utf8(
    context_ptr: *const u8,
    context_len: usize,
    limit: usize,
    output_ptr: *mut u8,
    output_capacity: usize,
) -> usize {
    let Some(context) = utf8_input(context_ptr, context_len) else {
        return 0;
    };
    let Some(assets) = AUTOSUGGEST.get() else {
        return 0;
    };

    let options = AutosuggestOptions {
        max_candidates: limit.clamp(1, AUTOSUGGEST_RESPONSE_LIMIT),
    };
    let Ok(result) = assets.lm.suggest_for_text(context, options) else {
        return 0;
    };
    write_joined(
        result
            .candidates
            .into_iter()
            .map(|candidate| candidate.text.to_string())
            .take(limit.clamp(1, AUTOSUGGEST_RESPONSE_LIMIT)),
        output_ptr,
        output_capacity,
    )
}

#[no_mangle]
pub extern "C" fn obadh_autosuggest_session_suggestions_utf8(
    limit: usize,
    output_ptr: *mut u8,
    output_capacity: usize,
) -> usize {
    let response_limit = limit.clamp(1, AUTOSUGGEST_RESPONSE_LIMIT);
    let Some(session_lock) = autosuggest_session() else {
        return 0;
    };
    let Ok(mut session) = session_lock.lock() else {
        return 0;
    };

    session.set_options(AutosuggestOptions {
        max_candidates: response_limit,
    });
    if session.suggest().is_err() {
        return 0;
    }
    session.suggest_personal_text();

    let personal_text_suggestions = session.personal_text_suggestions().to_vec();
    let model_candidates = session
        .candidates()
        .iter()
        .map(|candidate| candidate.text.to_string())
        .collect::<Vec<_>>();

    let mut values = Vec::with_capacity(response_limit);
    push_personal_text_suggestions(&session, &personal_text_suggestions, true, response_limit, &mut values);

    for candidate in model_candidates {
        if values.len() >= response_limit {
            break;
        }
        if values.iter().all(|existing| existing != &candidate) {
            values.push(candidate);
        }
    }

    push_personal_text_suggestions(&session, &personal_text_suggestions, false, response_limit, &mut values);

    write_joined(values.into_iter(), output_ptr, output_capacity)
}

#[no_mangle]
pub extern "C" fn obadh_autosuggest_commit_token_utf8(
    token_ptr: *const u8,
    token_len: usize,
) -> bool {
    let Some(token) = utf8_input(token_ptr, token_len) else {
        return false;
    };
    let Some(session_lock) = autosuggest_session() else {
        return false;
    };
    let Ok(mut session) = session_lock.lock() else {
        return false;
    };
    session.commit_token(token).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn obadh_autosuggest_clear_session() {
    let Some(session_lock) = autosuggest_session() else {
        return;
    };
    if let Ok(mut session) = session_lock.lock() {
        session.clear_context();
    }
}

#[no_mangle]
pub extern "C" fn obadh_autosuggest_clear_personal() {
    let Some(session_lock) = autosuggest_session() else {
        return;
    };
    if let Ok(mut session) = session_lock.lock() {
        session.personal_mut().clear();
    }
}

#[no_mangle]
pub extern "C" fn obadh_autosuggest_personal_snapshot_len() -> usize {
    let Some(session_lock) = autosuggest_session() else {
        return 0;
    };
    let Ok(session) = session_lock.lock() else {
        return 0;
    };
    session.personal_snapshot_len()
}

#[no_mangle]
pub extern "C" fn obadh_autosuggest_export_personal_snapshot(
    output_ptr: *mut u8,
    output_capacity: usize,
) -> usize {
    let Some(session_lock) = autosuggest_session() else {
        return 0;
    };
    let Ok(session) = session_lock.lock() else {
        return 0;
    };
    let mut bytes = Vec::with_capacity(session.personal_snapshot_len());
    session.write_personal_snapshot_into(&mut bytes);
    write_bytes(&bytes, output_ptr, output_capacity)
}

#[no_mangle]
pub extern "C" fn obadh_autosuggest_import_personal_snapshot(
    input_ptr: *const u8,
    input_len: usize,
) -> bool {
    if input_len == 0 {
        return false;
    }
    if input_ptr.is_null() {
        return false;
    }
    let Some(session_lock) = autosuggest_session() else {
        return false;
    };
    let bytes = unsafe { slice::from_raw_parts(input_ptr, input_len) };
    let Ok(mut session) = session_lock.lock() else {
        return false;
    };
    session.import_personal_snapshot(bytes).is_ok()
}

fn configure_autosuggest_session() -> bool {
    if AUTOSUGGEST_SESSION.get().is_some() {
        return true;
    }
    let Some(assets) = AUTOSUGGEST.get() else {
        return false;
    };
    let session = AutosuggestSession::with_personal_config(
        &assets.lm,
        PersonalAutosuggestConfig::default(),
        AutosuggestOptions {
            max_candidates: AUTOSUGGEST_RESPONSE_LIMIT,
        },
    );
    AUTOSUGGEST_SESSION
        .set(Mutex::new(session))
        .is_ok()
        || AUTOSUGGEST_SESSION.get().is_some()
}

fn autosuggest_session() -> Option<&'static Mutex<AutosuggestSession<'static, memmap2::Mmap>>> {
    if AUTOSUGGEST_SESSION.get().is_none() && !configure_autosuggest_session() {
        return None;
    }
    AUTOSUGGEST_SESSION.get()
}

fn push_personal_text_suggestions(
    session: &AutosuggestSession<'static, memmap2::Mmap>,
    suggestions: &[obadh_engine::PersonalAutosuggestTextSuggestion],
    contextual: bool,
    limit: usize,
    values: &mut Vec<String>,
) {
    for suggestion in suggestions {
        if values.len() >= limit {
            break;
        }
        if (suggestion.context_len > 0) != contextual {
            continue;
        }
        let Some(text) = session.personal_text_suggestion_text(*suggestion) else {
            continue;
        };
        if values.iter().all(|existing| existing != text) {
            values.push(text.to_string());
        }
    }
}

fn write_joined(
    values: impl Iterator<Item = String>,
    output_ptr: *mut u8,
    output_capacity: usize,
) -> usize {
    let mut joined = String::new();
    for (index, value) in values.enumerate() {
        if index > 0 {
            joined.push('\n');
        }
        joined.push_str(&value);
    }
    write_bytes(joined.as_bytes(), output_ptr, output_capacity)
}

fn engine() -> &'static ObadhEngine {
    ENGINE.get_or_init(ObadhEngine::new)
}

fn utf8_input<'a>(input_ptr: *const u8, input_len: usize) -> Option<&'a str> {
    if input_len == 0 {
        return Some("");
    }
    if input_ptr.is_null() {
        return None;
    }
    let bytes = unsafe { slice::from_raw_parts(input_ptr, input_len) };
    std::str::from_utf8(bytes).ok()
}

fn mmap_fst_lexicon(path: impl AsRef<Path>) -> Result<FstLexicon<memmap2::Mmap>, String> {
    let file = File::open(path).map_err(|error| error.to_string())?;
    let mmap = unsafe { memmap2::MmapOptions::new().map(&file).map_err(|error| error.to_string())? };
    let map = fst::Map::new(mmap).map_err(|error| error.to_string())?;
    Ok(FstLexicon::from_map(map))
}

fn write_bytes(bytes: &[u8], output_ptr: *mut u8, output_capacity: usize) -> usize {
    if !output_ptr.is_null() && output_capacity >= bytes.len() {
        let output = unsafe { slice::from_raw_parts_mut(output_ptr, output_capacity) };
        output[..bytes.len()].copy_from_slice(bytes);
    }
    bytes.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transliteration_reports_required_len_then_writes_output() {
        let input = b"ami";
        let needed = obadh_transliterate_utf8(input.as_ptr(), input.len(), std::ptr::null_mut(), 0);
        assert!(needed > 0);

        let mut output = vec![0_u8; needed];
        let written =
            obadh_transliterate_utf8(input.as_ptr(), input.len(), output.as_mut_ptr(), output.len());

        assert_eq!(written, needed);
        assert_eq!(String::from_utf8(output).unwrap(), "আমি");
    }

    #[test]
    fn missing_models_return_empty_suggestions() {
        let input = b"ami";
        let needed = obadh_autocorrect_suggestions_utf8(
            input.as_ptr(),
            input.len(),
            3,
            std::ptr::null_mut(),
            0,
        );
        assert_eq!(needed, 0);
    }
}
