class Student {
  String id;
  String name;
  List<double> faceEmbedding; // The 192-number array representing their face

  Student({
    required this.id,
    required this.name,
    required this.faceEmbedding,
  });

  // Convert to JSON to send to Firebase Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'faceEmbedding': faceEmbedding,
    };
  }

  // Create a Student object from Firebase data
  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      faceEmbedding: List<double>.from(map['faceEmbedding'] ?? []),
    );
  }
}