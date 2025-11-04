// lib/services/notification_service.dart
//
// NotificationService: wrapper around firebase_messaging + flutter_local_notifications,
// with helper methods to initialize, handle incoming messages, show local notifications,
// persist notifications to Firestore under users/{userId}/notifications, and manage FCM token.
//
// Usage:
//   await NotificationService.instance.init();
//   NotificationService.instance.setOnSelectNotificationCallback((payload) { ... });
//
// NOTE: Add these packages to your pubspec.yaml:
//   firebase_messaging: ^14.0.0
//   flutter_local_notifications: ^13.0.0
//   cloud_firestore: ^4.0.0
//   firebase_auth: ^4.0.0
//
// Adjust versions as needed for your project.
//
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

import '../models/notification_item.dart';

class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _fire = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Expose a stream for in-app notification events (useful for UI to react)
  final StreamController<NotificationItem> _onNotificationCtr = StreamController.broadcast();
  Stream<NotificationItem> get onNotificationReceived => _onNotificationCtr.stream;

  // Optional callback when user taps a local notification (payload is JSON string)
  void Function(NotificationResponse? response)? onSelectNotification;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 1) Setup flutter_local_notifications (platform-specific settings)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestAlertPermission: false,
    );

    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _local.initialize(initSettings, onDidReceiveNotificationResponse: (response) {
      // Called when user taps notification in system tray
      if (onSelectNotification != null) onSelectNotification!(response);
    });

    // 2) Request permissions for notifications (iOS/macOS)
    await _requestPermissions();

    // 3) Handle foreground messages: show local notification and persist
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleRemoteMessage(message, foreground: true);
    });

    // 4) Handle notification opened (app in background -> user taps notification)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleRemoteMessage(message, openedFromTray: true);
    });

    // 5) If the app was opened from a terminated state via notification
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      // give callers a chance to handle startup notification
      _handleRemoteMessage(initialMessage, openedFromTray: true);
    }

    // 6) Get & save FCM token for current user (if signed in)
    _fcm.getToken().then((token) async {
      if (token != null) {
        await _saveFcmTokenForCurrentUser(token);
      }
    });

    // 7) Listen to token refreshes
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      await _saveFcmTokenForCurrentUser(token);
    });
  }

  Future<void> _requestPermissions() async {
    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (kDebugMode) {
        print('FCM permission status: ${settings.authorizationStatus}');
      }
    } catch (e) {
      if (kDebugMode) print('Error requesting FCM permissions: $e');
    }
  }

  /// Handle incoming RemoteMessage. If [foreground] show local notification.
  /// If [openedFromTray] indicates user tapped the notification.
  Future<void> _handleRemoteMessage(RemoteMessage msg, {bool foreground = false, bool openedFromTray = false}) async {
    try {
      final data = msg.data;
      final notification = msg.notification;

      // Build a NotificationItem to persist
      final title = notification?.title ?? (data['title'] as String?) ?? 'Notification';
      final body = notification?.body ?? (data['body'] as String?) ?? '';
      final typeStr = (data['type'] as String?) ?? (data['notificationType'] as String?) ?? NotificationType.general.name;
      final metadataRaw = data['metadata'];

      Map<String, dynamic>? metadata;
      if (metadataRaw != null) {
        try {
          if (metadataRaw is String) {
            metadata = Map<String, dynamic>.from(jsonDecode(metadataRaw) as Map);
          } else if (metadataRaw is Map<String, dynamic>) {
            metadata = metadataRaw;
          } else {
            metadata = null;
          }
        } catch (_) {
          metadata = null;
        }
      }

      final now = Timestamp.now();
      final notifId = _fire.collection('notifications-temp').doc().id; // temp id; we'll write under user's subcollection

      final item = NotificationItem(
        id: notifId,
        title: title,
        body: body,
        type: _parseNotificationType(typeStr),
        metadata: metadata,
        read: false,
        createdAt: now,
      );

      // If foreground, display a local notification to the user
      if (foreground) {
        await _showLocalNotification(item, payload: jsonEncode({
          'notificationId': item.id,
          'metadata': item.metadata,
        }));
      }

      // Persist to Firestore under recipient's notifications subcollection if we can identify user
      // The message may include 'recipientId' in data; otherwise, persist to current user's notifications
      String? recipientId = data['recipientId'] as String?;
      if (recipientId == null) {
        final currentUser = _auth.currentUser;
        recipientId = currentUser?.uid;
      }

      if (recipientId != null) {
        final notifRef = _fire.collection('users').doc(recipientId).collection('notifications').doc();
        final toSave = NotificationItem(
          id: notifRef.id,
          title: item.title,
          body: item.body,
          type: item.type,
          metadata: item.metadata,
          read: false,
          createdAt: item.createdAt,
        );
        await notifRef.set(toSave.toMap());
        // emit event for in-app listeners
        _onNotificationCtr.add(toSave);
      } else {
        // no recipient (unlikely) -> optional: write to a central notifications collection for debugging
        if (kDebugMode) {
          await _fire.collection('notifications').doc().set(item.toMap());
        }
      }

      // If the notification caused the app to be opened (user tapped), call callback
      if (openedFromTray && onSelectNotification != null) {
        // payload with metadata helps navigate
        final payload = jsonEncode({
          'title': item.title,
          'body': item.body,
          'metadata': item.metadata,
        });
        final fakeResponse = NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          id: item.id.hashCode,
          actionId: null,
          input: null,
          payload: payload,
        );
        onSelectNotification!(fakeResponse);
      }
    } catch (e) {
      if (kDebugMode) print('Error handling remote message: $e');
    }
  }

  NotificationType _parseNotificationType(String? s) {
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

  /// Show a local system notification using flutter_local_notifications.
  /// Optionally persist to Firestore by specifying [persistForUserId].
  Future<void> _showLocalNotification(NotificationItem item, {String? payload}) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        'bitsonwheels_channel_01',
        'BitsOnWheels Notifications',
        channelDescription: 'General notifications for BitsOnWheels app',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
      );

      final iosDetails = DarwinNotificationDetails();

      final platform = NotificationDetails(android: androidDetails, iOS: iosDetails);

      await _local.show(
        item.id.hashCode,
        item.title,
        item.body,
        platform,
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) print('Error showing local notification: $e');
    }
  }

  /// Convenience method used by the app to send a local notification and persist it
  /// for the current user.
  ///
  /// Example: NotificationService.instance.showAndPersistLocalNotification(
  ///   title: 'Booking accepted',
  ///   body: 'Owner accepted your booking',
  ///   type: NotificationType.bookingAccepted,
  ///   metadata: {'bookingId': bookingId},
  /// );
  Future<void> showAndPersistLocalNotification({
    required String title,
    required String body,
    NotificationType type = NotificationType.general,
    Map<String, dynamic>? metadata,
    String? forUserId, // if null, uses current user
  }) async {
    final now = Timestamp.now();
    final currentUser = _auth.currentUser;
    final recipientId = forUserId ?? currentUser?.uid;

    final notifRef = (recipientId != null)
        ? _fire.collection('users').doc(recipientId).collection('notifications').doc()
        : _fire.collection('notifications').doc();

    final item = NotificationItem(
      id: notifRef.id,
      title: title,
      body: body,
      type: type,
      metadata: metadata,
      read: false,
      createdAt: now,
    );

    // Show system notification
    await _showLocalNotification(item, payload: jsonEncode({'notificationId': item.id, 'metadata': metadata}));

    // Persist to Firestore (if possible)
    try {
      await notifRef.set(item.toMap());
      if (recipientId != null) _onNotificationCtr.add(item);
    } catch (e) {
      if (kDebugMode) print('Failed to persist notification: $e');
    }
  }

  /// Show a local system notification without persisting to Firestore.
  /// Useful when the notification is already persisted elsewhere.
  Future<void> showLocalNotificationOnly({
    required String title,
    required String body,
    Map<String, dynamic>? metadata,
  }) async {
    final item = NotificationItem(
      id: '', // not used
      title: title,
      body: body,
      type: NotificationType.general,
      metadata: metadata,
      read: false,
      createdAt: Timestamp.now(),
    );
    await _showLocalNotification(item, payload: jsonEncode({'metadata': metadata}));
  }

  /// Show a booking request notification with Accept/Reject actions
  Future<void> showBookingRequestNotification({
    required String title,
    required String body,
    required String bookingId,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'bitsonwheels_channel_01',
      'BitsOnWheels Notifications',
      channelDescription: 'General notifications for BitsOnWheels app',
      importance: Importance.max,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('accept_$bookingId', 'Accept'),
        AndroidNotificationAction('reject_$bookingId', 'Reject'),
      ],
    );

    final iosDetails = DarwinNotificationDetails();

    final platform = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _local.show(
      bookingId.hashCode,
      title,
      body,
      platform,
      payload: 'booking_request_$bookingId',
    );
  }

  /// Saves the FCM token to the current user's profile under users/{uid}/fcmTokens/{token}
  /// so other systems (cloud functions) can send direct pushes to that token.
  Future<void> _saveFcmTokenForCurrentUser(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final tokenRef = _fire.collection('users').doc(user.uid).collection('fcmTokens').doc(token);
    await tokenRef.set({
      'token': token,
      'createdAt': Timestamp.now(),
      'platform': defaultTargetPlatform.toString(),
    });
  }

  /// Public method to programmatically retrieve the current FCM token.
  Future<String?> getFcmToken() => _fcm.getToken();

  /// Optional helper to subscribe to an FCM topic
  Future<void> subscribeToTopic(String topic) => _fcm.subscribeToTopic(topic);

  /// Optional helper to unsubscribe from an FCM topic
  Future<void> unsubscribeFromTopic(String topic) => _fcm.unsubscribeFromTopic(topic);

  /// Allow app to provide handler for notification taps (from local notifications)
  void setOnSelectNotificationCallback(void Function(NotificationResponse? response)? cb) {
    onSelectNotification = cb;
  }

  /// Mark a notification as read for a given user/notificationId
  Future<void> markNotificationRead({required String userId, required String notificationId}) async {
    final ref = _fire.collection('users').doc(userId).collection('notifications').doc(notificationId);
    await ref.update({'read': true});
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _onNotificationCtr.close();
    // flutter_local_notifications doesn't require dispose; firebase_messaging neither.
  }
}
