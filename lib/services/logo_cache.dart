import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Disk cache for channel logos. The default cache keeps only 200 files, so a list with thousands of
/// channels re-downloaded its logos again and again while scrolling (blank icons); this one keeps 30 000
/// for 60 days.
final CacheManager logoCacheManager = CacheManager(
  Config('lumoraLogos', stalePeriod: const Duration(days: 60), maxNrOfCacheObjects: 30000),
);
