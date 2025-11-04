// lib/screens/bike_details_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/bike.dart';
import '../services/bike_service.dart';
import '../services/booking_service.dart';
import 'add_bike_screen.dart';

class BookBikeScreen extends StatelessWidget {
  static const routeName = '/book_bike';
  const BookBikeScreen({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> _availableBikesStream() {
    return FirebaseFirestore.instance
        .collection('bicycles')
        .where('available', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  void _showBikeDetails(BuildContext context, Map<String, dynamic> bikeData, String bikeId) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final ownerId = (bikeData['ownerId'] as String?) ?? '';

    // Build a Bike model (lightweight) to pass into edit screen if needed
    final bikeModel = Bike(
      id: bikeId,
      ownerId: ownerId,
      ownerName: (bikeData['ownerName'] as String?) ?? '',
      title: (bikeData['title'] as String?) ?? '',
      description: (bikeData['description'] as String?) ?? '',
      locationText: (bikeData['locationText'] as String?) ?? '',
      hourlyRate: (bikeData['hourlyRate'] is num) ? (bikeData['hourlyRate'] as num).toDouble() : 0.0,
      images: (bikeData['images'] is List) ? List<String>.from(bikeData['images'] as List) : <String>[],
      contactNumber: (bikeData['contactNumber'] as String?) ?? '',
      available: (bikeData['available'] is bool) ? bikeData['available'] as bool : true,
      avgRating: (bikeData['avgRating'] is num) ? (bikeData['avgRating'] as num).toDouble() : 0.0,
      ratingCount: (bikeData['ratingCount'] is int) ? bikeData['ratingCount'] as int : (bikeData['ratingCount'] is num ? (bikeData['ratingCount'] as num).toInt() : 0),
      createdAt: (bikeData['createdAt'] is Timestamp) ? bikeData['createdAt'] as Timestamp : null,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: MediaQuery.of(ctx).viewInsets.add(const EdgeInsets.all(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(bikeData['title'] ?? 'No title', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if ((bikeData['images'] ?? []).isNotEmpty)
                SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: CachedNetworkImage(
                    imageUrl: (bikeData['images'] as List).isNotEmpty ? bikeData['images'][0] : '',
                    fit: BoxFit.cover,
                    placeholder: (c, u) => Container(color: Colors.grey[200]),
                    errorWidget: (c, u, e) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image)),
                  ),
                ),
              const SizedBox(height: 12),
              Text('Location: ${bikeData['locationText'] ?? '-'}'),
              const SizedBox(height: 8),
              Text('Rate: ₹${(bikeData['hourlyRate'] ?? 0).toString()} / hour'),
              const SizedBox(height: 12),
              Text(bikeData['description'] ?? '', maxLines: 6, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 16),

              // Action buttons
              Row(
                children: [
                  // Request Booking always visible (placeholder)
                  Expanded(
                    child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          int hours = 1;
                          double rate = (bikeData['hourlyRate'] is num) ? (bikeData['hourlyRate'] as num).toDouble() : 0.0;
                          double totalCost = rate;
                          await showDialog(
                            context: context,
                            builder: (dialogCtx) {
                              return StatefulBuilder(
                                builder: (context, setState) {
                                  return AlertDialog(
                                    title: const Text('Book Bicycle'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Enter number of hours:'),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                initialValue: hours.toString(),
                                                keyboardType: TextInputType.number,
                                                decoration: const InputDecoration(
                                                  border: OutlineInputBorder(),
                                                  isDense: true,
                                                ),
                                                onChanged: (val) {
                                                  final parsed = int.tryParse(val);
                                                  if (parsed != null && parsed > 0) {
                                                    setState(() {
                                                      hours = parsed;
                                                      totalCost = rate * hours;
                                                    });
                                                  }
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Text('Total cost: ₹${totalCost.toStringAsFixed(2)}'),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(dialogCtx).pop(),
                                        child: const Text('Cancel'),
                                      ),
                                    ElevatedButton(
                                      onPressed: () async {
                                        try {
                                          await BookingService().requestBooking(
                                            bikeId: bikeId,
                                            startTime: DateTime.now(),
                                            endTime: DateTime.now().add(Duration(hours: hours)),
                                            price: totalCost,
                                          );
                                          Navigator.of(dialogCtx).pop();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Booking request sent!')),
                                          );
                                        } catch (e) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Failed to request booking: $e')),
                                          );
                                        }
                                      },
                                      child: const Text('Confirm Booking'),
                                    ),
                                    ],
                                  );
                                },
                              );
                            },
                          );
                        },
                        icon: const Icon(Icons.request_page),
                        label: const Text('Request Booking'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // If current user is owner, show Edit and Delete buttons
              if (currentUid != null && ownerId == currentUid) ...[
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.of(ctx).pop(); // close the details sheet
                          // Open AddBikeScreen in edit mode by passing the Bike object
                          final updatedBikeId = await Navigator.push<String?>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddBikeScreen(bike: bikeModel),
                            ),
                          );

                          if (updatedBikeId != null && updatedBikeId.isNotEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Bike updated')),
                            );
                            // Firestore stream will auto-refresh the list
                          }
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (confirmCtx) {
                              return AlertDialog(
                                title: const Text('Delete listing?'),
                                content: const Text('Are you sure you want to permanently delete this bike listing? This cannot be undone.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(confirmCtx).pop(false), child: const Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.of(confirmCtx).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                                ],
                              );
                            },
                          );

                          if (confirmed == true) {
                            try {
                              final bikeService = BikeService();
                              await bikeService.deleteBike(bikeId: bikeId, deleteImagesFromStorage: true);
                              Navigator.of(ctx).pop(); // ensure details sheet closed
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Bike deleted')),
                              );
                              // Firestore stream will auto-refresh
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to delete bike: $e')),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.delete),
                        label: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _bikeCard(BuildContext context, Map<String, dynamic> d, String id) {
    final images = (d['images'] ?? []) as List<dynamic>;
    final thumb = images.isNotEmpty ? images.first as String : '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () => _showBikeDetails(context, d, id),
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: 120,
              height: 100,
              color: Colors.grey[200],
              child: thumb.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      width: 120,
                      height: 100,
                      placeholder: (c, u) => Container(color: Colors.grey[200]),
                      errorWidget: (c, u, e) => const Icon(Icons.broken_image),
                    )
                  : const Icon(Icons.directions_bike, size: 48, color: Colors.grey),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d['title'] ?? 'Untitled', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(d['locationText'] ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Text('₹${(d['hourlyRate'] ?? 0).toString()} / hour', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Bicycles'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _availableBikesStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text('No bicycles listed yet.\nAsk someone to add a bike!', textAlign: TextAlign.center),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final doc = docs[i];
              final data = doc.data();
              return _bikeCard(context, data, doc.id);
            },
          );
        },
      ),
    );
  }
}
