/// FlexChildStyle - Legado flex child layout style.
///
/// Mirrors Legado's `FlexChildStyle.kt` so imported discover categories can
/// keep their intended wrapping and width distribution.
class FlexChildStyle {
  final double layoutFlexGrow;
  final double layoutFlexShrink;
  final String layoutAlignSelf;
  final double layoutFlexBasisPercent;
  final bool layoutWrapBefore;

  const FlexChildStyle({
    this.layoutFlexGrow = 0,
    this.layoutFlexShrink = 1,
    this.layoutAlignSelf = 'auto',
    this.layoutFlexBasisPercent = -1,
    this.layoutWrapBefore = false,
  });

  static const FlexChildStyle defaultStyle = FlexChildStyle();

  factory FlexChildStyle.fromJson(Map<String, dynamic> json) {
    return FlexChildStyle(
      layoutFlexGrow: _readDouble(
        json,
        legadoKey: 'layout_flexGrow',
        dartKey: 'layoutFlexGrow',
        fallback: defaultStyle.layoutFlexGrow,
      ),
      layoutFlexShrink: _readDouble(
        json,
        legadoKey: 'layout_flexShrink',
        dartKey: 'layoutFlexShrink',
        fallback: defaultStyle.layoutFlexShrink,
      ),
      layoutAlignSelf:
          _readString(
            json,
            legadoKey: 'layout_alignSelf',
            dartKey: 'layoutAlignSelf',
            fallback: defaultStyle.layoutAlignSelf,
          ) ??
          defaultStyle.layoutAlignSelf,
      layoutFlexBasisPercent: _readDouble(
        json,
        legadoKey: 'layout_flexBasisPercent',
        dartKey: 'layoutFlexBasisPercent',
        fallback: defaultStyle.layoutFlexBasisPercent,
      ),
      layoutWrapBefore: _readBool(
        json,
        legadoKey: 'layout_wrapBefore',
        dartKey: 'layoutWrapBefore',
        fallback: defaultStyle.layoutWrapBefore,
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'layout_flexGrow': layoutFlexGrow,
    'layout_flexShrink': layoutFlexShrink,
    'layout_alignSelf': layoutAlignSelf,
    'layout_flexBasisPercent': layoutFlexBasisPercent,
    'layout_wrapBefore': layoutWrapBefore,
  };

  bool get hasCustomValue => this != defaultStyle;

  static double _readDouble(
    Map<String, dynamic> json, {
    required String legadoKey,
    required String dartKey,
    required double fallback,
  }) {
    final value = json[legadoKey] ?? json[dartKey];
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  static String? _readString(
    Map<String, dynamic> json, {
    required String legadoKey,
    required String dartKey,
    required String fallback,
  }) {
    final value = json[legadoKey] ?? json[dartKey];
    if (value == null) {
      return fallback;
    }
    return value.toString();
  }

  static bool _readBool(
    Map<String, dynamic> json, {
    required String legadoKey,
    required String dartKey,
    required bool fallback,
  }) {
    final value = json[legadoKey] ?? json[dartKey];
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlexChildStyle &&
          runtimeType == other.runtimeType &&
          layoutFlexGrow == other.layoutFlexGrow &&
          layoutFlexShrink == other.layoutFlexShrink &&
          layoutAlignSelf == other.layoutAlignSelf &&
          layoutFlexBasisPercent == other.layoutFlexBasisPercent &&
          layoutWrapBefore == other.layoutWrapBefore;

  @override
  int get hashCode => Object.hash(
    layoutFlexGrow,
    layoutFlexShrink,
    layoutAlignSelf,
    layoutFlexBasisPercent,
    layoutWrapBefore,
  );
}

/// ExploreKind - 探索分類模型
/// (對標 Android data/entities/rule/ExploreKind.kt)
class ExploreKind {
  final String title;
  final String? url;
  final FlexChildStyle? style;

  const ExploreKind({required this.title, this.url, this.style});

  FlexChildStyle get effectiveStyle => style ?? FlexChildStyle.defaultStyle;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'url': url,
    if (style != null) 'style': style!.toJson(),
  };

  factory ExploreKind.fromJson(Map<String, dynamic> json) {
    return ExploreKind(
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString(),
      style: _parseStyle(json['style']),
    );
  }

  static FlexChildStyle? _parseStyle(dynamic rawStyle) {
    if (rawStyle is Map) {
      return FlexChildStyle.fromJson(Map<String, dynamic>.from(rawStyle));
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExploreKind &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          url == other.url &&
          style == other.style;

  @override
  int get hashCode => Object.hash(title, url, style);
}
