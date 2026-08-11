import 'package:flutter/material.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/theme_customization.dart';
import 'package:provider/provider.dart';

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  ThemeArea _area = ThemeArea.app;
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ThemeSettingsProvider>();
    final appSettings = context.watch<SettingsProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('外觀與主題')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SegmentedButton<ThemeArea>(
            segments: const [
              ButtonSegment(value: ThemeArea.app, label: Text('全域')),
              ButtonSegment(value: ThemeArea.reader, label: Text('閱讀')),
              ButtonSegment(value: ThemeArea.menu, label: Text('選單')),
            ],
            selected: {_area},
            onSelectionChanged: (value) => setState(() => _area = value.first),
          ),
          const SizedBox(height: 12),
          if (_area == ThemeArea.app) ...[
            const Text('App 顯示模式', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('跟隨系統')),
                ButtonSegment(value: ThemeMode.light, label: Text('淺色')),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
              ],
              selected: {appSettings.themeMode},
              onSelectionChanged: (value) => appSettings.setThemeMode(value.first),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Text(
              _area == ThemeArea.reader ? '閱讀顯示模式' : '閱讀選單顯示模式',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SegmentedButton<AreaThemeMode>(
              segments: const [
                ButtonSegment(value: AreaThemeMode.followApp, label: Text('跟隨 App')),
                ButtonSegment(value: AreaThemeMode.light, label: Text('淺色')),
                ButtonSegment(value: AreaThemeMode.dark, label: Text('深色')),
              ],
              selected: {
                _area == ThemeArea.reader ? settings.readerMode : settings.menuMode,
              },
              onSelectionChanged: (value) =>
                  settings.setAreaMode(_area, value.first),
            ),
            const SizedBox(height: 16),
          ],
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('淺色設定'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('深色設定'),
              ),
            ],
            selected: {_dark},
            onSelectionChanged: (value) => setState(() => _dark = value.first),
          ),
          const SizedBox(height: 18),
          _Preview(area: _area, dark: _dark, settings: settings),
          const SizedBox(height: 18),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('使用自訂配色'),
            subtitle: const Text('關閉時使用內建預設；自訂值仍會保留'),
            value: _useCustom(settings),
            onChanged: (value) => settings.setUseCustom(_area, _dark, value),
          ),
          const Divider(height: 28),
          if (_area == ThemeArea.app)
            ..._buildAppEditors(settings)
          else
            ..._buildAreaEditors(settings),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => settings.reset(_area, _dark),
            icon: const Icon(Icons.restart_alt),
            label: const Text('恢復這組自訂色為預設值'),
          ),
        ],
      ),
    );
  }

  bool _useCustom(ThemeSettingsProvider settings) {
    return switch ((_area, _dark)) {
      (ThemeArea.app, false) => settings.appLightCustom,
      (ThemeArea.app, true) => settings.appDarkCustom,
      (ThemeArea.reader, false) => settings.readerLightCustom,
      (ThemeArea.reader, true) => settings.readerDarkCustom,
      (ThemeArea.menu, false) => settings.menuLightCustom,
      (ThemeArea.menu, true) => settings.menuDarkCustom,
    };
  }

  List<Widget> _buildAppEditors(ThemeSettingsProvider settings) {
    final colors = _dark ? settings.appDark : settings.appLight;
    final entries = <(String, Color, AppUiThemeColors Function(Color))>[
      ('主色', colors.primary, (v) => colors.copyWith(primary: v)),
      ('強調色', colors.secondary, (v) => colors.copyWith(secondary: v)),
      ('頁面背景', colors.background, (v) => colors.copyWith(background: v)),
      ('卡片與面板', colors.surface, (v) => colors.copyWith(surface: v)),
      ('頂部列', colors.appBar, (v) => colors.copyWith(appBar: v)),
      ('底部導覽', colors.navigation, (v) => colors.copyWith(navigation: v)),
      ('主要文字', colors.textPrimary, (v) => colors.copyWith(textPrimary: v)),
      ('次要文字', colors.textSecondary, (v) => colors.copyWith(textSecondary: v)),
      ('邊框與分隔線', colors.border, (v) => colors.copyWith(border: v)),
    ];
    return entries
        .map(
          (entry) => _ColorTile(
            label: entry.$1,
            color: entry.$2,
            onChanged: (value) => settings.updateApp(_dark, entry.$3(value)),
          ),
        )
        .toList();
  }

  List<Widget> _buildAreaEditors(ThemeSettingsProvider settings) {
    final colors = _area == ThemeArea.reader
        ? (_dark ? settings.readerDark : settings.readerLight)
        : (_dark ? settings.menuDark : settings.menuLight);
    final entries = <(String, Color, ReaderAreaThemeColors Function(Color))>[
      ('背景', colors.background, (v) => colors.copyWith(background: v)),
      ('主要文字', colors.text, (v) => colors.copyWith(text: v)),
      ('次要文字', colors.secondaryText, (v) => colors.copyWith(secondaryText: v)),
      ('主色／選中狀態', colors.accent, (v) => colors.copyWith(accent: v)),
      ('高亮／選中背景', colors.highlight, (v) => colors.copyWith(highlight: v)),
      ('邊框與分隔線', colors.border, (v) => colors.copyWith(border: v)),
    ];
    return entries
        .map(
          (entry) => _ColorTile(
            label: entry.$1,
            color: entry.$2,
            onChanged: (value) => settings.updateArea(_area, _dark, entry.$3(value)),
          ),
        )
        .toList();
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.area, required this.dark, required this.settings});

  final ThemeArea area;
  final bool dark;
  final ThemeSettingsProvider settings;

  @override
  Widget build(BuildContext context) {
    if (area == ThemeArea.app) {
      final c = dark ? settings.appDark : settings.appLight;
      return Container(
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              height: 42,
              color: c.appBar,
              alignment: Alignment.center,
              child: Text(
                '夜讀',
                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_stories, color: c.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('主題即時預覽', style: TextStyle(color: c.textPrimary)),
                          Text(
                            '主要畫面、卡片與導覽',
                            style: TextStyle(color: c.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              height: 38,
              color: c.navigation,
              alignment: Alignment.center,
              child: Icon(Icons.home_rounded, color: c.primary),
            ),
          ],
        ),
      );
    }

    final c = area == ThemeArea.reader
        ? (dark ? settings.readerDark : settings.readerLight)
        : (dark ? settings.menuDark : settings.menuLight);
    return Container(
      height: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: area == ThemeArea.reader
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '第十二章　夜色',
                  style: TextStyle(color: c.accent, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  '窗外的風慢慢吹過，紙頁在燈下留下柔和的影子。',
                  style: TextStyle(color: c.text, height: 1.6),
                ),
                const SizedBox(height: 6),
                Text(
                  '閱讀正文與資訊顏色彼此獨立。',
                  style: TextStyle(color: c.secondaryText, fontSize: 12),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Icon(Icons.list_alt, color: c.text),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.highlight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.record_voice_over, color: c.accent),
                ),
                Icon(Icons.format_size, color: c.text),
                Icon(Icons.settings, color: c.secondaryText),
              ],
            ),
    );
  }
}

