extends RefCounted
class_name HemingwayEnforcer

const MAX_SENTENCES := 3
const MAX_CHARS_PER_SENTENCE := 25

# Returns { truncated_text, original_text, was_truncated,
#           original_sentence_count, original_max_sentence_length }
static func truncate(text: Variant) -> Dictionary:
	if text == null or typeof(text) != TYPE_STRING:
		return {
			"truncated_text": "",
			"original_text": str(text) if text != null else "",
			"was_truncated": false,
			"original_sentence_count": 0,
			"original_max_sentence_length": 0
		}
	
	var original_text: String = text
	var sentences: PackedStringArray = _split_sentences(original_text)
	var original_sentence_count: int = sentences.size()
	var original_max_sentence_length: int = 0
	for s in sentences:
		var slen: int = s.length()
		if slen > original_max_sentence_length:
			original_max_sentence_length = slen
	
	var was_truncated: bool = false
	
	# Truncate to max sentences
	if sentences.size() > MAX_SENTENCES:
		sentences.resize(MAX_SENTENCES)
		sentences[sentences.size() - 1] = sentences[sentences.size() - 1].rstrip(".!?") + "…"
		was_truncated = true
	
	# Truncate each sentence to max chars
	var truncated_parts: PackedStringArray = []
	for i in range(sentences.size()):
		var sentence: String = _truncate_sentence(sentences[i])
		if sentence != sentences[i]:
			was_truncated = true
		truncated_parts.append(sentence)
	
	var truncated_text: String = ""
	for i in range(truncated_parts.size()):
		if i > 0:
			truncated_text += " "
		truncated_text += truncated_parts[i]
	
	return {
		"truncated_text": truncated_text,
		"original_text": original_text,
		"was_truncated": was_truncated,
		"original_sentence_count": original_sentence_count,
		"original_max_sentence_length": original_max_sentence_length
	}


static func _split_sentences(text: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var current: String = ""
	var i: int = 0
	while i < text.length():
		current += text[i]
		var ch: String = text[i]
		if ch in ".!?":
			# Check if this is the end of a sentence
			if i + 1 >= text.length() or text[i + 1] == ' ' or text[i + 1] == '\n' or text[i + 1] == '\t':
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


static func _truncate_sentence(sentence: String) -> String:
	if sentence.length() <= MAX_CHARS_PER_SENTENCE:
		return sentence
	
	# Strip trailing punctuation for truncation
	var stripped: String = sentence.rstrip(".!?")
	if stripped.length() <= MAX_CHARS_PER_SENTENCE:
		return stripped + "…"
	
	# Find last word boundary within limit
	var truncated: String = stripped.substr(0, MAX_CHARS_PER_SENTENCE)
	var last_space: int = truncated.rfind(" ")
	if last_space > 0:
		truncated = truncated.substr(0, last_space)
	
	return truncated.strip_edges() + "…"
