// lib/screens/bike_details_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/bike.dart';
import '../services/bike_service.dart';
import '../services/booking_service.dart';
import 'add_bike_screen.dart';

class BookBikeScreen extends StatefulWidget {
  static const routeName = '/book_bike';
  const BookBikeScreen({super.key});

  @override
  State<BookBikeScreen> createState() => _BookBikeScreenState();
}

class _BookBikeScreenState extends State<BookBikeScreen> {
  bool _showFilters = false;
  String? _selectedPriceFilter; // null, '<10', '10-20', '>20'
  String? _selectedLocationFilter; // null or location text
  String? _selectedRatingFilter; // null, '4plus', '3plus', 'all'

  Future<List<String>> _getAvailableLocations() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('bicycles')
          .where('available', isEqualTo: true)
          .get();

      final locations = <String>{};
      for (var doc in snapshot.docs) {
        final location = doc.data()['locationText'] as String?;
        if (location != null && location.isNotEmpty) {
          locations.add(location);
        }
      }

      return locations.toList()..sort();
    } catch (e) {
      debugPrint('Error fetching locations: $e');
      return [];
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _availableBikesStream() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('bicycles')
        .where('available', isEqualTo: true)
        .where('status', isNotEqualTo: 'booked'); // Exclude booked bikes

    // Apply price filter if selected
    if (_selectedPriceFilter != null) {
      if (_selectedPriceFilter == '<10') {
        query = query.where('hourlyRate', isLessThan: 10);
      } else if (_selectedPriceFilter == '10-20') {
        query = query.where('hourlyRate', isGreaterThanOrEqualTo: 10)
            .where('hourlyRate', isLessThanOrEqualTo: 20);
      } else if (_selectedPriceFilter == '>20') {
        query = query.where('hourlyRate', isGreaterThan: 20);
      }
    }

    // Apply location filter if selected
    if (_selectedLocationFilter != null) {
      query = query.where('locationText', isEqualTo: _selectedLocationFilter);
    }

    return query.orderBy('createdAt', descending: true).snapshots();
  }

  Future<List<DocumentSnapshot<Map<String, dynamic>>>> _filterByRating(List<DocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (_selectedRatingFilter == null) {
      return docs;
    }

    final filteredDocs = <DocumentSnapshot<Map<String, dynamic>>>[];

    for (final doc in docs) {
      final ownerId = doc.data()!['ownerId'] as String?;
      if (ownerId == null) continue;

      // Get the actual average rating from reviews collection
      final rating = await _getActualAverageRating(ownerId);
      
      debugPrint('🔍 Bike: ${doc.data()!['title']}, Owner: $ownerId, Rating: $rating, Filter: $_selectedRatingFilter');

      if (_selectedRatingFilter == '4plus') {
        if (rating >= 4.0) {
          filteredDocs.add(doc);
        }
      } else if (_selectedRatingFilter == '3plus') {
        if (rating >= 3.0) {
          filteredDocs.add(doc);
        }
      }
    }

    return filteredDocs;
  }

  Future<double> _getActualAverageRating(String ownerId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
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
      debugPrint('Error fetching average rating for owner $ownerId: $e');
      return 0.0;
    }
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
        actions: [
          // Filter button
          IconButton(
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
            icon: const Icon(Icons.filter_list),
            tooltip: 'Toggle Filters',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Section - visible when _showFilters is true
          if (_showFilters)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[100],
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Price Filter
                    const Text(
                      'Price Filter (₹/hour)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Less than 10 Rs
                        FilterChip(
                          label: const Text('Less than ₹10'),
                          selected: _selectedPriceFilter == '<10',
                          onSelected: (selected) {
                            setState(() {
                              _selectedPriceFilter = selected ? '<10' : null;
                            });
                          },
                          backgroundColor: Colors.white,
                          selectedColor: Colors.green[100],
                          side: BorderSide(
                            color: _selectedPriceFilter == '<10' ? Colors.green : Colors.grey[300]!,
                          ),
                        ),
                        // Between 10 and 20 Rs
                        FilterChip(
                          label: const Text('₹10 - ₹20'),
                          selected: _selectedPriceFilter == '10-20',
                          onSelected: (selected) {
                            setState(() {
                              _selectedPriceFilter = selected ? '10-20' : null;
                            });
                          },
                          backgroundColor: Colors.white,
                          selectedColor: Colors.green[100],
                          side: BorderSide(
                            color: _selectedPriceFilter == '10-20' ? Colors.green : Colors.grey[300]!,
                          ),
                        ),
                        // Greater than 20 Rs
                        FilterChip(
                          label: const Text('Greater than ₹20'),
                          selected: _selectedPriceFilter == '>20',
                          onSelected: (selected) {
                            setState(() {
                              _selectedPriceFilter = selected ? '>20' : null;
                            });
                          },
                          backgroundColor: Colors.white,
                          selectedColor: Colors.green[100],
                          side: BorderSide(
                            color: _selectedPriceFilter == '>20' ? Colors.green : Colors.grey[300]!,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Location Filter
                    const Text(
                      'Location Filter',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<List<String>>(
                      future: _getAvailableLocations(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const SizedBox(
                            height: 40,
                            child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                          );
                        }

                        final locations = snapshot.data ?? [];

                        if (locations.isEmpty) {
                          return const Text('No locations available', style: TextStyle(fontSize: 12, color: Colors.grey));
                        }

                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: locations
                              .map((location) => FilterChip(
                                    label: Text(location),
                                    selected: _selectedLocationFilter == location,
                                    onSelected: (selected) {
                                      setState(() {
                                        _selectedLocationFilter = selected ? location : null;
                                      });
                                    },
                                    backgroundColor: Colors.white,
                                    selectedColor: Colors.blue[100],
                                    side: BorderSide(
                                      color: _selectedLocationFilter == location ? Colors.blue : Colors.grey[300]!,
                                    ),
                                  ))
                              .toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // Rating Filter
                    const Text(
                      'Rating Filter',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // 4+ stars
                        FilterChip(
                          label: const Text('⭐ 4 & Above'),
                          selected: _selectedRatingFilter == '4plus',
                          onSelected: (selected) {
                            setState(() {
                              _selectedRatingFilter = selected ? '4plus' : null;
                            });
                          },
                          backgroundColor: Colors.white,
                          selectedColor: Colors.orange[100],
                          side: BorderSide(
                            color: _selectedRatingFilter == '4plus' ? Colors.orange : Colors.grey[300]!,
                          ),
                        ),
                        // 3+ stars
                        FilterChip(
                          label: const Text('⭐ 3 & Above'),
                          selected: _selectedRatingFilter == '3plus',
                          onSelected: (selected) {
                            setState(() {
                              _selectedRatingFilter = selected ? '3plus' : null;
                            });
                          },
                          backgroundColor: Colors.white,
                          selectedColor: Colors.orange[100],
                          side: BorderSide(
                            color: _selectedRatingFilter == '3plus' ? Colors.orange : Colors.grey[300]!,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Clear filters button
                    if (_selectedPriceFilter != null || _selectedLocationFilter != null || _selectedRatingFilter != null)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedPriceFilter = null;
                              _selectedLocationFilter = null;
                              _selectedRatingFilter = null;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[400],
                          ),
                          child: const Text('Clear All Filters'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // Bike list (stream)
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _availableBikesStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                
                // If rating filter is applied, use FutureBuilder to handle async filtering
                if (_selectedRatingFilter != null) {
                  return FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
                    future: _filterByRating(docs),
                    builder: (context, filterSnapshot) {
                      if (filterSnapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (filterSnapshot.hasError) {
                        return Center(child: Text('Error: ${filterSnapshot.error}'));
                      }

                      final filteredDocs = filterSnapshot.data ?? [];

                      if (filteredDocs.isEmpty) {
                        return Center(
                          child: Text(
                            _selectedPriceFilter != null || _selectedLocationFilter != null || _selectedRatingFilter != null
                                ? 'No bicycles found matching your filters.'
                                : 'No bicycles listed yet.\nAsk someone to add a bike!',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: filteredDocs.length,
                        itemBuilder: (ctx, i) {
                          final doc = filteredDocs[i];
                          final data = doc.data();
                          if (data != null) {
                            return _bikeCard(context, data, doc.id);
                          }
                          return const SizedBox.shrink();
                        },
                      );
                    },
                  );
                }

                // No rating filter, just display the list
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      _selectedPriceFilter != null || _selectedLocationFilter != null
                          ? 'No bicycles found matching your filters.'
                          : 'No bicycles listed yet.\nAsk someone to add a bike!',
                      textAlign: TextAlign.center,
                    ),
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
          ),
        ],
      ),
    );
  }
}
