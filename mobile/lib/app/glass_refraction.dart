import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Clear glass with one lightweight full-pane refraction pass.
///
/// A previous version used three high-quality backdrop filters for every
/// scrolling card. On mobile web each filter has to re-sample the page during
/// a drag, so a long list could turn one gesture into dozens of offscreen
/// renders. One medium-quality pass keeps the transparent lens effect while
/// leaving substantially more frame budget for scrolling and input.
class GlassRefraction extends StatelessWidget {
  /// This only moves backdrop pixels; it does not add tint, absorption or a
  /// blur layer. Kept modest so the single pass remains smooth on mobile web.
  static const refractionScale = .82;
  final double radius;
  const GlassRefraction({super.key, required this.radius});

  @override
  Widget build(BuildContext context) =>
      // A retained offset layer anchors the matrix at this surface, not at the
      // page origin. Unlike an opacity layer it still samples the real backdrop.
      IgnorePointer(child:
          RepaintBoundary(child: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth, h = constraints.maxHeight;
        if (!w.isFinite || !h.isFinite || w < 12 || h < 12) {
          return const SizedBox.shrink();
        }
        final displacement =
            (w < h ? w : h).clamp(0.0, 80.0) / 8 * refractionScale;
        final matrix = Float64List.fromList([
          1 + displacement * 2 / w,
          0,
          0,
          0,
          0,
          1 + displacement * 2 / h,
          0,
          0,
          0,
          0,
          1,
          0,
          -displacement,
          -displacement,
          0,
          1,
        ]);
        // The parent StudySurface already clips this layer to the same rounded
        // rectangle. Avoiding a second clip saves another compositing step.
        return BackdropFilter(
            filter: ui.ImageFilter.matrix(matrix,
                filterQuality: FilterQuality.medium),
            child: const SizedBox.expand());
      })));
}

/// Keeps scrolling text from colliding with transparent navigation labels.
/// A clip preserves access to the real backdrop for nested glass lenses, unlike
/// an opacity saveLayer. The wallpaper stays visible behind the navigation.
class GlassContentViewport extends StatelessWidget {
  final bool enabled;
  final Widget child;
  const GlassContentViewport(
      {super.key, required this.enabled, required this.child});
  @override
  Widget build(BuildContext context) {
    // Keep this wrapper in the element tree in both modes.  Returning `child`
    // directly when glass was disabled re-parented every tab and disposed its
    // ListView, which sent a reader back to the top of a long page.
    final clipper =
        enabled ? _ContentInsets(MediaQuery.paddingOf(context)) : null;
    return ClipRect(clipper: clipper, child: child);
  }
}

class _ContentInsets extends CustomClipper<Rect> {
  final EdgeInsets padding;
  const _ContentInsets(this.padding);
  @override
  Rect getClip(Size size) {
    final top = padding.top.clamp(0.0, size.height);
    final bottom = (size.height - padding.bottom).clamp(top, size.height);
    return Rect.fromLTRB(0, top, size.width, bottom);
  }

  @override
  bool shouldReclip(_ContentInsets oldClipper) => oldClipper.padding != padding;
}
