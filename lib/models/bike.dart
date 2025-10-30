// lib/models/bike.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Bike {
  final String id;
  final String ownerId;
  final String title;
  final String description;
  final String locationText;
  final double hourlyRate;
  final List<String> images;
  final Timestamp createdAt;
  final bool available;

  Bike({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.description,
    required this.locationText,
    required this.hourlyRate,
    required this.images,
    required this.createdAt,
    this.available = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'title': title,
      'description': description,
      'locationText': locationText,
      'hourlyRate': hourlyRate,
      'images': images,
      'createdAt': createdAt,
      'available': available,
    };
  }

  factory Bike.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Bike(
      id: doc.id,
      ownerId: data['ownerId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      locationText: data['locationText'] ?? '',
      hourlyRate: (data['hourlyRate'] ?? 0).toDouble(),
      images: List<String>.from(data['images'] ?? []),
      createdAt: data['createdAt'] ?? Timestamp.now(),
      available: data['available'] ?? true,
    );
  }
}
