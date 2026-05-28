import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:night_reader/core/services/app_permission_service.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'change_cover_provider.dart';
import 'book_detail_provider.dart';
import 'widgets/cover/cover_header.dart';
import 'widgets/cover/cover_grid_item.dart';
import 'widgets/cover/cover_manual_input.dart';

class ChangeCoverSheet extends StatefulWidget {
  final String bookName;
  final String author;
  const ChangeCoverSheet({
    super.key,
    required this.bookName,
    required this.author,
  });
  @override
  State<ChangeCoverSheet> createState() => _ChangeCoverSheetState();
}

class _ChangeCoverSheetState extends State<ChangeCoverSheet> {
  final TextEditingController _urlController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final AppPermissionService _permissionService = AppPermissionService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChangeCoverProvider>().init(widget.bookName, widget.author);
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final allowed = await _permissionService.requestPhotoLibraryIfNeeded();
      if (!allowed) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('未取得相簿權限，無法選取封面圖片')));
        }
        return;
      }
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null && mounted) {
        context.read<BookDetailProvider>().updateCover('file://${image.path}');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('選取圖片失敗: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.topSheetXl,
      ),
      child: Column(
        children: [
          _buildHandle(),
          CoverHeader(bookName: widget.bookName, author: widget.author),
          Expanded(child: _buildCoverGrid()),
          CoverManualInput(
            urlController: _urlController,
            onPickImage: _pickImage,
          ),
        ],
      ),
    );
  }

  Widget _buildHandle() => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _buildCoverGrid() {
    return Consumer<ChangeCoverProvider>(
      builder: (context, provider, child) {
        if (provider.covers.isEmpty && !provider.isSearching)
          return const Center(child: Text('未找到相關封面'));
        return GridView.builder(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.65,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
          ),
          itemCount: provider.covers.length,
          itemBuilder:
              (context, index) => CoverGridItem(result: provider.covers[index]),
        );
      },
    );
  }
}
