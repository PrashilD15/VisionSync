class Constants {
  // MobileFaceNet requires 112x112 pixel images
  static const int modelImageSize = 112;

  // The threshold for Euclidean distance.
  // Lower = stricter match. Higher = more false positives.
  // 1.0 is a good starting point for MobileFaceNet.
  static const double matchingThreshold = 1.0;
}