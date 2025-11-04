import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';

admin.initializeApp();

const db = admin.firestore();
const fcm = admin.messaging();

/**
 * Helper: send notification to a user (persist to users/{uid}/notifications and send FCM to all tokens)
 */
async function sendNotificationToUser(userId: string, title: string, body: string, data?: { [k: string]: any }) {
  if (!userId) return;

  const now = admin.firestore.FieldValue.serverTimestamp();

  // Persist notification doc under user's notifications subcollection
  try {
    const notifRef = db.collection('users').doc(userId).collection('notifications').doc();
    const notifDoc = {
      title,
      body,
      type: (data && data.type) ? data.type : 'general',
      metadata: data ?? {},
      read: false,
      createdAt: now,
    };
    await notifRef.set(notifDoc);
  } catch (e) {
    console.error('Failed to persist notification doc for user', userId, e);
  }

  // Gather FCM tokens for the user (assumes tokens stored at users/{uid}/fcmTokens/{token})
  try {
    const tokensSnap = await db.collection('users').doc(userId).collection('fcmTokens').get();
    const tokens: string[] = [];
    tokensSnap.forEach(t => {
      const doc = t.data();
      if (doc && doc.token) tokens.push(doc.token as string);
    });

    if (tokens.length === 0) return;

    const payload: admin.messaging.MulticastMessage = {
      notification: { title, body },
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
      data: Object.fromEntries(
        Object.entries(data ?? {}).map(([k, v]) => [k, typeof v === 'string' ? v : JSON.stringify(v)])
      ),
      tokens,
    };

    const resp = await fcm.sendMulticast(payload);
    if (resp.failureCount > 0) {
      // Remove invalid tokens where possible
      const toRemove: Promise<any>[] = [];
      resp.responses.forEach((r, i) => {
        if (!r.success) {
          const err = r.error;
          if (err && (err.code === 'messaging/registration-token-not-registered' || err.code === 'messaging/invalid-registration-token')) {
            // Delete token doc
            const badToken = tokens[i];
            toRemove.push(
              db.collectionGroup('fcmTokens').where('token', '==', badToken).get().then(snap => {
                const batch = db.batch();
                snap.forEach(doc => batch.delete(doc.ref));
                return batch.commit();
              }).catch(err => console.warn('Failed to remove invalid token', badToken, err))
            );
          }
        }
      });
      await Promise.all(toRemove);
    }
  } catch (e) {
    console.error('Failed to send FCM to user', userId, e);
  }
}

/**
 * Firestore trigger: on booking created -> notify owner
 */
export const onBookingCreated = functions.firestore
  .document('bookings/{bookingId}')
  .onCreate(async (snap, ctx) => {
    try {
      const data = snap.data();
      if (!data) return;
      const bookingId = ctx.params.bookingId as string;
      const bikeId = data.bikeId as string;
      const renterId = data.renterId as string;
      const bikeSnap = await db.collection('bicycles').doc(bikeId).get();

      if (!bikeSnap.exists) {
        console.warn('Booking created for missing bike', bikeId, bookingId);
        return;
      }

      const bike = bikeSnap.data()!;
      const ownerId = bike.ownerId as string;

      // Persist a server-side notification and send push to owner
      const title = 'New booking request';
      const body = `${(data.renterName || 'Someone')} requested ${data.hoursRequested || 'a'} hour(s) for your bike "${bike.title || ''}".`;
      const metadata = { bookingId, bikeId, renterId };

      await sendNotificationToUser(ownerId, title, body, { ...metadata, type: 'bookingRequest' });

      console.log(`Notified owner ${ownerId} about booking ${bookingId}`);
    } catch (e) {
      console.error('Error in onBookingCreated', e);
    }
  });

/**
 * Firestore trigger: on booking updated -> react to status changes
 *
 * Behaviors:
 *  - If status transitions to 'accepted' (or 'active'), ensure acceptedAt/startsAt/endsAt exist, compute endsAt from hoursRequested if needed,
 *    and atomically set bike.isBooked = true and bike.currentBookingId = bookingId (transaction).
 *  - If status transitions to 'rejected', notify renter.
 *  - If status transitions to 'finished', clear bike.isBooked if it matches this booking and notify both parties.
 */
