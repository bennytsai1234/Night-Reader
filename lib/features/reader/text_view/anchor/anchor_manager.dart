/// Shared anchor geometry. Runtime owns intent; the viewport owns restore lifetime.
abstract final class AnchorManager {
  static double anchorOffsetInViewport(double viewportHeight) {
    final safeHeight = viewportHeight.isFinite && viewportHeight > 0
        ? viewportHeight
        : 1.0;
    return (safeHeight * 0.2).clamp(24.0, 120.0).toDouble();
  }
}
