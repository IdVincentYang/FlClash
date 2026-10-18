import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/providers/config_state.dart';

class TestConfigState extends ConfigState {
  TestConfigState([this.fact = const ConfigFact()]);
  final ConfigFact fact;

  @override
  ConfigViewState build() => ConfigViewState(fact: fact);
}
