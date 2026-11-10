import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

final profileReviewStatusProvider = FutureProvider.autoDispose
    .family<SourceReviewStatus, Profile>((ref, profile) {
      ref.watch(configStateProvider);
      ref.watch(nativeRequestStateProvider);
      ref.watch(initProvider);
      ref.watch(appVisibleProvider);
      return ref
          .read(profilesActionProvider.notifier)
          .sourceReviewStatus(profile);
    }, retry: (retryCount, error) => null);
