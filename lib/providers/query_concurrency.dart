// Concurrency guard for the chat query pipeline.
// Extracted so the accept/reject logic is a pure function that can be
// unit-tested without building HomeScreen or QueryProvider (WP1-05).

/// Returns true if a new query should be accepted given the current state.
/// Rejects empty queries and rejects any attempt to start a new query while
/// another is already streaming (isStreaming) or still being processed by
/// the provider (isProcessing).
bool shouldAcceptNewQuery({
  required bool isStreaming,
  required bool isProcessing,
  required String query,
}) {
  if (query.trim().isEmpty) return false;
  if (isStreaming) return false;
  if (isProcessing) return false;
  return true;
}

/// Convenience for UI bindings: whether the input surface should be
/// disabled (greyed out send button, mic, follow-up chips, etc.).
bool isInputLocked({
  required bool isStreaming,
  required bool isProcessing,
}) =>
    isStreaming || isProcessing;
