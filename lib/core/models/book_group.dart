/// BookGroup - 書籍分組模型
/// (原 Android data/entities/BookGroup.kt)
class BookGroup {
  final int groupId;
  String groupName;
  String? coverPath;
  int order;
  bool enableRefresh;
  bool show;
  int bookSort;

  int get id => groupId;
  String get name => groupName;
  set name(String v) => groupName = v;

  static const int idRoot = -100;
  static const int idAll = -1;
  static const int idLocal = -2;
  static const int idAudio = -3;
  static const int idNetNone = -4;
  static const int idLocalNone = -5;
  static const int idError = -11;

  BookGroup({
    this.groupId = 1,
    this.groupName = '',
    this.coverPath,
    this.order = 0,
    this.enableRefresh = true,
    this.show = true,
    this.bookSort = -1,
  });

  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'groupName': groupName,
      'coverPath': coverPath,
      'order': order,
      'enableRefresh': enableRefresh,
      'show': show,
      'bookSort': bookSort,
    };
  }

  factory BookGroup.fromJson(Map<String, dynamic> json) {
    return BookGroup(
      groupId: json['groupId'] ?? 1,
      groupName: json['groupName'] ?? '',
      coverPath: json['coverPath'],
      order: json['order'] ?? 0,
      enableRefresh:
          json['enableRefresh'] == 1 || json['enableRefresh'] == true,
      show: json['show'] == 1 || json['show'] == true,
      bookSort: json['bookSort'] ?? -1,
    );
  }
}
