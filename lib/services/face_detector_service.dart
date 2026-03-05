import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorService {
  FaceDetector? _faceDetector;

  // ── BUG FIX: guard flag ────────────────────────────────────────────────────
  // When RecognitionScreen disposes this service and RegisterScreen then calls
  // initialize() again, the old closed detector would throw
  // "Detector already closed".  We now null the field on dispose and create a
  // fresh FaceDetector on every initialize() call.
  bool _initialized = false;

  void initialize() {
    // Close any existing detector before creating a new one
    _faceDetector?.close();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        // accurate mode finds faces reliably across lighting and angles.
        // fast mode misses faces that are slightly off-centre or dim.
        performanceMode: FaceDetectorMode.accurate,
        enableTracking: true,
        // headEulerAngles needed for quality hints in RegisterScreen
        enableClassification: false,
        enableLandmarks: false,
        minFaceSize: 0.15,
      ),
    );
    _initialized = true;
  }

  Future<List<Face>> getFaces(InputImage inputImage) async {
    if (!_initialized || _faceDetector == null) return [];
    return await _faceDetector!.processImage(inputImage);
  }

  void dispose() {
    _faceDetector?.close();
    _faceDetector = null;
    _initialized  = false;
  }
}