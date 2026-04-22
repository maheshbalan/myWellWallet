// Tag + helpers for the chat's typing indicator. Extracted so the
// add / remove / detect logic is pure and can be tested without pumping
// the full HomeScreen widget tree (WP1-04).

/// Key that tags a message map as the transient typing indicator. Using a
/// dedicated key (instead of a magic `'typing'` string in the `message`
/// field) lets removal target the indicator by identity, so interleaving
/// writes to the message list never delete the wrong entry.
const String kTypingIndicatorKey = 'isTypingIndicator';

/// Build a new typing-indicator message map. Each call returns a fresh
/// map with the current timestamp.
Map<String, dynamic> buildTypingIndicator() => {
      'isUser': false,
      'message': 'typing',
      kTypingIndicatorKey: true,
      'timestamp': DateTime.now(),
    };

/// Remove every typing-indicator entry from [messages] in place. Safe to
/// call even if no indicator is present.
void removeTypingIndicator(List<Map<String, dynamic>> messages) {
  messages.removeWhere((m) => m[kTypingIndicatorKey] == true);
}

/// Whether [message] is a typing indicator.
bool isTypingIndicator(Map<String, dynamic> message) =>
    message[kTypingIndicatorKey] == true;
