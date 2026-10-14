import * as admin from 'firebase-admin';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { validateAndNormalizePayload, ValidatedRestroomData } from './validation';

export interface SubmitRestroomResponse {
  success: boolean;
  restroom: Record<string, unknown>;
  isIdempotentRetry: boolean;
}

/**
 * Builds the sanitized public Firestore document payload.
 * Strictly excludes any contributor UID or private metadata.
 */
export function buildPublicRestroomDocument(
  data: ValidatedRestroomData,
  timestamp: admin.firestore.Timestamp
): Record<string, unknown> {
  const doc: Record<string, unknown> = {
    id: data.restroomId,
    name: data.name,
    latitude: data.latitude,
    longitude: data.longitude,
    geohash: data.geohash,
    accessType: data.accessType,

    averageRating: 0.0,
    ratingCount: 0,
    verificationCount: 0,
    negativeVerificationCount: 0,
    lastVerifiedAt: null,
    status: 'unverified',
    createdAt: timestamp,
    updatedAt: timestamp,
  };

  if (data.countryCode !== null) doc.countryCode = data.countryCode;
  if (data.region !== null) doc.region = data.region;
  if (data.city !== null) doc.city = data.city;
  if (data.buildingName !== null) doc.buildingName = data.buildingName;
  if (data.buildingSection !== null) doc.buildingSection = data.buildingSection;
  if (data.floor !== null) doc.floor = data.floor;
  if (data.unitOrArea !== null) doc.unitOrArea = data.unitOrArea;
  if (data.landmark !== null) doc.landmark = data.landmark;
  if (data.directionsNote !== null) doc.directionsNote = data.directionsNote;
  if (data.accessInstructions !== null) doc.accessInstructions = data.accessInstructions;

  if (data.accessType === 'paid') {
    doc.feeAmount = data.feeAmount;
    doc.feeCurrency = data.feeCurrency;
  }

  doc.male = data.male;
  doc.female = data.female;
  doc.allGender = data.allGender;

  doc.pwdAccessible = data.pwdAccessible;
  doc.babyChanging = data.babyChanging;
  doc.hasBidet = data.hasBidet;
  doc.hasToiletPaper = data.hasToiletPaper;
  doc.hasSoap = data.hasSoap;
  doc.hasHandDryer = data.hasHandDryer;

  return doc;
}

/**
 * Core transactional submission logic.
 * Bounded by OCC transaction on /contributionRateLimits/{uid}.
 */
export async function executeSubmitRestroom(
  db: admin.firestore.Firestore,
  uid: string,
  data: unknown,
  customNowMs?: number
): Promise<SubmitRestroomResponse> {
  const validated = validateAndNormalizePayload(data);

  const nowMs = customNowMs ?? Date.now();
  const now = admin.firestore.Timestamp.fromMillis(nowMs);

  return await db.runTransaction(async (transaction) => {
    const publicRef = db.collection('restrooms').doc(validated.restroomId);
    const privateRef = db.collection('contributions').doc(`restroom_${validated.restroomId}`);
    const rateLimitRef = db.collection('contributionRateLimits').doc(uid);

    // 1. Check existing public restroom document (Idempotency & Collision check)
    const publicSnap = await transaction.get(publicRef);
    if (publicSnap.exists) {
      const privateSnap = await transaction.get(privateRef);
      if (privateSnap.exists && privateSnap.data()?.userUid === uid) {
        // Idempotent retry of existing contribution: return existing record without charging rate limits
        return {
          success: true,
          restroom: publicSnap.data() as Record<string, unknown>,
          isIdempotentRetry: true,
        };
      }
      throw new HttpsError(
        'already-exists',
        'A restroom with this ID already exists or is owned by another contributor.'
      );
    }

    // 2. Read rate-limit document for authenticated user
    const rateLimitSnap = await transaction.get(rateLimitRef);
    const existingTimestamps: admin.firestore.Timestamp[] = rateLimitSnap.exists
      ? rateLimitSnap.data()?.submissionTimestamps || []
      : [];

    // Filter valid timestamps within rolling windows
    const valid24h = existingTimestamps.filter(
      (t) => nowMs - t.toMillis() < 24 * 60 * 60 * 1000
    );
    const valid10m = valid24h.filter(
      (t) => nowMs - t.toMillis() < 10 * 60 * 1000
    );

    // Enforce locked rate-limit constraints:
    // - Max 10 per 24 hours
    // - Max 3 per 10 minutes
    if (valid24h.length >= 10) {
      throw new HttpsError(
        'resource-exhausted',
        'Daily submission limit reached. You may submit up to 10 restrooms per 24 hours.'
      );
    }
    if (valid10m.length >= 3) {
      throw new HttpsError(
        'resource-exhausted',
        'Burst submission limit reached. Please wait a few minutes before submitting another restroom.'
      );
    }

    // 3. Construct atomic documents
    const publicPayload = buildPublicRestroomDocument(validated, now);
    const privatePayload = {
      id: `restroom_${validated.restroomId}`,
      contributionType: 'restroom',
      resourceId: validated.restroomId,
      restroomId: validated.restroomId,
      userUid: uid,
      moderationState: 'pending',
      createdAt: now,
      updatedAt: now,
    };
    const updatedTimestamps = [...valid24h, now];

    // 4. Atomic writes
    transaction.set(publicRef, publicPayload);
    transaction.set(privateRef, privatePayload);
    transaction.set(rateLimitRef, {
      userUid: uid,
      submissionTimestamps: updatedTimestamps,
      updatedAt: now,
    });

    return {
      success: true,
      restroom: publicPayload,
      isIdempotentRetry: false,
    };
  });
}

/**
 * Cloud Functions V2 HTTPS Callable endpoint.
 */
export const submitRestroom = onCall(
  {
    enforceAppCheck: false, // Default false in local tests; enforced via environment in staging/production
  },
  async (request: CallableRequest<unknown>): Promise<SubmitRestroomResponse> => {
    // 1. Authenticate caller
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated anonymously.');
    }
    const uid = request.auth.uid;

    // 2. Validate App Check if configured
    if (process.env.ENFORCE_APP_CHECK === 'true' && !request.app) {
      throw new HttpsError('failed-precondition', 'App Check verification failed.');
    }

    const db = admin.firestore();
    return await executeSubmitRestroom(db, uid, request.data);
  }
);
