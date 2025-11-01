// lib/services/booking_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BookingService {
  final _fire = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// Create a booking request. This client-side function:
  /// 1) reads bike doc to get ownerId
  /// 2) writes bookings/{}
  /// 3) writes notifications/{}
  Future<DocumentReference> requestBooking({
    required String bikeId,
    required DateTime startTime,
    required DateTime endTime,
    required double price,
    String? note,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // 1) Read bike doc to get ownerId
    final bikeSnap = await _fire.collection('bicycles').doc(bikeId).get();
    if (!bikeSnap.exists) throw Exception('Bike not found');
    final bikeData = bikeSnap.data()!;
    final ownerId = (bikeData['ownerId'] as String?) ?? '';
    if (ownerId.isEmpty) throw Exception('Bike owner not set');

    // 2) Create booking doc with status "requested"
    final bookingRef = await _fire.collection('bookings').add({
      'bikeId': bikeId,
      'ownerId': ownerId,
      'renterId': user.uid,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'price': price,
      'note': note ?? '',
      'status': 'requested', // requested -> owner will accept/reject
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 3) Optional: Write an in-app notification document for the owner
    await _fire.collection('notifications').add({
      'userId': ownerId, // target user
      'title': 'New booking request',
      'body': '${user.email ?? 'Someone'} requested a booking for ${bikeData['title'] ?? 'your bike'}.',
      'payload': {
        'bookingId': bookingRef.id,
        'bikeId': bikeId,
      },
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      'fromUserId': user.uid,
    });

    // (Optional) Trigger push notification server-side (Cloud Function) based on bookings creation.
    return bookingRef;
  }
}
