"""Re-export from validate_hemingway for backward compatibility."""
from scripts.validate_hemingway import (
    RULES,
    SENTENCE_ENDS,
    CJK_ENDS,
    ALL_ENDS,
    split_sentences,
    has_cjk,
    truncate_sentence,
    validate_text,
    extract_texts,
    _apply_truncation,
)
