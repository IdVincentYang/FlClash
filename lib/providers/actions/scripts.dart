part of '../action.dart';

@Riverpod(keepAlive: true)
class ScriptsAction extends _$ScriptsAction {
  @protected
  Request get requestClient => request;

  @override
  void build() {}

  Future<void> putScript(Script script) async {
    await ref.read(scriptsProvider.notifier).put(script);
    _applyIfInUse(script.id);
  }

  Future<void> deleteScript(int id) => requestClient.mutate(() async {
    await ref.read(scriptsProvider.notifier).deletePersisted(id);
    await File(await appPath.getScriptPath(id.toString())).safeDelete();
  });

  Future<void> saveScript(Script script, String content) async {
    final staged = await RequestFile.stage(utf8.encode(content));
    try {
      final path = await script.path;
      await requestClient.mutate(() async {
        await requestClient.invalidate('script:${script.id}');
        final current =
            (await database.scriptsDao.query().get()).get(script.id) ?? script;
        await staged.replace(
          path,
          () => ref
              .read(scriptsProvider.notifier)
              .persist(
                current.copyWith(
                  label: script.label,
                  lastUpdateTime: DateTime.now(),
                ),
              ),
        );
      });
      _applyIfInUse(script.id);
    } finally {
      await staged.close();
    }
  }

  Future<void> updateScript(Script script, {bool sourceEdit = false}) async {
    final updatingKeys = ref.read(updatingKeysProvider.notifier);
    final operation = updatingKeys.start(script.updatingKey);
    RequestSession? session;
    RequestFile? staged;
    try {
      if (sourceEdit) {
        await requestClient.mutate(() async {
          final current =
              (await database.scriptsDao.query().get()).get(script.id) ??
              script;
          await ref
              .read(scriptsProvider.notifier)
              .persist(
                current.copyWith(
                  label: script.label,
                  url: script.url,
                  requestMode: script.requestMode,
                  requestProxy: script.requestProxy,
                ),
              );
        });
      }
      final previous = (await database.scriptsDao.query().get()).get(script.id);
      script = previous ?? script;
      session = await requestClient.begin(
        key: 'script:${script.id}',
        url: script.url!,
        mode: script.requestMode,
        proxy: script.requestProxy,
        bootstrapIfUnconfigured:
            previous == null && script.requestMode == RequestMode.proxy,
        sourceIsCurrent: () async {
          final current = (await database.scriptsDao.query().get()).get(
            script.id,
          );
          return current == null
              ? previous == null
              : (current.url, current.requestMode, current.requestProxy) ==
                    (script.url, script.requestMode, script.requestProxy);
        },
      );
      final response = await session.run(
        () => requestClient.getTextResponseForUrl(script.url!),
      );
      staged = await RequestFile.stage(utf8.encode(response.data ?? ''));
      final incoming = staged;
      final path = await script.path;
      await session.commit(() async {
        final current =
            (await database.scriptsDao.query().get()).get(script.id) ?? script;
        await incoming.replace(
          path,
          () => ref
              .read(scriptsProvider.notifier)
              .persist(
                current.copyWith(lastUpdateTime: DateTime.now()),
                networkResult: true,
              ),
        );
        await requestClient.invalidate('script:${script.id}');
      });
      final completed = session;
      _applyIfInUse(
        script.id,
        isCurrent: () => completed.lifecycleCurrent(sourceInvalidated: true),
      );
    } finally {
      session?.close();
      await staged?.close();
      updatingKeys.stop(script.updatingKey, operation);
    }
  }

  void _applyIfInUse(int scriptId, {Future<bool> Function()? isCurrent}) {
    final profile = ref.read(currentProfileProvider);
    if (profile?.overwriteType != OverwriteType.script ||
        profile?.scriptId != scriptId) {
      return;
    }
    final profileId = profile!.id;
    ref
        .read(setupActionProvider.notifier)
        .applyProfileDebounce(
          silence: true,
          isCurrent: isCurrent == null
              ? null
              : () async {
                  final current = ref.read(currentProfileProvider);
                  return current?.id == profileId &&
                      current?.overwriteType == OverwriteType.script &&
                      current?.scriptId == scriptId &&
                      await isCurrent();
                },
        );
  }
}
