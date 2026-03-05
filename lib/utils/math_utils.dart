import 'dart:math';

class MathUtils {
  // Calculates the Euclidean distance between two face vectors
  // A distance of 0.0 means it is the exact same photo.
  // A distance < 1.0 (threshold) usually indicates the same person.
  static double euclideanDistance(List<double> e1, List<double> e2) {
    if (e1.length != e2.length) {
      throw Exception("Vectors must be the same length to compare them");
    }

    double sum = 0.0;
    for (int i = 0; i < e1.length; i++) {
      sum += pow((e1[i] - e2[i]), 2);
    }
    return sqrt(sum);
  }
}