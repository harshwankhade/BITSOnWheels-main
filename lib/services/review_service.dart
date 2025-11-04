import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReviewService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// Submit a review/rating for a bike and owner
  Future<void> submitReview({
    required String bikeId,
    required String ownerId,
    required String bookingId,
    required double rating,
    required String comment,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not authenticated');

    // Add review to reviews collection
    await _firestore.collection('reviews').add({
      'bikeId': bikeId,
      'ownerId': ownerId,
      'renterId': currentUser.uid,
      'bookingId': bookingId,
      'rating': rating,
      'comment': comment,
      'createdAt': FieldValue.serverTimestamp(),
    });

    print('⭐ Review submitted: $rating stars for owner $ownerId');
  }

  /// Get average rating for an owner
  Future<double> getAverageRatingForOwner(String ownerId) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('ownerId', isEqualTo: ownerId)
          .get();

      if (snapshot.docs.isEmpty) return 0.0;

      final ratings = snapshot.docs
          .map((doc) => (doc.data()['rating'] as num?)?.toDouble() ?? 0.0)
          .toList();

      final average = ratings.reduce((a, b) => a + b) / ratings.length;
      return double.parse(average.toStringAsFixed(1));
    } catch (e) {
      print('Error fetching average rating: $e');
      return 0.0;
    }
  }

  /// Get total number of reviews for an owner
  Future<int> getReviewCountForOwner(String ownerId) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('ownerId', isEqualTo: ownerId)
          .get();

      return snapshot.docs.length;
    } catch (e) {
      print('Error fetching review count: $e');
      return 0;
    }
  }

  /// Get all reviews for a bike
  Future<List<Map<String, dynamic>>> getReviewsForBike(String bikeId) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('bikeId', isEqualTo: bikeId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('Error fetching reviews: $e');
      return [];
    }
  }
}
