import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_open_target.dart';
import 'package:night_reader/features/reader_v2/shell/reader_v2_page.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// Custom page route that provides a polished book-opening transition.
///
/// The animation has three phases:
/// 1. **Cover fly-in** (0–40%): Background darkens + cover scales in
/// 2. **Book open** (35–70%): 3D perspective rotation simulating a page turn
/// 3. **Reader reveal** (60–100%): Cover fades, reader content appears
class BookOpenRoute extends PageRouteBuilder {
  BookOpenRoute({
    required this.book,
    this.openTarget,
    this.initialChapters = const <BookChapter>[],
    this.heroTag,
  }) : super(
         pageBuilder:
             (context, animation, secondaryAnimation) => ReaderV2Page(
               book: book,
               openTarget: openTarget,
               initialChapters: initialChapters,
             ),
         transitionDuration: const Duration(milliseconds: 700),
         reverseTransitionDuration: const Duration(milliseconds: 500),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           return _BookOpenTransition(
             animation: animation,
             heroTag: heroTag,
             child: child,
           );
         },
       );

  final Book book;
  final ReaderV2OpenTarget? openTarget;
  final List<BookChapter> initialChapters;
  final String? heroTag;
}

class _BookOpenTransition extends StatelessWidget {
  const _BookOpenTransition({
    required this.animation,
    required this.child,
    this.heroTag,
  });

  final Animation<double> animation;
  final Widget child;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    // Phase 1: Background dimming (0% → 40%)
    final backgroundDim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.40, curve: Curves.easeOut),
      ),
    );

    // Phase 2: Page turn perspective rotation (35% → 70%)
    final pageRotation = Tween<double>(begin: 0.0, end: math.pi * 0.5).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.35, 0.70, curve: Curves.easeInOutCubic),
      ),
    );

    // Phase 3: Reader content fade-in (60% → 100%)
    final contentOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.60, 1.0, curve: Curves.easeOut),
      ),
    );

    // Cover scale: starts slightly smaller, grows to fill
    final coverScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic),
      ),
    );

    // Cover opacity: visible during phases 1-2, fades during phase 3
    final coverOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.65, 0.90, curve: Curves.easeIn),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: The reader content (destination page)
            Opacity(opacity: contentOpacity.value, child: child),

            // Layer 2: Book-opening overlay
            if (animation.value < 0.95)
              Positioned.fill(
                child: IgnorePointer(
                  child: _buildBookOpenOverlay(
                    backgroundDim: backgroundDim.value,
                    pageRotation: pageRotation.value,
                    coverScale: coverScale.value,
                    coverOpacity: coverOpacity.value,
                    context: context,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBookOpenOverlay({
    required double backgroundDim,
    required double pageRotation,
    required double coverScale,
    required double coverOpacity,
    required BuildContext context,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Dimmed background
        Container(color: Colors.black.withValues(alpha: backgroundDim * 0.6)),

        // Book cover with 3D perspective rotation
        if (coverOpacity > 0.01)
          Center(
            child: Opacity(
              opacity: coverOpacity,
              child: Transform(
                alignment: Alignment.centerLeft,
                transform:
                    Matrix4.identity()
                      ..setEntry(3, 2, 0.001) // perspective
                      ..rotateY(-pageRotation), // rotate around Y axis
                child: Transform.scale(
                  scale: coverScale,
                  child: _buildCoverPlaceholder(context),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCoverPlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 180,
      height: 260,
      decoration: BoxDecoration(
        borderRadius: AppRadius.cardLg,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors:
              isDark
                  ? [const Color(0xFF2A3A35), const Color(0xFF1A2A24)]
                  : [const Color(0xFFE8DCC8), const Color(0xFFD4C4A8)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(4, 8),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.menu_book_rounded,
          size: 48,
          color:
              isDark
                  ? const Color(0xFFB9D7C2).withValues(alpha: 0.6)
                  : const Color(0xFF244739).withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
