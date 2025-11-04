// lib/models/notification_item.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  general,
  bookingRequest,
  bookingAccepted,
  bookingRejected,
  bookingStarted,
  bookingEnded,
}

class NotificationItem {
  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final Map<String, dynamic>? metadata;
  final bool read;
  final Timestamp createdAt;

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.metadata,
    required this.read,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'type': type.name,
      'metadata': metadata,
      'read': read,
      'createdAt': createdAt,
    };
  }

  factory NotificationItem.fromMap(Map<String, dynamic> map, String id) {
    return NotificationItem(
      id: id,
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      type: _parseType(map['type']),
      metadata: map['metadata'],
      read: map['read'] ?? false,
      createdAt: map['createdAt'] ?? Timestamp.now(),
    );
  }

  static NotificationType _parseType(String? s) {
    switch (s) {
      case 'bookingRequest':
        return NotificationType.bookingRequest;
      case 'bookingAccepted':
        return NotificationType.bookingAccepted;
      case 'bookingRejected':
        return NotificationType.bookingRejected;
      case 'bookingStarted':
        return NotificationType.bookingStarted;
      case 'bookingEnded':
        return NotificationType.bookingEnded;
      default:
        return NotificationType.general;
    }
  }
}