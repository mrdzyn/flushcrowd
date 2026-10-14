import { describe, it, before, after, beforeEach } from 'node:test';
import * as assert from 'node:assert/strict';
import * as admin from 'firebase-admin';
import { executeSubmitRestroom, submitRestroom } from '../src/submit_restroom';
import { HttpsError } from 'firebase-functions/v2/https';
import { initializeTestEnvironment, assertFails } from '@firebase/rules-unit-testing';

// Ensure Firebase Admin is connected to Firestore emulator
const PROJECT_ID = 'flushcrowd-p26-test';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = PROJECT_ID;

if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();

function getSamplePayload(restroomId: string, name = 'Ayala Malls Restroom') {
  return {
    restroomId,
    name,
    latitude: 14.552,
    longitude: 121.0205,
    accessType: 'free' as const,
    geohash: 'wdw4cc',
    buildingName: 'Ayala Malls Glorietta',
    floor: '2F',
    male: true,
    female: true,
    allGender: null,
    pwdAccessible: true,
    hasBidet: true,
    hasToiletPaper: true,
  };
}

async function clearCollections() {
  const collections = ['restrooms', 'contributions', 'contributionRateLimits'];
  for (const col of collections) {
    const snap = await db.collection(col).get();
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
}

describe('P2.6-C — Comprehensive Emulator Test Suite for Rate Limiting & Abuse Prevention', () => {
  before(async () => {
    await clearCollections();
  });

  beforeEach(async () => {
    await clearCollections();
  });

  after(async () => {
    await clearCollections();
  });

  // Scenario 1: Initial Submission
  it('Scenario 1: Initial Submission writes public restroom, private contribution, and initializes rate limit doc', async () => {
    const uid = 'uid_alice_101';
    const payload = getSamplePayload('rr_test_001');

    const res = await executeSubmitRestroom(db, uid, payload);
    assert.equal(res.success, true);
    assert.equal(res.isIdempotentRetry, false);

    // Verify public restroom
    const publicDoc = await db.collection('restrooms').doc('rr_test_001').get();
    assert.equal(publicDoc.exists, true);
    const pubData = publicDoc.data()!;
    assert.equal(pubData.id, 'rr_test_001');
    assert.equal(pubData.name, 'Ayala Malls Restroom');
    assert.equal(pubData.status, 'unverified');
    assert.equal(pubData.averageRating, 0.0);
    assert.equal(pubData.ratingCount, 0);
    assert.equal(pubData.geohash, 'wdw4cc');
    // Ensure strict privacy: no userUid or createdByUid in public doc
    assert.equal(pubData.userUid, undefined);
    assert.equal(pubData.createdByUid, undefined);

    // Verify private contribution
    const privDoc = await db.collection('contributions').doc('restroom_rr_test_001').get();
    assert.equal(privDoc.exists, true);
    const privData = privDoc.data()!;
    assert.equal(privData.userUid, uid);
    assert.equal(privData.resourceId, 'rr_test_001');
    assert.equal(privData.moderationState, 'pending');

    // Verify rate limit doc
    const rateDoc = await db.collection('contributionRateLimits').doc(uid).get();
    assert.equal(rateDoc.exists, true);
    const rateData = rateDoc.data()!;
    assert.equal(rateData.userUid, uid);
    assert.equal(rateData.submissionTimestamps.length, 1);
  });

  // Scenario 2: Rolling 10-Minute Burst Limit
  it('Scenario 2: Rolling 10-Minute Burst Limit allows 3 submissions and rejects 4th with resource-exhausted', async () => {
    const uid = 'uid_bob_burst';
    const baseTime = Date.now();

    // 1st submit
    const res1 = await executeSubmitRestroom(db, uid, getSamplePayload('rr_b1'), baseTime);
    assert.equal(res1.success, true);

    // 2nd submit (1 min later)
    const res2 = await executeSubmitRestroom(db, uid, getSamplePayload('rr_b2'), baseTime + 60 * 1000);
    assert.equal(res2.success, true);

    // 3rd submit (2 mins later)
    const res3 = await executeSubmitRestroom(db, uid, getSamplePayload('rr_b3'), baseTime + 120 * 1000);
    assert.equal(res3.success, true);

    // 4th submit (3 mins later - within 10 min window) -> Must be rejected!
    await assert.rejects(
      async () => {
        await executeSubmitRestroom(db, uid, getSamplePayload('rr_b4'), baseTime + 180 * 1000);
      },
      (err: unknown) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, 'resource-exhausted');
        assert.match(err.message, /Burst submission limit reached/);
        return true;
      }
    );

    // Verify rr_b4 was never created
    const doc4 = await db.collection('restrooms').doc('rr_b4').get();
    assert.equal(doc4.exists, false);
  });

  // Scenario 3: Rolling 24-Hour Daily Limit
  it('Scenario 3: Rolling 24-Hour Daily Limit allows 10 submissions and rejects 11th with resource-exhausted', async () => {
    const uid = 'uid_charlie_daily';
    const baseTime = Date.now();

    // Submit 10 restrooms spaced 15 minutes apart
    for (let i = 1; i <= 10; i++) {
      const res = await executeSubmitRestroom(
        db,
        uid,
        getSamplePayload(`rr_c${i}`),
        baseTime + i * 15 * 60 * 1000
      );
      assert.equal(res.success, true);
    }

    // 11th submission at 11 * 15m = 165m (well within 24 hours) -> Must be rejected!
    await assert.rejects(
      async () => {
        await executeSubmitRestroom(
          db,
          uid,
          getSamplePayload('rr_c11'),
          baseTime + 11 * 15 * 60 * 1000
        );
      },
      (err: unknown) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, 'resource-exhausted');
        assert.match(err.message, /Daily submission limit reached/);
        return true;
      }
    );

    const doc11 = await db.collection('restrooms').doc('rr_c11').get();
    assert.equal(doc11.exists, false);
  });

  // Scenario 4: Boundary Timestamps
  it('Scenario 4: Boundary Timestamps permit submission once oldest burst/daily timestamp rolls outside window', async () => {
    const uid = 'uid_boundary_user';
    const t0 = Date.now();

    // 3 burst submissions at t0, t0+1m, t0+2m
    await executeSubmitRestroom(db, uid, getSamplePayload('rr_bound_1'), t0);
    await executeSubmitRestroom(db, uid, getSamplePayload('rr_bound_2'), t0 + 60 * 1000);
    await executeSubmitRestroom(db, uid, getSamplePayload('rr_bound_3'), t0 + 120 * 1000);

    // At t0 + 9m50s, 3 submissions are still in last 10m -> Rejected
    await assert.rejects(async () => {
      await executeSubmitRestroom(db, uid, getSamplePayload('rr_bound_fail'), t0 + 9 * 60 * 1000 + 50 * 1000);
    });

    // At t0 + 10m01s, the t0 submission rolled past 10 minutes -> Exactly 2 remain -> 4th succeeds!
    const resBurstRecovery = await executeSubmitRestroom(
      db,
      uid,
      getSamplePayload('rr_bound_4'),
      t0 + 10 * 60 * 1000 + 1000
    );
    assert.equal(resBurstRecovery.success, true);

    // Test 24-hour boundary recovery:
    // User already has 4 submissions. Add 6 more spaced by 15 mins to hit 10 total
    let currTime = t0 + 20 * 60 * 1000;
    for (let i = 5; i <= 10; i++) {
      currTime += 15 * 60 * 1000;
      await executeSubmitRestroom(db, uid, getSamplePayload(`rr_bound_${i}`), currTime);
    }

    // Now user has 10 daily submissions. Attempt at currTime + 1m fails:
    await assert.rejects(async () => {
      await executeSubmitRestroom(db, uid, getSamplePayload('rr_bound_fail_daily'), currTime + 60 * 1000);
    });

    // At t0 + 24h01m (past t0), the 1st submission has rolled out of 24h window -> Succeeds!
    const resDailyRecovery = await executeSubmitRestroom(
      db,
      uid,
      getSamplePayload('rr_bound_11'),
      t0 + 24 * 60 * 60 * 1000 + 1000
    );
    assert.equal(resDailyRecovery.success, true);
  });

  // Scenario 5: Timestamp Pruning
  it('Scenario 5: Timestamp Pruning removes timestamps older than 24 hours from array', async () => {
    const uid = 'uid_prune_user';
    const t0 = Date.now();

    // 1st submission at t0
    await executeSubmitRestroom(db, uid, getSamplePayload('rr_prune_1'), t0);

    // Verify rate limit doc has 1 timestamp
    const snap1 = await db.collection('contributionRateLimits').doc(uid).get();
    assert.equal(snap1.data()!.submissionTimestamps.length, 1);

    // 2nd submission at t0 + 25 hours (t0 has expired and must be pruned)
    const t25h = t0 + 25 * 60 * 60 * 1000;
    await executeSubmitRestroom(db, uid, getSamplePayload('rr_prune_2'), t25h);

    const snap2 = await db.collection('contributionRateLimits').doc(uid).get();
    const timestamps = snap2.data()!.submissionTimestamps as admin.firestore.Timestamp[];
    // t0 was pruned, only t25h remains in array!
    assert.equal(timestamps.length, 1);
    assert.equal(timestamps[0].toMillis(), t25h);
  });

  // Scenario 6: Concurrent Submissions
  it('Scenario 6: Concurrent Submissions serialize via transaction OCC; exactly 3 succeed and 2 reject', async () => {
    const uid = 'uid_concurrent_user';
    const now = Date.now();

    // Fire 5 parallel submission attempts simultaneously for the same UID
    const promises = [1, 2, 3, 4, 5].map((i) =>
      executeSubmitRestroom(db, uid, getSamplePayload(`rr_conc_${i}`), now)
        .then(() => ({ status: 'fulfilled' }))
        .catch((err: HttpsError) => ({ status: 'rejected', code: err.code }))
    );

    const results = await Promise.all(promises);
    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    const rejected = results.filter((r): r is { status: string; code: string } => r.status === 'rejected');

    // Exactly 3 succeed, exactly 2 rejected with resource-exhausted
    assert.equal(fulfilled.length, 3);
    assert.equal(rejected.length, 2);
    for (const r of rejected) {
      assert.equal(r.code, 'resource-exhausted');
    }

    // Verify exactly 3 documents in rateLimits
    const rateDoc = await db.collection('contributionRateLimits').doc(uid).get();
    assert.equal(rateDoc.data()!.submissionTimestamps.length, 3);
  });

  // Scenario 7: Idempotency with Stable ID
  it('Scenario 7: Idempotency with Stable ID succeeds without consuming rate limit quota', async () => {
    const uid = 'uid_idempotent_user';
    const payload = getSamplePayload('rr_stable_007');

    // First attempt
    const res1 = await executeSubmitRestroom(db, uid, payload);
    assert.equal(res1.success, true);
    assert.equal(res1.isIdempotentRetry, false);

    // Retry with identical stable ID and same user
    const res2 = await executeSubmitRestroom(db, uid, payload);
    assert.equal(res2.success, true);
    assert.equal(res2.isIdempotentRetry, true);

    // Ensure timestamp count did not increase
    const rateDoc = await db.collection('contributionRateLimits').doc(uid).get();
    assert.equal(rateDoc.data()!.submissionTimestamps.length, 1);
  });

  // Scenario 8: Document ID Collision
  it('Scenario 8: Document ID Collision rejects attempts to claim an existing ID owned by another user', async () => {
    const aliceUid = 'uid_alice_owner';
    const eveUid = 'uid_eve_attacker';
    const payload = getSamplePayload('rr_shared_id');

    // Alice creates rr_shared_id
    await executeSubmitRestroom(db, aliceUid, payload);

    // Eve attempts to submit with the same restroomId -> Rejection
    await assert.rejects(
      async () => {
        await executeSubmitRestroom(db, eveUid, payload);
      },
      (err: unknown) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, 'already-exists');
        return true;
      }
    );
  });

  // Scenario 9: Forged / Missing Identity & Input Validation
  it('Scenario 9: Unauthenticated call or malformed payload is rejected before database mutation', async () => {
    // Missing authentication context
    await assert.rejects(
      async () => {
        // @ts-expect-error Testing unauthenticated call
        await submitRestroom.run({ data: getSamplePayload('rr_unauth'), auth: null });
      },
      (err: unknown) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, 'unauthenticated');
        return true;
      }
    );

    // Malformed geohash that does not match coordinates
    await assert.rejects(
      async () => {
        await executeSubmitRestroom(db, 'uid_test', {
          ...getSamplePayload('rr_bad_geo'),
          latitude: 14.552,
          longitude: 121.0205,
          geohash: '000000', // invalid mismatch
        });
      },
      (err: unknown) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, 'invalid-argument');
        assert.match(err.message, /geohash does not match/);
        return true;
      }
    );

    // Client-supplied UID injection is stripped/ignored
    const res = await executeSubmitRestroom(db, 'real_uid_777', {
      ...getSamplePayload('rr_injection_test'),
      userUid: 'forged_uid_888',
      createdByUid: 'forged_uid_999',
    });
    assert.equal(res.success, true);
    const pubDoc = await db.collection('restrooms').doc('rr_injection_test').get();
    assert.equal(pubDoc.data()!.userUid, undefined);
    assert.equal(pubDoc.data()!.createdByUid, undefined);
  });

  // Scenario 10: Direct Write Bypass Prevention
  it('Scenario 10: Direct Write Bypass Prevention rejects direct client SDK writes under proposed production rules', async () => {
    const PROD_PROJECT_ID = 'flushcrowd-p26-prod-rules-test';
    const proposedProductionRules = `
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /restrooms/{restroomId} {
      allow read: if true;
      allow create: if false; // Production release gate: client direct writes disabled
      allow update, delete: if false;
    }
    match /contributions/{contributionId} {
      allow read: if request.auth != null && resource.data.userUid == request.auth.uid;
      allow create: if false; // Production release gate: client direct writes disabled
      allow update, delete: if false;
    }
    match /contributionRateLimits/{uid} {
      allow read, write: if false; // Strictly internal to Admin SDK
    }
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
`;

    const rulesEnv = await initializeTestEnvironment({
      projectId: PROD_PROJECT_ID,
      firestore: {
        rules: proposedProductionRules,
        host: '127.0.0.1',
        port: 8080,
      },
    });

    try {
      const clientDb = rulesEnv.authenticatedContext('attacker_uid').firestore();

      // 1. Direct client setDoc to /restrooms must fail with PERMISSION_DENIED
      const restroomRef = clientDb.collection('restrooms').doc('rr_bypass_001');
      await assertFails(
        restroomRef.set({
          id: 'rr_bypass_001',
          name: 'Bypassed Restroom',
          latitude: 14.55,
          longitude: 121.02,
          geohash: 'wdw4cc',
          accessType: 'free',
          status: 'unverified',
          createdAt: new Date(),
          updatedAt: new Date(),
        })
      );

      // 2. Direct client batch write to both /restrooms and /contributions must fail
      const batch = clientDb.batch();
      batch.set(clientDb.collection('restrooms').doc('rr_bypass_002'), {
        id: 'rr_bypass_002',
        name: 'Batch Bypass',
        latitude: 14.55,
        longitude: 121.02,
        geohash: 'wdw4cc',
        accessType: 'free',
        status: 'unverified',
        createdAt: new Date(),
        updatedAt: new Date(),
      });
      batch.set(clientDb.collection('contributions').doc('restroom_rr_bypass_002'), {
        id: 'restroom_rr_bypass_002',
        contributionType: 'restroom',
        resourceId: 'rr_bypass_002',
        userUid: 'attacker_uid',
        moderationState: 'pending',
        createdAt: new Date(),
        updatedAt: new Date(),
      });
      await assertFails(batch.commit());

      // 3. Direct client write to /contributionRateLimits must fail
      const rateLimitRef = clientDb.collection('contributionRateLimits').doc('attacker_uid');
      await assertFails(
        rateLimitRef.set({
          userUid: 'attacker_uid',
          submissionTimestamps: [],
          updatedAt: new Date(),
        })
      );

      // 4. Verify that Admin SDK (used by Cloud Function submitRestroom) succeeds in the same project
      let prodAdminApp: admin.app.App;
      if (admin.apps.some((a) => a?.name === 'prod-test-app')) {
        prodAdminApp = admin.app('prod-test-app');
      } else {
        prodAdminApp = admin.initializeApp({ projectId: PROD_PROJECT_ID }, 'prod-test-app');
      }
      const prodAdminDb = prodAdminApp.firestore();

      const adminRes = await executeSubmitRestroom(
        prodAdminDb,
        'trusted_function_caller_uid',
        getSamplePayload('rr_admin_success')
      );
      assert.equal(adminRes.success, true);

      // Verify written via Admin SDK
      const adminDoc = await prodAdminDb.collection('restrooms').doc('rr_admin_success').get();
      assert.equal(adminDoc.exists, true);
      assert.equal(adminDoc.data()?.name, 'Ayala Malls Restroom');
    } finally {
      await rulesEnv.cleanup();
    }
  });
});
