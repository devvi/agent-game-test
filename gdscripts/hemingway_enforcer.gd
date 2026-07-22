extends RefCounted
class_name HemingwayEnforcer

const MAX_SENTENCES := 3
const MAX_CHARS_PER_SENTENCE := 25

# Domain-specific limits (Issue #51)
const DOMAIN_LIMITS := {
	"narration":    {"max_sentences": 3, "max_chars": 25},
	"dialogue":     {"max_sentences": 1, "max_chars": 25},
	"signage":      {"max_sentences": 1, "max_chars": 15},
	"choice_text":  {"max_sentences": 1, "max_chars": 30},
	"echo_variant": {"max_sentences": 1, "max_chars": 25},
}

# CJK constants (Issue #51)
const CJK_SENTENCE_ENDS := "。！？"
const COMBINED_SENTENCE_ENDS := ".!?" + CJK_SENTENCE_ENDS
const CJK_UNICODE_RANGE_START := 0x4E00
const CJK_UNICODE_RANGE_END := 0x9FFF

# Returns { truncated_text, original_text, was_truncated,
#           original_sentence_count, original_max_sentence_length,
#           domain_used, truncated_sentence_count }
static func truncate(text: Variant, domain: String = "narration") -> Dictionary:
	if text == null or typeof(text) != TYPE_STRING:
		return {
			"truncated_text": "",
			"original_text": str(text) if text != null else "",
			"was_truncated": false,
			"original_sentence_count": 0,
			"original_max_sentence_length": 0,
			"domain_used": domain,
			"truncated_sentence_count": 0
		}

	# Resolve domain limits with fallback
	var limits: Dictionary = DOMAIN_LIMITS.get(domain, DOMAIN_LIMITS["narration"])
	if not DOMAIN_LIMITS.has(domain):
		push_warning("[Hemingway] Unknown domain \"%s\", falling back to \"narration\"" % domain)
		domain = "narration"

	var max_sentences: int = limits["max_sentences"]
	var max_chars: int = limits["max_chars"]

	var original_text: String = text
	var sentences: PackedStringArray = _split_sentences(original_text)
	var original_sentence_count: int = sentences.size()
	var original_max_sentence_length: int = 0
	for s in sentences:
		var slen: int = s.length()
		if slen > original_max_sentence_length:
			original_max_sentence_length = slen

	var was_truncated: bool = false

	# Truncate to max sentences (sentence-limit applied FIRST per R7)
	if sentences.size() > max_sentences:
		sentences.resize(max_sentences)
		sentences[sentences.size() - 1] = sentences[sentences.size() - 1].rstrip(COMBINED_SENTENCE_ENDS) + "…"
		was_truncated = true

	# Truncate each sentence to max chars
	var truncated_parts: PackedStringArray = []
	for i in range(sentences.size()):
		var sentence: String = _truncate_sentence(sentences[i], max_chars)
		if sentence != sentences[i]:
			was_truncated = true
		truncated_parts.append(sentence)

	var truncated_text: String = ""
	for i in range(truncated_parts.size()):
		if i > 0:
			truncated_text += " "
		truncated_text += truncated_parts[i]

	var result := {
		"truncated_text": truncated_text,
		"original_text": original_text,
		"was_truncated": was_truncated,
		"original_sentence_count": original_sentence_count,
		"original_max_sentence_length": original_max_sentence_length,
		"domain_used": domain,
		"truncated_sentence_count": truncated_parts.size()
	}

	# Debug warning when truncated in editor
	if was_truncated and Engine.is_editor_hint():
		push_warning("[Hemingway] Truncated [%s]: \"%s\" → \"%s\" (%d→%d sentences, max %d→%d chars)" % [
			domain,
			original_text,
			truncated_text,
			original_sentence_count,
			truncated_parts.size(),
			original_max_sentence_length,
			max_chars
		])

	return result


static func _split_sentences(text: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var current: String = ""
	var i: int = 0
	while i < text.length():
		current += text[i]
		var ch: String = text[i]
		if ch in COMBINED_SENTENCE_ENDS:
			# CJK delimiters split unconditionally
			var is_cjk_end: bool = ch in CJK_SENTENCE_ENDS
			var is_end: bool = false
			if is_cjk_end:
				is_end = true
			else:
				# English delimiters require space, newline, tab, or EOS
				is_end = (i + 1 >= text.length() or text[i + 1] == ' ' or text[i + 1] == '\n' or text[i + 1] == '\t')
			if is_end:
				result.append(current.strip_edges())
				current = ""
				# Skip the space after punctuation
				if i + 1 < text.length() and text[i + 1] == ' ':
					i += 1
		i += 1

	# Don't lose trailing text that had no sentence-ending punctuation
	if current.strip_edges().length() > 0:
		result.append(current.strip_edges())

	return result


static func _truncate_sentence(sentence: String, max_chars: int = MAX_CHARS_PER_SENTENCE) -> String:
	if sentence.length() <= max_chars:
		return sentence

	# Strip trailing punctuation for truncation
	var stripped: String = sentence.rstrip(COMBINED_SENTENCE_ENDS)
	if stripped.length() <= max_chars:
		return stripped + "…"

	# CJK-aware: no word-boundary search (R8)
	if _has_cjk(sentence):
		return stripped.substr(0, max_chars) + "…"

	# Find last word boundary within limit
	var truncated: String = stripped.substr(0, max_chars)
	var last_space: int = truncated.rfind(" ")
	if last_space > 0:
		truncated = truncated.substr(0, last_space)

	return truncated.strip_edges() + "…"


static func _has_cjk(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= CJK_UNICODE_RANGE_START and code <= CJK_UNICODE_RANGE_END:
			return true
	return false
