// Prompt sanitization for user-provided text that is about to be
// interpolated into a Gemma chat-template prompt. WP1-06.
//
// Gemma prompts use <start_of_turn>...<end_of_turn> markers to delimit
// turns. A user query that contains one of these markers (accidentally
// or adversarially) can escape the user turn and hijack the model's
// instructions. We also want to cap length and collapse whitespace so an
// attacker can't pad the prompt into a truncation-forced state.

/// Default maximum length for a sanitized user query. Anything longer is
/// truncated. 500 chars is far larger than any realistic clinical
/// question but small enough that padding attacks can't bloat the prompt.
const int kPromptSanitizerDefaultMaxLength = 500;

/// Regex matching any Gemma turn-marker-like token. Matches variants such
/// as `<start_of_turn>`, `<end_of_turn>`, `<bos>`, `<eos>`, `<|im_start|>`,
/// `<|im_end|>`. Matching is case-insensitive; whitespace inside the
/// brackets is also accepted (e.g. `<start_of_turn >`).
final RegExp _controlMarkerPattern = RegExp(
  r'<\s*(?:\|)?\s*(?:start_of_turn|end_of_turn|bos|eos|im_start|im_end|pad|unk)\s*(?:\|)?\s*>',
  caseSensitive: false,
);

final RegExp _whitespaceRun = RegExp(r'\s+');

/// Strip Gemma control markers and collapse whitespace so [input] is safe
/// to interpolate into a prompt. Truncates to [maxLength] characters.
String sanitizeForPrompt(
  String input, {
  int maxLength = kPromptSanitizerDefaultMaxLength,
}) {
  // 1. Replace control markers with a neutral token so the model still
  //    sees *something* in place (prevents silent meaning loss) but no
  //    escaping occurs.
  var cleaned = input.replaceAll(_controlMarkerPattern, '[marker]');

  // 2. Collapse whitespace runs (including newlines) into single spaces.
  //    Protects against padding attacks that would otherwise force
  //    truncation somewhere unfortunate.
  cleaned = cleaned.replaceAll(_whitespaceRun, ' ').trim();

  // 3. Cap length.
  if (cleaned.length > maxLength) {
    cleaned = cleaned.substring(0, maxLength);
  }

  return cleaned;
}

/// Sanitize every `content` field in a conversation history list in place.
/// A prior model turn that contained unexpected markers can corrupt the
/// current prompt just as easily as user input can.
List<Map<String, String>> sanitizeHistory(
  List<Map<String, String>> history, {
  int maxLength = kPromptSanitizerDefaultMaxLength,
}) {
  return history
      .map((msg) => {
            ...msg,
            if (msg['content'] != null)
              'content': sanitizeForPrompt(msg['content']!, maxLength: maxLength),
          })
      .toList(growable: false);
}
