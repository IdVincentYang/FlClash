import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';

class TestProfiles extends Profiles {
  final List<Profile> initial;

  TestProfiles([this.initial = const []]);

  @override
  List<Profile> build() => initial;

  @override
  Future<void> put(Profile profile, {Iterable<int> renameIn = const []}) async {
    final next = List<Profile>.from(state);
    final index = next.indexWhere((item) => item.id == profile.id);
    if (index == -1) {
      next.add(profile);
    } else {
      next[index] = profile;
    }
    state = next;
  }

  @override
  Future<void> del(int id) async {
    state = state.where((profile) => profile.id != id).toList();
  }

  @override
  Future<void> reorder(List<Profile> profiles) async {
    state = List.of(profiles);
  }

  @override
  Future<void> updateProfile(
    int profileId,
    Profile Function(Profile profile) builder,
  ) async {
    final index = state.indexWhere((item) => item.id == profileId);
    if (index == -1) return;
    final next = List<Profile>.from(state);
    next[index] = builder(state[index]);
    state = next;
  }

  void replace(List<Profile> profiles) {
    state = profiles;
  }
}