class _ColorTile extends StatelessWidget {
  const _ColorTile({required this.label, required this.color, required this.onChanged});

  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final hex = color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text('#${hex.substring(2)}'),
      trailing: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      onTap: () async {
        final value = await showDialog<Color>(
          context: context,
          builder: (_) => _ColorEditorDialog(initial: color),
        );
        if (value != null) onChanged(value);
      },
    );
  }
}

class _ColorEditorDialog extends StatefulWidget {
  const _ColorEditorDialog({required this.initial});

  final Color initial;

  @override
  State<_ColorEditorDialog> createState() => _ColorEditorDialogState();
}

class _ColorEditorDialogState extends State<_ColorEditorDialog> {
  late HSLColor _hsl;
  late final TextEditingController _hex;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    _hsl = HSLColor.fromColor(widget.initial);
    _hex = TextEditingController(text: _hexText(_hsl.toColor()));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  String _hexText(Color color) =>
      color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

  void _syncHex() {
    _hex.text = _hexText(_hsl.toColor());
    _hexError = null;
  }

  Color? _parseHex() {
    final value = _hex.text.trim().replaceFirst('#', '');
    if (value.length != 6) return null;
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return null;
    return Color(0xFF000000 | parsed);
  }

  void _applyHex() {
    final color = _parseHex();
    setState(() {
      if (color == null) {
        _hexError = '請輸入 6 位 HEX 顏色';
        return;
      }
      _hsl = HSLColor.fromColor(color);
      _syncHex();
    });
  }

  void _submit() {
    final color = _parseHex();
    if (color == null) {
      setState(() => _hexError = '請輸入 6 位 HEX 顏色');
      return;
    }
    Navigator.pop(context, color);
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsl.toColor();
    return AlertDialog(
      title: const Text('調整顏色'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hex,
              decoration: InputDecoration(
                prefixText: '#',
                labelText: 'HEX',
                errorText: _hexError,
              ),
              onSubmitted: (_) => _applyHex(),
              onChanged: (_) {
                if (_hexError != null) setState(() => _hexError = null);
              },
            ),
            const SizedBox(height: 10),
            _slider('色相', _hsl.hue, 0, 360, (v) => _hsl = _hsl.withHue(v)),
            _slider(
              '飽和度',
              _hsl.saturation,
              0,
              1,
              (v) => _hsl = _hsl.withSaturation(v),
            ),
            _slider(
              '明度',
              _hsl.lightness,
              0,
              1,
              (v) => _hsl = _hsl.withLightness(v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('套用')),
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> update,
  ) {
    return Row(
      children: [
        SizedBox(width: 58, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            onChanged: (v) => setState(() {
              update(v);
              _syncHex();
            }),
          ),
        ),
      ],
    );
  }
}
