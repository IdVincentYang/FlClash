import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PreferenceWrite { pass, fail, failAfterWrite, throwError, throwAfterWrite }

class FailingPreferences extends Mock implements SharedPreferences {
  FailingPreferences(this.actual, this.outcomes, {this.beforeWrite});

  final SharedPreferences actual;
  final List<PreferenceWrite> outcomes;
  final Future<void> Function(int attempt)? beforeWrite;
  int writes = 0;

  @override
  String? getString(String key) => actual.getString(key);

  @override
  Future<bool> setString(String key, String value) async {
    final attempt = writes++;
    await beforeWrite?.call(attempt);
    final outcome = attempt < outcomes.length
        ? outcomes[attempt]
        : PreferenceWrite.pass;
    if (outcome == PreferenceWrite.fail) return false;
    if (outcome == PreferenceWrite.throwError) {
      throw StateError('synthetic-preference-secret');
    }
    final result = await actual.setString(key, value);
    if (outcome == PreferenceWrite.failAfterWrite) return false;
    if (outcome == PreferenceWrite.throwAfterWrite) {
      throw StateError('synthetic-preference-secret');
    }
    return result;
  }
}
