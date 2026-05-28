import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class UmdBookData {
  final String title;
  final String author;
  final List<UmdChapterData> chapters;
  final Uint8List? coverBytes;

  const UmdBookData({
    required this.title,
    required this.author,
    required this.chapters,
    this.coverBytes,
  });
}

class UmdChapterData {
  final String title;
  final String content;

  const UmdChapterData({required this.title, required this.content});
}

class UmdParser {
  final File file;

  const UmdParser(this.file);

  Future<UmdBookData> parse() async {
    final bytes = await file.readAsBytes();
    final reader = _ByteReader(bytes);
    if (reader.readUint32() != 0xde9a9b89) {
      throw const FormatException('不是有效的 UMD 檔案');
    }

    var title = '';
    var author = '';
    Uint8List? coverBytes;
    final chapterTitles = <String>[];
    final chapterOffsets = <int>[];
    final contentBuffer = BytesBuilder(copy: false);

    var currentSection = -1;
    var additionalCheckNumber = -1;

    while (!reader.isEnd) {
      final marker = reader.readByte();
      if (marker == 0x23) {
        final segType = reader.readUint16();
        final segFlag = reader.readByte();
        final len = reader.readByte() - 5;
        currentSection =
            (segType == 241 || segType == 10) ? currentSection : segType;

        switch (segType) {
          case 2:
            title = _decodeUnicode(reader.readBytes(len));
            break;
          case 3:
            author = _decodeUnicode(reader.readBytes(len));
            break;
          case 11:
            reader.readUint32();
            break;
          case 129:
          case 130:
          case 131:
          case 132:
            if (segType == 130 && segFlag >= 0) {
              reader.readByte();
            }
            additionalCheckNumber = reader.readUint32();
            break;
          case 12:
            reader.readUint32();
            return _buildBookData(
              fallbackTitle:
                  file.uri.pathSegments.isEmpty
                      ? file.path
                      : file.uri.pathSegments.last,
              title: title,
              author: author,
              coverBytes: coverBytes,
              chapterTitles: chapterTitles,
              chapterOffsets: chapterOffsets,
              contentBytes: contentBuffer.toBytes(),
            );
          default:
            if (len > 0) {
              reader.skip(len);
            }
            break;
        }
      } else if (marker == 0x24) {
        final blockCheck = reader.readUint32();
        final length = reader.readUint32() - 9;
        switch (currentSection) {
          case 130:
            if (length > 0) {
              coverBytes = Uint8List.fromList(reader.readBytes(length));
            }
            break;
          case 131:
            final count = length ~/ 4;
            for (var i = 0; i < count; i++) {
              chapterOffsets.add(reader.readUint32());
            }
            break;
          case 132:
            if (blockCheck == additionalCheckNumber) {
              var consumed = 0;
              while (consumed < length && !reader.isEnd) {
                final titleLen = reader.readByte();
                consumed += 1;
                if (titleLen <= 0) continue;
                final raw = reader.readBytes(titleLen);
                consumed += raw.length;
                chapterTitles.add(_decodeUnicode(raw));
              }
              final remaining = length - consumed;
              if (remaining > 0) {
                reader.skip(remaining);
              }
            } else {
              final raw = reader.readBytes(length);
              contentBuffer.add(_inflate(raw));
            }
            break;
          default:
            if (length > 0) {
              reader.skip(length);
            }
            break;
        }
      } else {
        break;
      }
    }

    return _buildBookData(
      fallbackTitle:
          file.uri.pathSegments.isEmpty
              ? file.path
              : file.uri.pathSegments.last,
      title: title,
      author: author,
      coverBytes: coverBytes,
      chapterTitles: chapterTitles,
      chapterOffsets: chapterOffsets,
      contentBytes: contentBuffer.toBytes(),
    );
  }

  UmdBookData _buildBookData({
    required String fallbackTitle,
    required String title,
    required String author,
    required Uint8List? coverBytes,
    required List<String> chapterTitles,
    required List<int> chapterOffsets,
    required Uint8List contentBytes,
  }) {
    final normalizedTitle = title.trim().isEmpty ? fallbackTitle : title.trim();
    final chapters = <UmdChapterData>[];
    if (chapterOffsets.isNotEmpty) {
      for (var i = 0; i < chapterOffsets.length; i++) {
        final start = chapterOffsets[i];
        final end =
            i + 1 < chapterOffsets.length
                ? chapterOffsets[i + 1]
                : contentBytes.length;
        if (start < 0 || start >= contentBytes.length || end < start) {
          continue;
        }
        final content =
            _decodeUnicode(
              contentBytes.sublist(start, end),
            ).replaceAll('\u2029', '\n').trim();
        chapters.add(
          UmdChapterData(
            title:
                i < chapterTitles.length && chapterTitles[i].trim().isNotEmpty
                    ? chapterTitles[i].trim()
                    : '第 ${i + 1} 章',
            content: content,
          ),
        );
      }
    }

    if (chapters.isEmpty && contentBytes.isNotEmpty) {
      chapters.add(
        UmdChapterData(
          title: normalizedTitle,
          content:
              _decodeUnicode(contentBytes).replaceAll('\u2029', '\n').trim(),
        ),
      );
    }

    return UmdBookData(
      title: normalizedTitle,
      author: author.trim().isEmpty ? '未知作者' : author.trim(),
      chapters: chapters,
      coverBytes: coverBytes,
    );
  }

  String _decodeUnicode(List<int> bytes) {
    if (bytes.isEmpty) return '';
    try {
      final units = <int>[];
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        units.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return String.fromCharCodes(units);
    } catch (_) {
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    }
  }

  Uint8List _inflate(List<int> compressed) {
    final inflater = ZLibDecoder(raw: false);
    return Uint8List.fromList(inflater.convert(compressed));
  }
}

class _ByteReader {
  final Uint8List _bytes;
  int offset = 0;

  _ByteReader(this._bytes);

  bool get isEnd => offset >= _bytes.length;

  int readByte() {
    if (isEnd) return -1;
    return _bytes[offset++];
  }

  int readUint16() {
    if (offset + 2 > _bytes.length) return 0;
    final value = _bytes[offset] | (_bytes[offset + 1] << 8);
    offset += 2;
    return value;
  }

  int readUint32() {
    if (offset + 4 > _bytes.length) return 0;
    final value =
        _bytes[offset] |
        (_bytes[offset + 1] << 8) |
        (_bytes[offset + 2] << 16) |
        (_bytes[offset + 3] << 24);
    offset += 4;
    return value;
  }

  Uint8List readBytes(int length) {
    final safeLength = length.clamp(0, _bytes.length - offset);
    final data = Uint8List.sublistView(_bytes, offset, offset + safeLength);
    offset += safeLength;
    return Uint8List.fromList(data);
  }

  void skip(int length) {
    offset = (offset + length).clamp(0, _bytes.length);
  }
}
