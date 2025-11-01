// lib/services/bike_service.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class BikeService {
  final _bikes = FirebaseFirestore.instance.collection('bicycles');
  final _storage = FirebaseStorage.instance;
  final _auth = FirebaseAuth.instance;
  final _fire = FirebaseFirestore.instance;

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
  /// Adds ownerId and ownerName (fetched from users/{uid} if available),
  /// and initializes avgRating/ratingCount.
  Future<DocumentReference> createBike({
    required String title,
    required String description,
    required String locationText,
    required double hourlyRate,
    required List<String> imageUrls,
    required String contactNumber,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Try to read the user's profile doc to get a display name
    String ownerName = user.displayName ?? user.email ?? 'Unknown';

    try {
      final userDoc = await _fire.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        if (data != null) {
          final fromDoc = (data['name'] as String?)?.trim();
          if (fromDoc != null && fromDoc.isNotEmpty) {
            ownerName = fromDoc;
          }
        }
      }
    } catch (e) {
      // Non-fatal: if read fails, fall back to auth-provided name/email
      // Useful to log in debug but don't block creation
      // print('Warning: failed to fetch user name for owner: $e');
    }

    final docRef = await _bikes.add({
      'ownerId': user.uid,
      'ownerName': ownerName,
      'title': title,
      'description': description,
      'locationText': locationText,
      'hourlyRate': hourlyRate,
      'images': imageUrls,
      'contactNumber': contactNumber,
      'available': true,
      // rating fields initialized; update when reviews are created
      'avgRating': 0.0,
      'ratingCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return docRef;
  }

  /// Update fields for an existing bike document.
  ///
  /// - `bikeId` (required): document id of the bike.
  /// - The other fields are optional; only non-null fields will be updated.
  /// - If `newImageUrls` is provided it will replace the `images` list in Firestore.
  /// - If `removedImageUrls` is provided, those image URLs will be removed from Firebase Storage.
  ///
  /// Example:
  /// await updateBike(bikeId: 'abc', title: 'New title', newImageUrls: newUrls, removedImageUrls: removed);
  Future<void> updateBike({
    required String bikeId,
    String? title,
    String? description,
    String? locationText,
    double? hourlyRate,
    List<String>? newImageUrls, // replace images with this list if provided
    List<String>? removedImageUrls, // delete these from storage (if owned by user)
    String? contactNumber,
    bool? available,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final docRef = _bikes.doc(bikeId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) throw Exception('Bike not found');

    final data = snapshot.data();
    final ownerId = (data?['ownerId'] as String?) ?? '';
    if (ownerId != user.uid) {
      throw Exception('Not authorized to update this bike');
    }

    final updateData = <String, dynamic>{};
    if (title != null) updateData['title'] = title;
    if (description != null) updateData['description'] = description;
    if (locationText != null) updateData['locationText'] = locationText;
    if (hourlyRate != null) updateData['hourlyRate'] = hourlyRate;
    if (newImageUrls != null) updateData['images'] = newImageUrls;
    if (contactNumber != null) updateData['contactNumber'] = contactNumber;
    if (available != null) updateData['available'] = available;

    if (updateData.isNotEmpty) {
      await docRef.update(updateData);
    }

    // Delete removed images from storage (non-blocking for UI but await to surface errors)
    if (removedImageUrls != null && removedImageUrls.isNotEmpty) {
      for (final url in removedImageUrls) {
        try {
          await _deleteImageByUrlIfOwned(url, user.uid);
        } catch (e) {
          // ignore/log - don't block the update because of storage deletion failure
        }
      }
    }
  }

  /// Delete a bike document and optionally delete its images from storage.
  ///
  /// - Verifies ownership before deleting.
  /// - If deleteImagesFromStorage is true, attempts to delete each image URL listed in the bike doc.
  Future<void> deleteBike({
    required String bikeId,
    bool deleteImagesFromStorage = true,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final docRef = _bikes.doc(bikeId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) throw Exception('Bike not found');

    final data = snapshot.data();
    final ownerId = (data?['ownerId'] as String?) ?? '';
    if (ownerId != user.uid) throw Exception('Not authorized to delete this bike');

    final images = List<String>.from(data?['images'] ?? []);

    // Delete document first so queries won't show a partially-deleted item.
    await docRef.delete();

    if (deleteImagesFromStorage) {
      for (final url in images) {
        try {
          await _deleteImageByUrlIfOwned(url, user.uid);
        } catch (e) {
          // ignore or log; image might already be gone or not deletable
        }
      }
    }
  }

  /// Helper: deletes a storage object given a download URL if it appears to belong to the user's folder.
  ///
  /// This attempts to prevent accidental deletion of other users' files by checking the path contains the uid.
  /// If the URL does not contain the uid we still try to delete (in case you store differently), but you can
  /// change this behavior if you want stricter checks.
  Future<void> _deleteImageByUrlIfOwned(String url, String uid) async {
    try {
      final ref = _storage.refFromURL(url);
      // Basic safety check: ensure the storage path contains the uid (optional, adjust as needed)
      final fullPath = ref.fullPath; // e.g. "bikes/<uid>/<filename>"
      if (fullPath.contains('/$uid/') || fullPath.contains('bikes/$uid/')) {
        await ref.delete();
      } else {
        // Path doesn't include uid — still attempt delete but this is a guard you can change.
        await ref.delete();
      }
    } on FirebaseException catch (e) {
      // If the object doesn't exist or permission denied, surface a clear message for debugging.
      if (e.code == 'object-not-found') {
        // already deleted; ignore
        return;
      }
      // rethrow other exceptions so callers may log/handle if needed
      rethrow;
    } catch (e) {
      // ignore other errors
      return;
    }
  }
}
