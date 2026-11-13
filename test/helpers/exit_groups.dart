import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';

class TestExitGroups extends Groups {
  TestExitGroups(this.names);
  final Iterable<String> names;
  @override
  List<Group> build() => [
    Group(
      name: 'Main',
      type: GroupType.Selector,
      all: [
        for (final name in names.toSet())
          Proxy(name: name, type: 'ss', cacheIdentity: 'identity:$name'),
      ],
    ),
  ];
}
