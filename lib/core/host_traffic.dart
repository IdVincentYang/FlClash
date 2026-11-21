class HostTrafficSnapshot {
  const HostTrafficSnapshot(this.runtimeEpoch, this.rows);

  factory HostTrafficSnapshot.fromJson(Map<String, Object?> data) {
    final epoch = data['runtimeEpoch'];
    final rows = data['rows'];
    if (epoch is! String || epoch.isEmpty || rows is! List) {
      throw const FormatException('Host traffic snapshot is incomplete');
    }
    return HostTrafficSnapshot(
      epoch,
      List.unmodifiable(
        rows.map((item) {
          if (item case {
            'key': final String key,
            'upload': final int upload,
            'download': final int download,
          } when upload >= 0 && download >= 0) {
            return HostTrafficRow(key, upload, download);
          }
          throw const FormatException('Host traffic row is incomplete');
        }),
      ),
    );
  }

  final String runtimeEpoch;
  final List<HostTrafficRow> rows;
}

class HostTrafficRow {
  const HostTrafficRow(this.key, this.upload, this.download);

  final String key;
  final int upload;
  final int download;

  int get total => upload + download;
  bool get other => key == 'other:';
}
