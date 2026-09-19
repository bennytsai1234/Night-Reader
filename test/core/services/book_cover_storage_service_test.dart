import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/book_cover_storage_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('換源會移交 user custom-cover cache 並退休舊 source asset dir', () async {
    final service = BookCoverStorageService();
    final oldBook = Book(
      bookUrl: 'https://old.example/book/1',
      origin: 'https://old.example',
      name: '測試書',
      customCoverUrl: 'https://user.example/custom.png',
    );
    final migratedBook = oldBook.copyWith(
      bookUrl: 'https://new.example/book/1',
      origin: 'https://new.example',
      originName: '新源',
    );

    final oldDir = await AppStoragePaths.bookAssetDir(
      BookCoverStorageService.bookStorageKey(oldBook),
      ensureExists: true,
    );
    final oldCustom = File(p.join(oldDir.path, 'custom-cover-source.png'));
    await oldCustom.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
    oldBook.customCoverLocalPath = oldCustom.path;
    migratedBook.customCoverLocalPath = oldCustom.path;

    final newDir = await AppStoragePaths.bookAssetDir(
      BookCoverStorageService.bookStorageKey(migratedBook),
    );
    addTearDown(() async {
      if (await oldDir.exists()) await oldDir.delete(recursive: true);
      if (await newDir.exists()) await newDir.delete(recursive: true);
    });

    await service.handoffSourceSwitchAssets(oldBook, migratedBook);

    expect(migratedBook.customCoverLocalPath, isNot(oldCustom.path));
    final migratedCustom = File(migratedBook.customCoverLocalPath!);
    expect(await migratedCustom.exists(), isTrue);
    expect(await migratedCustom.readAsBytes(), <int>[1, 2, 3, 4]);
    expect(await oldDir.exists(), isFalse);
    expect(
      p.isWithin(newDir.path, migratedCustom.path) ||
          p.equals(newDir.path, p.dirname(migratedCustom.path)),
      isTrue,
    );
  });
}
