import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the thinking effort is saved with the service and an unknown one '
      'reads as the service default', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AiRepairSettings(await SharedPreferences.getInstance());

    await settings.save((
      baseUrl: 'https://ai.example/v1',
      apiKey: 'k',
      model: 'm',
      effort: 'low',
    ));
    expect((await settings.service())?.effort, 'low');

    SharedPreferences.setMockInitialValues({
      AiRepairSettings.serviceKey:
          '{"baseUrl":"https://ai.example/v1","apiKey":"k","model":"m",'
          '"effort":"turbo"}',
    });
    final old = AiRepairSettings(await SharedPreferences.getInstance());
    expect((await old.service())?.effort, '');
  });
}
