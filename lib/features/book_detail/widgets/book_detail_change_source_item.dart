import 'package:night_reader/shared/widgets/source_option_tile.dart';

class BookDetailChangeSourceItem extends SourceOptionTile {
  const BookDetailChangeSourceItem({
    super.key,
    required super.searchBook,
    super.isCurrent = false,
    super.onTap,
  });
}
