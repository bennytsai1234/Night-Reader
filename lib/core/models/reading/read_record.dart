/// ReadRecord - 閱讀紀錄模型
/// (原 Android data/entities/ReadRecord.kt)
class ReadRecord {
  int id;
  String deviceId;
  String bookName;
  int readTime;
  int lastRead;

  ReadRecord({
    this.id = 0,
    this.deviceId = '',
    this.bookName = '',
    this.readTime = 0,
    this.lastRead = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'bookName': bookName,
      'readTime': readTime,
      'lastRead': lastRead,
    };
  }

  factory ReadRecord.fromJson(Map<String, dynamic> json) {
    return ReadRecord(
      deviceId: json['deviceId'] ?? '',
      bookName: json['bookName'] ?? '',
      readTime: json['readTime'] ?? 0,
      lastRead: json['lastRead'] ?? 0,
    );
  }
}
