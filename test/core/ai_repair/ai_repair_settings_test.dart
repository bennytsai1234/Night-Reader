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

  test('the model for finding books is kept in the same record as the '
      'service, falls back to the repair model, and survives a save that does '
      'not mention it', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AiRepairSettings(await SharedPreferences.getInstance());
    const service = (
      baseUrl: 'https://ai.example/v1',
      apiKey: 'k',
      model: 'repair',
      effort: 'low',
    );
    await settings.save(service);
    expect((await settings.findService())?.model, 'repair', reason: '留空同修書源');

    await settings.save(service, findModel: 'finder');
    final find = (await settings.findService())!;
    expect(find.model, 'finder');
    expect(
      (find.baseUrl, find.apiKey, find.effort),
      ('https://ai.example/v1', 'k', 'low'),
    );
    expect((await settings.service())?.model, 'repair');

    await settings.save((
      baseUrl: service.baseUrl,
      apiKey: 'k2',
      model: 'repair',
      effort: 'low',
    ));
    expect(await settings.findModel(), 'finder', reason: '沒給就留著');
    expect((await SharedPreferences.getInstance()).getKeys(), {
      AiRepairSettings.serviceKey,
    }, reason: '和網址、金鑰同一筆，一起同步');
  });

  test('how many sites the AI repairs at once is kept, three by default, and '
      'synced', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AiRepairSettings(await SharedPreferences.getInstance());
    expect(await settings.concurrency(), aiDefaultConcurrency);
    await settings.saveConcurrency(6);
    expect(await settings.concurrency(), 6);
    expect(
      AiRepairSettings.syncedKeys,
      contains(AiRepairSettings.concurrencyKey),
    );

    SharedPreferences.setMockInitialValues({
      AiRepairSettings.concurrencyKey: 5,
    });
    final odd = AiRepairSettings(await SharedPreferences.getInstance());
    expect(await odd.concurrency(), aiDefaultConcurrency);
  });

  test('a preset is recognised by its address, and only the tested model is '
      'marked', () {
    final go = aiServicePresets.first;
    expect(aiServicePresetOf('${go.baseUrl}/')?.name, go.name);
    expect(aiServicePresetOf('https://my.example/v1'), isNull);
    expect(aiModelTested(go.baseUrl, go.model!), isTrue);
    expect(aiModelTested(go.baseUrl, 'kimi-k3'), isFalse);
    expect(aiModelTested('https://my.example/v1', go.model!), isFalse);
  });
}
