import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class ImageConverter {
  // Main entry point for converting the camera frame
  static img.Image? convertCameraImage(CameraImage image) {
    if (image.format.group == ImageFormatGroup.yuv420) {
      return _convertYUV420ToImage(image);
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      return _convertBGRA8888ToImage(image);
    }
    return null;
  }

  // iOS Conversion
  static img.Image _convertBGRA8888ToImage(CameraImage image) {
    return img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra,
    );
  }

  // Android Conversion (YUV to RGB math)
  static img.Image _convertYUV420ToImage(CameraImage image) {
    final uvRowStride = image.planes[1].bytesPerRow;
    final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    final imgImage = img.Image(width: image.width, height: image.height);

    for (int y = 0; y < image.height; y++) {
      int uvRow = image.planes[1].bytesPerRow * (y >> 1);

      for (int x = 0; x < image.width; x++) {
        int uvIndex = uvRow + (x >> 1) * uvPixelStride;

        int indexY = y * image.planes[0].bytesPerRow + x;
        int yValue = image.planes[0].bytes[indexY];
        int uValue = image.planes[1].bytes[uvIndex];
        int vValue = image.planes[2].bytes[uvIndex];

        // Standard YUV to RGB conversion formula
        int r = (yValue + 1.402 * (vValue - 128)).toInt();
        int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).toInt();
        int b = (yValue + 1.772 * (uValue - 128)).toInt();

        // Clamp values between 0 and 255
        imgImage.setPixelRgb(
            x,
            y,
            r.clamp(0, 255),
            g.clamp(0, 255),
            b.clamp(0, 255)
        );
      }
    }
    return imgImage;
  }
}