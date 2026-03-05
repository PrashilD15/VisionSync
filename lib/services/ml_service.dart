import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../core/constants.dart';

class MLService {
  late Interpreter _interpreter;

  Future<void> initialize() async {
    try {
      // BUG FIX: Set numThreads for better performance on mobile
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(
        'assets/models/mobilefacenet.tflite',
        options: options,
      );
      print('MobileFaceNet loaded successfully.');
    } catch (e) {
      print('Failed to load model: $e');
    }
  }

  List<double> predict(img.Image image) {
    img.Image resizedImage =
    img.copyResizeCropSquare(image, size: Constants.modelImageSize);

    // BUG FIX: TFLite expects a 4D input tensor [1, 112, 112, 3].
    // Previously the code passed a flat Float32List which caused a shape
    // mismatch — the model would silently return a zeroed output vector,
    // causing every Euclidean distance to be huge and nothing ever matched.
    final input = _imageToInputTensor(resizedImage, Constants.modelImageSize);

    // Output shape: [1, 192]
    final output = List.generate(1, (_) => List.filled(192, 0.0));

    _interpreter.run(input, output);

    return List<double>.from(output[0]);
  }

  /// Returns a properly shaped [1][H][W][3] nested list for TFLite Flutter.
  /// Mean=127.5, Std=127.5 normalizes pixels to [-1.0, 1.0] as MobileFaceNet expects.
  List _imageToInputTensor(img.Image image, int inputSize) {
    // Outer list: batch dimension (always 1)
    return List.generate(1, (_) {
      // Height
      return List.generate(inputSize, (y) {
        // Width
        return List.generate(inputSize, (x) {
          final pixel = image.getPixel(x, y);
          // Channels: R, G, B normalized to [-1, 1]
          return [
            (pixel.r - 127.5) / 127.5,
            (pixel.g - 127.5) / 127.5,
            (pixel.b - 127.5) / 127.5,
          ];
        });
      });
    });
  }
}