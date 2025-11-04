// lib/models/bike.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Bike {
  final String id;
  final String ownerId;
  final String ownerName;
  final String title;
  final String description;
  final String locationText;
  final double hourlyRate;
  final List<String> images;
  final String contactNumber;
  final bool available;
  final double avgRating;
  final int ratingCount;
  final Timestamp? createdAt;
  final String status; // "booked" or "unbooked"

  Bike({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.title,
    required this.description,
    required this.locationText,
    required this.hourlyRate,
    required this.images,
    required this.contactNumber,
    this.available = true,
    this.avgRating = 0.0,
    this.ratingCount = 0,
    this.createdAt,
    this.status = 'unbooked',
  });

  /// Convert this Bike to a map suitable for Firestore.
  /// If createdAt is null, caller can let Firestore set server timestamp
  /// by passing FieldValue.serverTimestamp() when creating.
  Map<String, dynamic> toMap({bool useServerTimestampForCreatedAt = false}) {
    final map = <String, dynamic>{
      'ownerId': ownerId,
      'ownerName': ownerName,
      'title': title,
      'description': description,
      'locationText': locationText,
      'hourlyRate': hourlyRate,
      'images': images,
      'contactNumber': contactNumber,
      'available': available,
      'avgRating': avgRating,
      'ratingCount': ratingCount,
      'status': status,
    };

    if (useServerTimestampForCreatedAt) {
      map['createdAt'] = FieldValue.serverTimestamp();
    } else if (createdAt != null) {
      map['createdAt'] = createdAt;
    }

    return map;
  }

  /// Create a Bike model from a Firestore document snapshot.
  factory Bike.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    return Bike(
      id: doc.id,
      ownerId: (data['ownerId'] as String?) ?? '',
      ownerName: (data['ownerName'] as String?) ?? '',
      title: (data['title'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      locationText: (data['locationText'] as String?) ?? '',
      hourlyRate: (data['hourlyRate'] is num)
          ? (data['hourlyRate'] as num).toDouble()
          : 0.0,
      images: (data['images'] is List)
          ? List<String>.from(data['images'] as List)
          : <String>[],
      contactNumber: (data['contactNumber'] as String?) ?? '',
      available: (data['available'] is bool) ? data['available'] as bool : true,
      avgRating: (data['avgRating'] is num)
          ? (data['avgRating'] as num).toDouble()
          : 0.0,
      ratingCount:
          (data['ratingCount'] is int) ? data['ratingCount'] as int : (data['ratingCount'] is num ? (data['ratingCount'] as num).toInt() : 0),
      createdAt: (data['createdAt'] is Timestamp) ? data['createdAt'] as Timestamp : null,
      status: (data['status'] as String?) ?? 'unbooked',
    );
  }
}
