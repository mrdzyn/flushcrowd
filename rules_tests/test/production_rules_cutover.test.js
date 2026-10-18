import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import fs from 'node:fs';
import path from 'node:path';
import { test, before, after, beforeEach, describe } from 'node:test';

const PROJECT_ID = 'flushcrowd-prod-rules-cutover-test';
let testEnv;

before(async () => {
  const currentDir = path.dirname(new URL(import.meta.url).pathname);
  const rulesPath = path.resolve(currentDir, '../../firestore.production.rules');
  const rules = fs.readFileSync(rulesPath, 'utf8');

  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules,
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

beforeEach(async () => {
  if (testEnv) {
    await testEnv.clearFirestore();
  }
});

function getValidRestroomData(restroomId = 'rr_cutover_100') {
  const now = new Date();
  return {
    id: restroomId,
    name: 'Greenbelt 5 Garden Restroom',
    latitude: 14.5520,
    longitude: 121.0205,
    geohash: 'wdw4fq',
    accessType: 'free',
    status: 'unverified',
    buildingName: 'Greenbelt 5',
    floor: '2F',
    male: true,
    female: true,
    allGender: null,
    pwdAccessible: true,
    babyChanging: false,
    hasBidet: true,
    hasToiletPaper: true,
    hasSoap: true,
    hasHandDryer: true,
    averageRating: 0.0,
    ratingCount: 0,
    verificationCount: 0,
    negativeVerificationCount: 0,
    lastVerifiedAt: null,
    createdAt: now,
    updatedAt: now,
  };
}

function getValidContributionData(restroomId = 'rr_cutover_100', userUid = 'contributor_user') {
  const now = new Date();
  return {
    id: `restroom_${restroomId}`,
    contributionType: 'restroom',
    resourceId: restroomId,
    restroomId: restroomId,
    userUid: userUid,
    moderationState: 'pending',
    createdAt: now,
    updatedAt: now,
  };
}

describe('P2.6 Task 2 — Production Security Rules Cutover Candidate', () => {
  test('1. Direct client public restroom create is rejected', async () => {
    const authDb = testEnv.authenticatedContext('contributor_user').firestore();
    const unauthDb = testEnv.unauthenticatedContext().firestore();
    const data = getValidRestroomData('rr_client_001');

    // Authenticated client SDK direct create fails
    await assertFails(authDb.collection('restrooms').doc('rr_client_001').set(data));

    // Unauthenticated client SDK direct create fails
    await assertFails(unauthDb.collection('restrooms').doc('rr_client_001').set(data));
  });

  test('2. Direct client contribution create is rejected', async () => {
    const authDb = testEnv.authenticatedContext('contributor_user').firestore();
    const unauthDb = testEnv.unauthenticatedContext().firestore();
    const data = getValidContributionData('rr_client_002', 'contributor_user');

    // Authenticated client SDK direct contribution create fails
    await assertFails(
      authDb.collection('contributions').doc('restroom_rr_client_002').set(data)
    );

    // Unauthenticated client SDK direct contribution create fails
    await assertFails(
      unauthDb.collection('contributions').doc('restroom_rr_client_002').set(data)
    );
  });

  test('3. Direct client batch writes cannot bypass restrictions', async () => {
    const authDb = testEnv.authenticatedContext('contributor_user').firestore();
    const restroomId = 'rr_batch_003';
    const restroomData = getValidRestroomData(restroomId);
    const contribData = getValidContributionData(restroomId, 'contributor_user');

    // Construct paired batch write matching staging validation schemas
    const batch = authDb.batch();
    batch.set(authDb.collection('restrooms').doc(restroomId), restroomData);
    batch.set(authDb.collection('contributions').doc(`restroom_${restroomId}`), contribData);

    // Under production cutover rules, direct batch commit MUST fail with PERMISSION_DENIED
    await assertFails(batch.commit());
  });

  test('4. Authorized Admin SDK writes succeed', async () => {
    const restroomId = 'rr_admin_004';
    const userUid = 'admin_managed_user';
    const restroomData = getValidRestroomData(restroomId);
    const contribData = getValidContributionData(restroomId, userUid);
    const now = new Date();

    // Simulate Admin SDK (e.g. Cloud Function submitRestroom backend) via security rules disabled context
    await testEnv.withSecurityRulesDisabled(async (adminContext) => {
      const adminDb = adminContext.firestore();

      // Admin write to public restrooms succeeds
      await assertSucceeds(adminDb.collection('restrooms').doc(restroomId).set(restroomData));

      // Admin write to private contributions succeeds
      await assertSucceeds(
        adminDb.collection('contributions').doc(`restroom_${restroomId}`).set(contribData)
      );

      // Admin write to private contributionRateLimits succeeds
      await assertSucceeds(
        adminDb.collection('contributionRateLimits').doc(userUid).set({
          userUid: userUid,
          submissionTimestamps: [now],
          updatedAt: now,
        })
      );
    });
  });

  test('5. Legitimate public discovery reads continue working', async () => {
    const restroomId = 'rr_read_005';
    const restroomData = getValidRestroomData(restroomId);

    // Seed document via Admin SDK
    await testEnv.withSecurityRulesDisabled(async (adminContext) => {
      await adminContext.firestore().collection('restrooms').doc(restroomId).set(restroomData);
    });

    const unauthDb = testEnv.unauthenticatedContext().firestore();
    const authDb = testEnv.authenticatedContext('random_user').firestore();

    // 1. Unauthenticated single-document get succeeds
    await assertSucceeds(unauthDb.collection('restrooms').doc(restroomId).get());

    // 2. Authenticated single-document get succeeds
    await assertSucceeds(authDb.collection('restrooms').doc(restroomId).get());

    // 3. Spatial geohash range query succeeds for public discovery
    const query = unauthDb
      .collection('restrooms')
      .where('geohash', '>=', 'wdw4')
      .where('geohash', '<=', 'wdw4~');
    await assertSucceeds(query.get());
  });

  test('6. Private contributor ownership and privacy rules remain intact', async () => {
    const restroomId = 'rr_privacy_006';
    const ownerUid = 'legitimate_owner_uid';
    const otherUid = 'unauthorized_reader_uid';
    const contribDocId = `restroom_${restroomId}`;
    const contribData = getValidContributionData(restroomId, ownerUid);

    // Seed data via Admin SDK
    await testEnv.withSecurityRulesDisabled(async (adminContext) => {
      const db = adminContext.firestore();
      await db.collection('contributions').doc(contribDocId).set(contribData);
      await db.collection('contributionRateLimits').doc(ownerUid).set({
        userUid: ownerUid,
        submissionTimestamps: [new Date()],
        updatedAt: new Date(),
      });
    });

    const ownerDb = testEnv.authenticatedContext(ownerUid).firestore();
    const otherDb = testEnv.authenticatedContext(otherUid).firestore();
    const unauthDb = testEnv.unauthenticatedContext().firestore();

    // 6a. Contributor can read their own contribution record
    await assertSucceeds(ownerDb.collection('contributions').doc(contribDocId).get());

    // 6b. Other authenticated user CANNOT read contributor record
    await assertFails(otherDb.collection('contributions').doc(contribDocId).get());

    // 6c. Unauthenticated user CANNOT read contributor record
    await assertFails(unauthDb.collection('contributions').doc(contribDocId).get());

    // 6d. Rate-limit records remain strictly inaccessible to clients (read and write)
    await assertFails(ownerDb.collection('contributionRateLimits').doc(ownerUid).get());
    await assertFails(
      ownerDb.collection('contributionRateLimits').doc(ownerUid).set({
        userUid: ownerUid,
        submissionTimestamps: [],
      })
    );
    await assertFails(otherDb.collection('contributionRateLimits').doc(ownerUid).get());
    await assertFails(unauthDb.collection('contributionRateLimits').doc(ownerUid).get());

    // 6e. Facility updates and deletions remain disabled
    await assertFails(
      ownerDb.collection('restrooms').doc(restroomId).update({ name: 'Tampered Name' })
    );
    await assertFails(ownerDb.collection('restrooms').doc(restroomId).delete());

    // 6f. Contribution updates and deletions remain disabled
    await assertFails(
      ownerDb.collection('contributions').doc(contribDocId).update({ moderationState: 'approved' })
    );
    await assertFails(ownerDb.collection('contributions').doc(contribDocId).delete());
  });
});
