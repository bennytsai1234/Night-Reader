import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/theme_customization.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
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
      extendBodyBehindAppBar: true,
      appBar: GlassNavHeader(
        title: '外觀與主題',
        bottomHeight: _areaBarHeight,
        bottom: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppGrouped.margin),
          child: Center(
            child: GlassSegmented<ThemeArea>(
              segments: const [
                GlassSegment(ThemeArea.app, '全域'),
                GlassSegment(ThemeArea.reader, '閱讀'),
                GlassSegment(ThemeArea.menu, '選單'),
              ],
              selected: _area,
              onChanged: (value) => setState(() => _area = value),
            ),
          ),
        ),
      ),
      body: GroupedListView(
        children: [
          if (_area == ThemeArea.app)
            GroupedSection(
              topGap: AppSpacing.lg,
              header: 'App 顯示模式',
              footer: '跟隨系統時，手機為淺色就套用淺色方案，手機為深色就套用深色方案。',
              children: [
                for (final (mode, label) in const [
                  (ThemeMode.system, '跟隨系統'),
                  (ThemeMode.light, '淺色方案'),
                  (ThemeMode.dark, '深色方案'),
                ])
                  GroupedCheckRow(
                    title: label,
                    selected: appSettings.themeMode == mode,
                    onTap: () => appSettings.setThemeMode(mode),
                  ),
              ],
            )
          else
            GroupedSection(
              topGap: AppSpacing.lg,
              header: _area == ThemeArea.reader ? '閱讀方案切換' : '閱讀選單方案切換',
              footer: '淺色與深色各使用自己的配色方案；跟隨系統只負責依手機目前模式選擇要套用哪一套。',
              children: [
                for (final (mode, label) in const [
                  (AreaThemeMode.followSystem, '跟隨系統'),
                  (AreaThemeMode.light, '淺色方案'),
                  (AreaThemeMode.dark, '深色方案'),
                ])
                  GroupedCheckRow(
                    title: label,
                    selected:
                        (_area == ThemeArea.reader
                            ? settings.readerMode
                            : settings.menuMode) ==
                        mode,
                    onTap: () => settings.setAreaMode(_area, mode),
                  ),
              ],
            ),
          GroupedSection(
            header: '編輯方案',
            footer: '關閉自訂配色時使用內建預設；自訂值仍會保留。',
            children: [
              GroupedContent(
                child: GlassSegmented<bool>(
                  segments: const [
                    GlassSegment(
                      false,
                      '淺色方案',
                      icon: Icons.light_mode_outlined,
                    ),
                    GlassSegment(
                      true,
                      '深色方案',
                      icon: Icons.dark_mode_outlined,
                    ),
                  ],
                  selected: _dark,
                  onChanged: (value) => setState(() => _dark = value),
                ),
              ),
              GroupedContent(
                padding: const EdgeInsets.fromLTRB(
                  AppGrouped.rowPadding,
                  0,
                  AppGrouped.rowPadding,
                  AppGrouped.rowPadding,
                ),
                child: _Preview(area: _area, dark: _dark, settings: settings),
              ),
              GroupedSwitchRow(
                title: '使用自訂配色',
                value: _useCustom(settings),
                onChanged: (value) => settings.setUseCustom(_area, _dark, value),
              ),
            ],
          ),
          GroupedSection(
            header: _dark ? '深色方案配色' : '淺色方案配色',
            children:
                _area == ThemeArea.app
                    ? _buildAppEditors(settings)
                    : _buildAreaEditors(settings),
          ),
          GroupedSection(
            children: [
              GroupedRow(
                title: _dark ? '恢復深色方案預設值' : '恢復淺色方案預設值',
                accent: true,
                showChevron: false,
                onTap: () => settings.reset(_area, _dark),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 頁首下方分段控制列的高度（控制本身 36，上下留白）。
  static const double _areaBarHeight = 36 + AppSpacing.md;

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
          borderRadius: AppRadius.cardLg,
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
                dark ? '深色方案預覽' : '淺色方案預覽',
                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: AppRadius.cardMd,
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_stories, color: c.primary),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('主題即時預覽', style: TextStyle(color: c.textPrimary)),
                          Text(
                            '主要畫面、卡片與導覽',
                            style: AppTextStyles.labelSm.copyWith(color: c.textSecondary),
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
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: AppRadius.cardLg,
        border: Border.all(color: c.border),
      ),
      child: area == ThemeArea.reader
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dark ? '深色閱讀方案' : '淺色閱讀方案',
                  style: TextStyle(color: c.accent, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '窗外的風慢慢吹過，紙頁在燈下留下柔和的影子。',
                  style: TextStyle(color: c.text, height: 1.6),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '方案名稱只代表切換槽位，實際顏色由你自訂。',
                  style: AppTextStyles.labelSm.copyWith(color: c.secondaryText),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Icon(Icons.list_alt, color: c.text),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: c.highlight,
                    borderRadius: AppRadius.cardMd,
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
    return GroupedRow(
      title: label,
      value: '#${hex.substring(2)}',
      trailing: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: AppChrome.of(context).separator),
        ),
      ),
      onTap: () async {
        final value = await showDialog<Color>(
          context: context,
          barrierColor: AppChrome.of(context).barrier,
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
    return AppAlert<bool>(
      title: '調整顏色',
      onAction: (apply) => apply ? _submit() : Navigator.pop(context),
      actions: const [
        AppAlertAction(label: '取消', value: false),
        AppAlertAction(label: '套用', value: true, isDefault: true),
      ],
      content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: color,
                borderRadius: AppRadius.cardMd,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
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
            const SizedBox(height: AppSpacing.md),
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
        SizedBox(width: 52, child: Text(label, style: AppTextStyles.uiSm)),
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
