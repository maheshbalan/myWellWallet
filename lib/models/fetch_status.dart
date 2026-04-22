/// Model for tracking data fetch progress
class FetchStatus {
  final String resourceType;
  final String status; // 'pending', 'in_progress', 'completed', 'error'
  final int? count;
  final String? errorMessage;
  final double progress; // 0.0 to 1.0

  FetchStatus({
    required this.resourceType,
    required this.status,
    this.count,
    this.errorMessage,
    this.progress = 0.0,
  });

  FetchStatus copyWith({
    String? resourceType,
    String? status,
    int? count,
    String? errorMessage,
    double? progress,
  }) {
    return FetchStatus(
      resourceType: resourceType ?? this.resourceType,
      status: status ?? this.status,
      count: count ?? this.count,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
    );
  }
}

/// Summary of completed data fetch
class FetchSummary {
  final Map<String, int> resourceCounts;
  final int totalResources;
  final DateTime completedAt;
  final List<String> errors;
  final bool storedInDatabase;

  FetchSummary({
    required this.resourceCounts,
    required this.totalResources,
    required this.completedAt,
    this.errors = const [],
    this.storedInDatabase = true,
  });
}

/// Overall step status for fetch process
class FetchStepStatus {
  final String stepName;
  final String status; // 'pending', 'in_progress', 'completed', 'error'
  final String? message;
  final String? dataSnippet;

  FetchStepStatus({
    required this.stepName,
    required this.status,
    this.message,
    this.dataSnippet,
  });
}

