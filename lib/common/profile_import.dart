enum ProfileImportPhase { preparing, downloading, reviewing, saving }

class ProfileImportTask {
  ProfileImportTask({required this.onPhase});

  final void Function(ProfileImportPhase) onPhase;
  bool usingLoadedNodes = false;
  bool _cancelled = false;
  void Function()? _cancel;

  bool get isCurrent => !_cancelled;

  void attach(void Function() cancel) {
    _cancel = cancel;
    if (_cancelled) cancel();
  }

  void report(ProfileImportPhase phase) {
    if (isCurrent) onPhase(phase);
  }

  void cancel() {
    _cancelled = true;
    _cancel?.call();
    _cancel = null;
  }
}

class ProfileImportAlternative implements Exception {
  const ProfileImportAlternative({this.loadedNodes});
  final String? loadedNodes;
}
