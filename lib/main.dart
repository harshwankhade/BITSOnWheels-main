import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:bitsonwheelsv1/screens/home_screen.dart';
import 'package:bitsonwheelsv1/screens/login_screen.dart';
import 'package:bitsonwheelsv1/screens/signup_screen.dart';
import 'package:bitsonwheelsv1/screens/verify_email_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/add_bike_screen.dart';
import 'package:bitsonwheelsv1/screens/bike_details_screen.dart';
import 'package:bitsonwheelsv1/services/notification_service.dart';
import 'package:bitsonwheelsv1/services/review_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BITSOnWheels',
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const Root(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/verify': (context) => const VerifyEmailScreen(),
        '/home': (context) => const HomeScreen(),
        '/add_bike': (context) => const AddBikeScreen(),
        BookBikeScreen.routeName: (context) => const BookBikeScreen(),
      },
    );
  }
}

/// Custom dialog widget with countdown timer for booking acceptance
class _AcceptanceTimerDialog extends StatefulWidget {
  final String title;
  final String body;
  final int timerDurationSeconds;
  final String bookingId;

  const _AcceptanceTimerDialog({
    required this.title,
    required this.body,
    required this.timerDurationSeconds,
    required this.bookingId,
  });

  @override
  State<_AcceptanceTimerDialog> createState() => _AcceptanceTimerDialogState();
}

class _AcceptanceTimerDialogState extends State<_AcceptanceTimerDialog> {
  late int remainingSeconds;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    remainingSeconds = widget.timerDurationSeconds;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        remainingSeconds--;
        if (remainingSeconds <= 0) {
          _timer.cancel();
          // Show rating dialog when timer expires
          if (mounted) {
            Navigator.of(context).pop();
            _showRatingDialog();
          }
        }
      });
    });
  }

  void _showRatingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _RatingDialog(
        bookingId: widget.bookingId,
      ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = remainingSeconds / widget.timerDurationSeconds;
    
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.body, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 24),
          // Circular progress indicator with timer
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    remainingSeconds > 10 ? Colors.green : Colors.orange,
                  ),
                  backgroundColor: Colors.grey[300],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(remainingSeconds),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const Text(
                    'Timer',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${widget.timerDurationSeconds} seconds total',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
      backgroundColor: Colors.green.withOpacity(0.05),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
    );
  }
}

/// Rating dialog shown when booking is completed
class _RatingDialog extends StatefulWidget {
  final String bookingId;

  const _RatingDialog({required this.bookingId});

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  double _rating = 0;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submitRating() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Fetch booking details
      final bookingDoc = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .get();

      if (!bookingDoc.exists) {
        throw Exception('Booking not found');
      }

      final bookingData = bookingDoc.data()!;
      final bikeId = bookingData['bikeId'] as String;
      final ownerId = bookingData['ownerId'] as String;

      // Submit review
      final reviewService = ReviewService();
      await reviewService.submitReview(
        bikeId: bikeId,
        ownerId: ownerId,
        bookingId: widget.bookingId,
        rating: _rating,
        comment: _commentController.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thank you for your rating!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting rating: $e')),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Row(
        children: [
          Icon(Icons.star, color: Colors.amber, size: 28),
          SizedBox(width: 12),
          Text('Booking Finished! 🎉', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'How was your experience?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 20),
            // Star rating
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return GestureDetector(
                  onTap: () {
                    setState(() => _rating = (index + 1).toDouble());
                  },
                  child: Icon(
                    Icons.star,
                    size: 40,
                    color: index < _rating ? Colors.amber : Colors.grey[300],
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            Text(
              _rating > 0 ? '${_rating.toInt()} out of 5 stars' : 'Select a rating',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 20),
            // Comment field
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add a comment (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Skip'),
        ),
        ElevatedButton.icon(
          onPressed: _isSubmitting ? null : _submitRating,
          icon: _isSubmitting ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ) : const Icon(Icons.check),
          label: Text(_isSubmitting ? 'Submitting...' : 'Submit Rating'),
        ),
      ],
    );
  }
}

class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  StreamSubscription<QuerySnapshot>? _notificationSubscription;
  DateTime? _appStartTime;