export const onBookingUpdated = functions.firestore
  .document('bookings/{bookingId}')
  .onUpdate(async (change, ctx) => {
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return;
    const bookingId = ctx.params.bookingId as string;

    const oldStatus = (before.status as string) || '';
    const newStatus = (after.status as string) || '';

    // If status didn't change, nothing to do
    if (oldStatus === newStatus) return;

    const bikeId = after.bikeId as string;
    const renterId = after.renterId as string;
    const ownerId = after.bikeOwnerId as string || (await db.collection('bicycles').doc(bikeId).get()).data()?.ownerId;

    console.log(`Booking ${bookingId} status changed: ${oldStatus} -> ${newStatus}`);

    try {
      if (newStatus === 'accepted' || newStatus === 'active') {
        // We need to ensure acceptedAt/startsAt/endsAt exist and atomically mark bike as booked
        await db.runTransaction(async (txn) => {
          const bookingRef = db.collection('bookings').doc(bookingId);
          const bikeRef = db.collection('bicycles').doc(bikeId);

          const bikeSnap = await txn.get(bikeRef);
          if (!bikeSnap.exists) throw new Error('Bike not found');

          const bikeData = bikeSnap.data()!;
          const isBooked = bikeData.isBooked === true;
          if (isBooked) {
            // If bike already booked by someone else and currentBookingId != bookingId -> abort
            const currentBkg = bikeData.currentBookingId as string | undefined;
            if (currentBkg != null && currentBkg !== bookingId) {
              throw new Error(`Bike ${bikeId} already booked by ${currentBkg}`);
            }
            // If currentBookingId equals this booking, proceed to ensure timestamps
          }

          // Ensure booking doc timestamps
          const bookingSnap = await txn.get(bookingRef);
          if (!bookingSnap.exists) throw new Error('Booking disappeared');
          const bookingData = bookingSnap.data()!;

          const now = admin.firestore.Timestamp.now();

          const hoursRequested = (bookingData.hoursRequested as number) || 0;

          let acceptedAt = bookingData.acceptedAt as admin.firestore.Timestamp | undefined;
          let startsAt = bookingData.startsAt as admin.firestore.Timestamp | undefined;
          let endsAt = bookingData.endsAt as admin.firestore.Timestamp | undefined;

          if (!acceptedAt) acceptedAt = now;
          if (!startsAt) startsAt = now;
          if (!endsAt) {
            // compute endsAt from startsAt + hoursRequested
            const endsAtDate = new Date(startsAt.toDate().getTime() + (hoursRequested * 60 * 60 * 1000));
            endsAt = admin.firestore.Timestamp.fromDate(endsAtDate);
          }

          // Update booking timestamps/status
          txn.update(bookingRef, {
            status: newStatus,
            acceptedAt: acceptedAt,
            startsAt: startsAt,
            endsAt: endsAt,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          // Update bike: set isBooked and currentBookingId
          txn.update(bikeRef, {
            isBooked: true,
            currentBookingId: bookingId,
            bookingStatus: 'booked',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        });

        // After transaction, notify renter that booking was accepted / started
        if (newStatus === 'accepted') {
          await sendNotificationToUser(renterId,
            'Booking accepted',
            'Your booking request has been accepted by the owner.',
            { bookingId, bikeId, type: 'bookingAccepted' });
        } else if (newStatus === 'active') {
          await sendNotificationToUser(renterId,
            'Booking started',
            'Your booking has started. Enjoy your ride!',
            { bookingId, bikeId, type: 'bookingStarted' });
        }
      } else if (newStatus === 'rejected') {
        // Notify renter about rejection
        await sendNotificationToUser(renterId,
          'Booking rejected',
          after.rejectionReason || 'Your booking request was rejected by the owner.',
          { bookingId, bikeId, type: 'bookingRejected' });
      } else if (newStatus === 'finished') {
        // When booking finished, clear bike.isBooked if it points to this booking
        await db.runTransaction(async (txn) => {
          const bikeRef = db.collection('bicycles').doc(bikeId);
          const bikeSnap = await txn.get(bikeRef);
          if (!bikeSnap.exists) return;
          const bikeData = bikeSnap.data()!;
          const currentBookingId = bikeData.currentBookingId as string | undefined;
          if (currentBookingId === bookingId) {
            txn.update(bikeRef, {
              isBooked: false,
              currentBookingId: admin.firestore.FieldValue.delete(),
              bookingStatus: 'available',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          // Also ensure booking document has endsAt & updated time
          const bookingRef = db.collection('bookings').doc(bookingId);
          const bookingSnap = await txn.get(bookingRef);
          if (bookingSnap.exists) {
            const bData = bookingSnap.data()!;
            if (!bData.endsAt) {
              txn.update(bookingRef, {
                endsAt: admin.firestore.Timestamp.now(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });
            }
          }
        });

        // Notify both parties
        await Promise.all([
          sendNotificationToUser(renterId,
            'Ride finished',
            'Your ride has finished. Please return the bike to the owner.',
            { bookingId, bikeId, type: 'bookingEnded' }),
          sendNotificationToUser(ownerId,
            'Ride finished',
            'A ride has finished for your bike.',
            { bookingId, bikeId, type: 'bookingEnded' }),
        ]);
      }
    } catch (e) {
      console.error('Error reacting to booking update', bookingId, e);
    }
  });

/**
 * Scheduled job: find bookings that have ended (endsAt <= now) and are still active/accepted and finish them.
 * Runs every minute. You can tune schedule as needed.
 */
export const scheduledFinishBookings = functions.pubsub
  .schedule('every 1 minutes')
  .onRun(async (ctx) => {
    const now = admin.firestore.Timestamp.now();
    console.log('scheduledFinishBookings tick at', now.toDate().toISOString());

    try {
      // Find bookings with status in ['active','accepted'] and endsAt <= now
      const q = db.collection('bookings')
        .where('status', 'in', ['active', 'accepted'])
        .where('endsAt', '<=', now)
        .limit(50); // batch size - tune as needed

      const snap = await q.get();
      if (snap.empty) {
        console.log('No expired bookings found this run.');
        return null;
      }

      const batchOps: Promise<any>[] = [];

      for (const doc of snap.docs) {
        const bookingId = doc.id;
        const b = doc.data();
        const bikeId = b.bikeId as string;
        const renterId = b.renterId as string;
        const ownerId = b.bikeOwnerId as string;

        console.log(`Auto-finishing booking ${bookingId} for bike ${bikeId}`);

        // Transactionally set booking.status = 'finished' and clear bike booking if appropriate
        const p = db.runTransaction(async (txn) => {
          const bookingRef = db.collection('bookings').doc(bookingId);
          const bikeRef = db.collection('bicycles').doc(bikeId);

          const bookingSnap = await txn.get(bookingRef);
          if (!bookingSnap.exists) return;

          const bookingData = bookingSnap.data()!;
          const currentStatus = bookingData.status as string;
          if (currentStatus === 'finished') return;

          txn.update(bookingRef, {
            status: 'finished',
            endsAt: bookingData.endsAt || admin.firestore.Timestamp.now(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          const bikeSnap = await txn.get(bikeRef);
          if (bikeSnap.exists) {
            const bikeData = bikeSnap.data()!;
            const currentBookingId = bikeData.currentBookingId as string | undefined;
            if (currentBookingId === bookingId) {
              txn.update(bikeRef, {
                isBooked: false,
                currentBookingId: admin.firestore.FieldValue.delete(),
                bookingStatus: 'available',
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });
            }
          }
        }).then(async () => {
          // Send notifications after transaction success
          await Promise.all([
            sendNotificationToUser(renterId,
              'Ride finished',
              'Your booked period has ended. Please return the bike to the owner.',
              { bookingId, bikeId, type: 'bookingEnded' }),
            sendNotificationToUser(ownerId,
              'Ride finished',
              'A booked period has ended for your bike.',
              { bookingId, bikeId, type: 'bookingEnded' }),
          ]);
        }).catch(err => {
          console.error('Error auto-finishing booking', bookingId, err);
        });

        batchOps.push(p);
      }

      await Promise.all(batchOps);
    } catch (e) {
      console.error('Error in scheduledFinishBookings', e);
    }

    return null;
  });
