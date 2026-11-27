/// Web fallback for native temporary-file cleanup.
library;

/// Browser-managed caches cannot be cleared through the native file API.
Future<int> clearTempCacheBytes({
  Future<dynamic> Function()? directoryProvider,
}) async => 0;