  @override
  void initState() {
    super.initState();
    // Record when app started to filter old notifications
    _appStartTime = DateTime.now();
    NotificationService.instance.setOnSelectNotificationCallback(_onNotificationResponse);
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _setupNotificationListener();
      } else {
        _notificationSubscription?.cancel();
        _notificationSubscription = null;
      }
    });
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  void _setupNotificationListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _notificationSubscription?.cancel();
      _notificationSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .snapshots()
          .listen((snapshot) {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final data = change.doc.data();
            if (data != null) {
              // Only show notifications created after app started
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
              if (createdAt != null && createdAt.isBefore(_appStartTime!)) {
                print('⏭️  Skipping old notification created at $createdAt');
                continue;
              }
              
              final title = data['title'] as String? ?? 'Notification';
              final body = data['body'] as String? ?? '';
              final type = data['type'] as String?;
              final metadata = data['metadata'] as Map<String, dynamic>?;
              
              print('📢 New notification received: type=$type, title=$title');
              
              if (type == 'bookingRequest' && metadata != null && metadata['bookingId'] != null) {
                final bookingId = metadata['bookingId'] as String;
                // Show dialog for booking request
                _showBookingRequestDialog(title, body, bookingId);
                // Also show notification
                NotificationService.instance.showBookingRequestNotification(
                  title: title,
                  body: body,
                  bookingId: bookingId,
                );
              } else if (type == 'bookingAccepted') {
                // Show auto-closing dialog for booking accepted with timer
                final bookingId = metadata?['bookingId'] as String?;
                if (bookingId != null) {
                  _showAcceptanceDialogWithTimer(title, body, bookingId);
                } else {
                  _showAutoClosingDialog(title, body, Colors.green);
                }
              } else if (type == 'bookingRejected') {
                // Show auto-closing dialog for booking rejected
                _showAutoClosingDialog(title, body, Colors.red);
              } else {
                // Show regular notification for all other types
                NotificationService.instance.showLocalNotificationOnly(
                  title: title,
                  body: body,
                  metadata: metadata,
                );
              }
            }
          }
        }
      });
    }
  }

  void _showAutoClosingDialog(String title, String body, Color accentColor) {
    if (!mounted) return;
    
    // Show the dialog
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(
              accentColor == Colors.green ? Icons.check_circle : Icons.cancel,
              color: accentColor,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        content: Text(body, style: const TextStyle(fontSize: 15)),
        backgroundColor: accentColor.withOpacity(0.05),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      ),
    );
    
    // Auto-close after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
    });
  }

  void _showAcceptanceDialogWithTimer(String title, String body, String bookingId) {
    if (!mounted) return;

    // Fetch booking details to get duration
    FirebaseFirestore.instance.collection('bookings').doc(bookingId).get().then((doc) {
      if (!mounted) return;
      
      final booking = doc.data();
      if (booking == null) {
        _showAutoClosingDialog(title, body, Colors.green);
        return;
      }

      final startTime = (booking['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
      final endTime = (booking['endTime'] as Timestamp?)?.toDate() ?? DateTime.now();
      final durationInHours = endTime.difference(startTime).inHours;
      final timerDurationSeconds = durationInHours * 10;

      // Create a stateful dialog with timer
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => _AcceptanceTimerDialog(
          title: title,
          body: body,
          timerDurationSeconds: timerDurationSeconds,
          bookingId: bookingId,
        ),
      );

      // Auto-close after timer completes
      Future.delayed(Duration(seconds: timerDurationSeconds), () {
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
      });
    });
  }

  void _showBookingRequestDialog(String title, String body, String bookingId) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(body),
              const SizedBox(height: 16),
              // Show additional booking details
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('bookings').doc(bookingId).get(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  
                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const SizedBox.shrink();
                  }
                  
                  final booking = snapshot.data!.data() as Map<String, dynamic>;
                  final startTime = (booking['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
                  final endTime = (booking['endTime'] as Timestamp?)?.toDate() ?? DateTime.now();
                  final price = booking['price'] ?? 0;
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Booking Details',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            _buildDetailRow('Start:', _formatDateTime(startTime)),
                            _buildDetailRow('End:', _formatDateTime(endTime)),
                            _buildDetailRow('Duration:', _calculateDuration(startTime, endTime)),
                            _buildDetailRow('Price:', '₹${price.toStringAsFixed(2)}'),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _rejectBooking(bookingId);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reject', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _acceptBooking(bookingId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Accept', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _calculateDuration(DateTime start, DateTime end) {
    final duration = end.difference(start);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours == 0) {
      return '$minutes minutes';
    }
    return minutes == 0 ? '$hours hours' : '$hours hrs $minutes mins';
  }

  void _onNotificationResponse(NotificationResponse? response) {
    if (response == null) return;
    final actionId = response.actionId;
    if (actionId != null) {
      if (actionId.startsWith('accept_')) {
        final bookingId = actionId.substring('accept_'.length);
        _acceptBooking(bookingId);
      } else if (actionId.startsWith('reject_')) {
        final bookingId = actionId.substring('reject_'.length);
        _rejectBooking(bookingId);
      }
    }
    // Handle normal tap if needed
  }

  Future<void> _acceptBooking(String bookingId) async {
    try {
      print('✅ Accepting booking: $bookingId');
      
      // Update booking status
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // Get booking details
      final booking = await FirebaseFirestore.instance.collection('bookings').doc(bookingId).get();
      if (booking.exists) {
        final data = booking.data()!;
        final renterId = data['renterId'];
        final bikeId = data['bikeId'];
        
        // Get bike details for better notification
        String bikeTitle = 'your bike';
        try {
          final bikeDoc = await FirebaseFirestore.instance.collection('bicycles').doc(bikeId).get();
          if (bikeDoc.exists) {
            bikeTitle = bikeDoc.data()?['title'] ?? 'your bike';
          }
        } catch (e) {
          print('Error fetching bike details: $e');
        }
        
        // Send notification to renter
        await FirebaseFirestore.instance.collection('users').doc(renterId).collection('notifications').add({
          'title': 'Booking Accepted! 🎉',
          'body': 'Your booking for "$bikeTitle" has been confirmed by the owner!',
          'type': 'bookingAccepted',
          'metadata': {'bookingId': bookingId, 'bikeId': bikeId},
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        print('✅ Notification sent to renter: $renterId');
      }
    } catch (e) {
      print('❌ Error accepting booking: $e');
    }
  }

  Future<void> _rejectBooking(String bookingId) async {
    try {
      print('❌ Rejecting booking: $bookingId');
      
      // Update booking status
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // Get booking details
      final booking = await FirebaseFirestore.instance.collection('bookings').doc(bookingId).get();
      if (booking.exists) {
        final data = booking.data()!;
        final renterId = data['renterId'];
        final bikeId = data['bikeId'];
        
        // Get bike details for better notification
        String bikeTitle = 'the bike';
        try {
          final bikeDoc = await FirebaseFirestore.instance.collection('bicycles').doc(bikeId).get();
          if (bikeDoc.exists) {
            bikeTitle = bikeDoc.data()?['title'] ?? 'the bike';
          }
        } catch (e) {
          print('Error fetching bike details: $e');
        }
        
        // Send notification to renter
        await FirebaseFirestore.instance.collection('users').doc(renterId).collection('notifications').add({
          'title': 'Booking Declined',
          'body': 'Your booking request for "$bikeTitle" was declined by the owner.',
          'type': 'bookingRejected',
          'metadata': {'bookingId': bookingId, 'bikeId': bikeId},
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        print('📧 Notification sent to renter: $renterId');
      }
    } catch (e) {
      print('❌ Error rejecting booking: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        } else {
          if (!user.emailVerified) return const VerifyEmailScreen();
          return const HomeScreen();
        }
      },
    );
  }
}