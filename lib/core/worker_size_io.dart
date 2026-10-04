import 'dart:io';

/// One fewer than the processor count, minimum one. More isolates than cores
/// makes a batch slower, not faster.
int defaultWorkerCount() {
  final n = Platform.numberOfProcessors - 1;
  return n < 1 ? 1 : n;
}
