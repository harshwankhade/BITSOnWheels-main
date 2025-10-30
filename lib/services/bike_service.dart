// lib/services/bike_service.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class BikeService {
  final _bikes = FirebaseFirestore.instance.collection('bicycles');
  final _storage = FirebaseStorage.instance;
  final _auth = FirebaseAuth.instance;

  /// Uploads a single file and returns its download URL.
  Future<String> uploadImageFile({
    required File file,
    required void Function(double)? onProgress,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not authenticated');

    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child('bikes/$uid/$fileName');

    final uploadTask = ref.putFile(file);

    // Listen for progress if callback provided
    uploadTask.snapshotEvents.listen((snapshot) {
      final bytesTransferred = snapshot.bytesTransferred.toDouble();
      final total = snapshot.totalBytes.toDouble();
      if (onProgress != null && total > 0) {
        onProgress(bytesTransferred / total);
      }
    });

    final taskSnapshot = await uploadTask;
    return await taskSnapshot.ref.getDownloadURL();
  }

  /// Creates bike document; images must be uploaded first (urls).
  Future<DocumentReference> createBike({
    required String title,
    required String description,
    required String locationText,
    required double hourlyRate,
    required List<String> imageUrls,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final docRef = await _bikes.add({
      'ownerId': user.uid,
      'title': title,
      'description': description,
      'locationText': locationText,
      'hourlyRate': hourlyRate,
      'images': imageUrls,
      'available': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return docRef;
  }
}
