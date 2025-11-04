// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bitsonwheelsv1/services/auth_service.dart';
import 'package:bitsonwheelsv1/screens/add_bike_screen.dart';
import 'package:bitsonwheelsv1/services/bike_service.dart';
import 'package:bitsonwheelsv1/services/booking_service.dart';
import 'package:bitsonwheelsv1/models/bike.dart';
import 'package:cached_network_image/cached_network_image.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool showOnlyMine = false;

  @override
  void initState() {
    super.initState();
  }

  Future<String?> _getUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        return doc.data()?['name'] ?? user.email; // fallback to email if name missing
      }
    } catch (e) {
      debugPrint('Error fetching user name: $e');
    }
    return user.email;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _bikesStream({String? ownerId}) {
    final col = FirebaseFirestore.instance.collection('bicycles');
    Query<Map<String, dynamic>> q = col.where('available', isEqualTo: true);
    if (ownerId != null && ownerId.isNotEmpty) {
      q = q.where('ownerId', isEqualTo: ownerId);
    }
    q = q.orderBy('createdAt', descending: true);
    return q.snapshots();
  }

  Widget _bikeCard(BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final images = (d['images'] ?? []) as List<dynamic>;
    final thumb = images.isNotEmpty ? images.first as String : '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () {
          // Navigate to details page for this bike
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BikeDetailsPage(bikeId: doc.id),
            ),
          );
        },
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
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BITSOnWheels'),
        actions: [
          // Add bike action
          IconButton(
            onPressed: () {
              Navigator.pushNamed(context, AddBikeScreen.routeName);
            },
            icon: const Icon(Icons.pedal_bike_outlined),
            tooltip: 'Add Bike',
          ),
          // Logout button
          IconButton(
            onPressed: () async {
              await AuthService().signOut();
              Navigator.pushReplacementNamed(context, '/login');
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: FutureBuilder<String?>(
        future: _getUserName(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final name = snapshot.data ?? 'User';

          return Column(
            children: [
              // Header: welcome + toggle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Welcome, $name', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    // Toggle All / My Listings
                    ToggleButtons(
                      isSelected: [!showOnlyMine, showOnlyMine],
                      onPressed: (index) {
                        setState(() {
                          showOnlyMine = index == 1;
                        });
                      },
                      children: const [
                        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('All')),
                        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('My Listings')),
                      ],
                    ),
                  ],
                ),
              ),

              // Buttons row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pushNamed(context, AddBikeScreen.routeName);
                        },
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Add Bicycle'),
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pushNamed(context, '/book_bike');
                        },
                        icon: const Icon(Icons.directions_bike_outlined),
                        label: const Text('Browse'),
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), backgroundColor: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Bike list (stream)
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _bikesStream(ownerId: showOnlyMine ? currentUid : null),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Text(showOnlyMine ? 'You have no listings yet.\nTap "Add Bicycle" to create one.' : 'No bicycles listed yet.'),
                      );
                    }

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (ctx, i) {
                        final doc = docs[i];
                        return _bikeCard(context, doc);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Simple page to show full bike details (fetches document by id).
/// This page shows Edit/Delete if the current user owns the bike, and
/// wires Edit -> AddBikeScreen (edit mode), Delete -> BikeService.deleteBike(...)
class BikeDetailsPage extends StatefulWidget {
  final String bikeId;
  const BikeDetailsPage({super.key, required this.bikeId});

  @override
  State<BikeDetailsPage> createState() => _BikeDetailsPageState();
}

class _BikeDetailsPageState extends State<BikeDetailsPage> {
  final BikeService _bikeService = BikeService();
  bool _loading = true;
  Map<String, dynamic>? _data;
  String? _error;
  bool _deleting = false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await FirebaseFirestore.instance.collection('bicycles').doc(widget.bikeId).get();
      if (!doc.exists) {
        setState(() {
          _error = 'Bike not found';
          _loading = false;
        });
        return;
      }
      setState(() {
        _data = doc.data();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _onDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete listing?'),
        content: const Text('Deleting this listing is permanent. Do you want to continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _deleting = true;
    });

    try {
      await _bikeService.deleteBike(bikeId: widget.bikeId, deleteImagesFromStorage: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bike deleted')));
      Navigator.of(context).pop(); // close details page
    } catch (e) {
      setState(() {
        _deleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bike details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bike details')),
        body: Center(child: Text('Error: $_error')),
      );
    }

    final d = _data ?? {};
    final images = (d['images'] ?? []) as List<dynamic>;
    final ownerId = (d['ownerId'] as String?) ?? '';
    final title = (d['title'] as String?) ?? 'Untitled';
    final desc = (d['description'] as String?) ?? '';
    final locationText = (d['locationText'] as String?) ?? '-';
    final hourlyRate = (d['hourlyRate'] is num) ? (d['hourlyRate'] as num).toDouble() : 0.0;
    final contact = (d['contactNumber'] as String?) ?? '';
    final ownerName = (d['ownerName'] as String?) ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (images.isNotEmpty)
                SizedBox(
                  height: 220,
                  width: double.infinity,
                  child: PageView.builder(
                    itemCount: images.length,
                    itemBuilder: (c, i) {
                      final url = images[i] as String;
                      return CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (c, u) => Container(color: Colors.grey[200]),
                        errorWidget: (c, u, e) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image)),
                      );
                    },
                  ),
                )
              else
                Container(
                  height: 220,
                  color: Colors.grey[200],
                  child: const Center(child: Icon(Icons.directions_bike, size: 72)),
                ),
              const SizedBox(height: 12),
              Text('Owner: $ownerName', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Location: $locationText'),
              const SizedBox(height: 6),
              Text('Rate: ₹${hourlyRate.toString()} / hour', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Text(desc),
              const SizedBox(height: 16),
              Text('Contact: $contact'),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        int hours = 1;
                        double rate = hourlyRate;
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
                                            bikeId: widget.bikeId,
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
              const SizedBox(height: 12),

              if (currentUid != null && ownerId == currentUid) ...[
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          // Open the AddBikeScreen in edit mode by passing a Bike model
                          final bikeModel = Bike(
                            id: widget.bikeId,
                            ownerId: ownerId,
                            ownerName: ownerName,
                            title: title,
                            description: desc,
                            locationText: locationText,
                            hourlyRate: hourlyRate,
                            images: images.map((e) => e as String).toList(),
                            contactNumber: contact,
                          );

                          final updatedId = await Navigator.push<String?>(
                            context,
                            MaterialPageRoute(builder: (_) => AddBikeScreen(bike: bikeModel)),
                          );

                          if (updatedId != null && updatedId.isNotEmpty) {
                            // reload details
                            await _load();
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bike updated')));
                          }
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: _deleting ? null : _onDelete,
                        icon: const Icon(Icons.delete),
                        label: _deleting ? const Text('Deleting...') : const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
