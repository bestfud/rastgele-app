import 'package:flutter/foundation.dart';

const bool kVerboseDebugLogs = false;
const Duration kSlowPerfLogThreshold = Duration(milliseconds: 3000);

final Set<String> _debugLogKeys = <String>{};

void verboseDebugLog(String message) {
  if (!kDebugMode || !kVerboseDebugLogs) {
    return;
  }

  debugPrint(message);
}

void perfLog(String message) {
  if (!kDebugMode || !kVerboseDebugLogs) {
    return;
  }

  debugPrint(message);
}

void perfLogOnce(String key, String message) {
  if (_debugLogKeys.add(key)) {
    perfLog(message);
  }
}

Future<T> perfRunTimed<T>(String label, Future<T> Function() action) async {
  if (!kDebugMode) {
    return action();
  }

  final stopwatch = Stopwatch()..start();
  try {
    return await action();
  } finally {
    stopwatch.stop();
    if (kVerboseDebugLogs ||
        stopwatch.elapsedMilliseconds >= kSlowPerfLogThreshold.inMilliseconds) {
      debugPrint('[perf] $label ${stopwatch.elapsedMilliseconds}ms');
    }
  }
}

void perfLogFrame(String label, Stopwatch stopwatch) {
  if (!kDebugMode || !kVerboseDebugLogs) {
    return;
  }

  debugPrint(
      '[perf] $label frame scheduling at ${stopwatch.elapsedMilliseconds}ms');
}
