import 'package:flutter/material.dart';

class FacePainter extends CustomPainter {
  final Rect?  animatedRect;
  final Size   imageSize;
  final Color  boxColor;
  final bool   isFrontCamera;
  final String? label; // <-- NEW: Label to display above the box

  const FacePainter({
    required this.animatedRect,
    required this.imageSize,
    this.boxColor     = Colors.greenAccent,
    this.isFrontCamera = true,
    this.label, // <-- NEW
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (animatedRect == null || imageSize.isEmpty) return;

    // Scale factors from image pixels → canvas pixels
    final double scaleX = canvasSize.width  / imageSize.width;
    final double scaleY = canvasSize.height / imageSize.height;

    double left   = animatedRect!.left   * scaleX;
    double top    = animatedRect!.top    * scaleY;
    double right  = animatedRect!.right  * scaleX;
    double bottom = animatedRect!.bottom * scaleY;

    // Flip X for front camera so the box matches the mirrored preview
    if (isFrontCamera) {
      final double flippedLeft  = canvasSize.width - right;
      final double flippedRight = canvasSize.width - left;
      left  = flippedLeft;
      right = flippedRight;
    }

    final Rect scaledRect = Rect.fromLTRB(left, top, right, bottom);

    // Subtle tinted fill
    canvas.drawRect(
      scaledRect,
      Paint()
        ..style   = PaintingStyle.fill
        ..color   = boxColor.withOpacity(0.07),
    );

    // Corner bracket lines
    final Paint p = Paint()
      ..color     = boxColor
      ..strokeWidth = 3.5
      ..style     = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double c = scaledRect.shortestSide * 0.20; // corner arm length

    // Top-left
    canvas.drawLine(scaledRect.topLeft, scaledRect.topLeft.translate( c,  0), p);
    canvas.drawLine(scaledRect.topLeft, scaledRect.topLeft.translate( 0,  c), p);
    // Top-right
    canvas.drawLine(scaledRect.topRight, scaledRect.topRight.translate(-c,  0), p);
    canvas.drawLine(scaledRect.topRight, scaledRect.topRight.translate( 0,  c), p);
    // Bottom-left
    canvas.drawLine(scaledRect.bottomLeft, scaledRect.bottomLeft.translate( c,  0), p);
    canvas.drawLine(scaledRect.bottomLeft, scaledRect.bottomLeft.translate( 0, -c), p);
    // Bottom-right
    canvas.drawLine(scaledRect.bottomRight, scaledRect.bottomRight.translate(-c,  0), p);
    canvas.drawLine(scaledRect.bottomRight, scaledRect.bottomRight.translate( 0, -c), p);

    // --- NEW: Draw the text label above the bounding box ---
    if (label != null && label!.isNotEmpty) {
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: boxColor,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black45, // Slight background for contrast
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout();

      // Center the text horizontally with the box
      final double centerX = left + (right - left) / 2;
      final double xOffset = centerX - textPainter.width / 2;
      double yOffset = top - textPainter.height - 8;

      // Prevent the text from being cut off at the top edge of the screen
      if (yOffset < 0) {
        yOffset = bottom + 8;
      }

      textPainter.paint(canvas, Offset(xOffset, yOffset));
    }
  }

  @override
  bool shouldRepaint(FacePainter old) =>
      old.animatedRect   != animatedRect   ||
          old.imageSize      != imageSize      ||
          old.boxColor       != boxColor       ||
          old.isFrontCamera  != isFrontCamera  ||
          old.label          != label; // <-- NEW
}