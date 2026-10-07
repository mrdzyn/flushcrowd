import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import fs from 'node:fs';
import path from 'node:path';
import { test, before, after, beforeEach, describe } from 'node:test';

const PROJECT_ID = 'flushcrowd-rules-test';
let testEnv;

before(async () => {
  const currentDir = path.dirname(new URL(import.meta.url).pathname);
  const rulesPath = path.resolve(currentDir, '../../firestore.rules');
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

function getValidRestroomData() {
  const now = new Date();
  return {
    id: 'rr_test_1',
    name: 'Downtown Public Restroom',
    latitude: 37.7749,
    longitude: -122.4194,
    geohash: '9q8yyk',
    accessType: 'free',
    status: 'active',
    createdAt: now,
    updatedAt: now,
  };
}

describe('Firestore Security Rules — FlushCrowd Phase 0', () => {
  // ===============================================================
  // 1. PUBLIC READS
  // ===============================================================
  describe('Public Reads', () => {
    test('public restroom read is allowed for unauthenticated users', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('restrooms').doc('rr_public_1').set(getValidRestroomData());
      });

      const unauthDb = testEnv.unauthenticatedContext().firestore();
      await assertSucceeds(unauthDb.collection('restrooms').doc('rr_public_1').get());
    });

    test('sanitized public rating read is allowed for unauthenticated users', async () => {
      const now = new Date();
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('ratings').doc('rate_public_1').set({
          id: 'rate_public_1',
          restroomId: 'rr_public_1',
          overall: 4.5,
          cleanliness: 5.0,
          comment: 'Very clean',
          createdAt: now,
          updatedAt: now,
        });
      });

      const unauthDb = testEnv.unauthenticatedContext().firestore();
      await assertSucceeds(unauthDb.collection('ratings').doc('rate_public_1').get());
    });
  });

  // ===============================================================
  // 2. PRIVATE DATA
  // ===============================================================
  describe('Private Data Isolation', () => {
    test('ratingOwnership public read is denied for unauthenticated users', async () => {
      const now = new Date();
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('ratingOwnership').doc('rr_1_userA').set({
          restroomId: 'rr_1',
          userUid: 'userA',
          ratingId: 'rate_1',
          createdAt: now,
          updatedAt: now,
        });
      });

      const unauthDb = testEnv.unauthenticatedContext().firestore();
      await assertFails(unauthDb.collection('ratingOwnership').doc('rr_1_userA').get());
    });

    test('ratingOwnership read is denied for a different authenticated user', async () => {
      const now = new Date();
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('ratingOwnership').doc('rr_1_userA').set({
          restroomId: 'rr_1',
          userUid: 'userA',
          ratingId: 'rate_1',
          createdAt: now,
          updatedAt: now,
        });
      });

      const userBDb = testEnv.authenticatedContext('userB').firestore();
      await assertFails(userBDb.collection('ratingOwnership').doc('rr_1_userA').get());
    });

    test('ratingOwnership read is allowed for the document owner', async () => {
      const now = new Date();
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('ratingOwnership').doc('rr_1_userA').set({
          restroomId: 'rr_1',
          userUid: 'userA',
          ratingId: 'rate_1',
          createdAt: now,
          updatedAt: now,
        });
      });

      const userADb = testEnv.authenticatedContext('userA').firestore();
      await assertSucceeds(userADb.collection('ratingOwnership').doc('rr_1_userA').get());
    });

    test('reports collection public and client read is completely denied', async () => {
      const now = new Date();
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('reports').doc('rep_1').set({
          restroomId: 'rr_1',
          reason: 'duplicate',
          notes: 'Duplicate listing',
          createdAt: now,
        });
      });

      const unauthDb = testEnv.unauthenticatedContext().firestore();
      await assertFails(unauthDb.collection('reports').doc('rep_1').get());

      const authDb = testEnv.authenticatedContext('userA').firestore();
      await assertFails(authDb.collection('reports').doc('rep_1').get());
    });
  });

  // ===============================================================
  // 3. AUTHENTICATION & CONTRIBUTION
  // ===============================================================
  describe('Authentication Requirements', () => {
    test('unauthenticated contribution write to restrooms is rejected', async () => {
      const unauthDb = testEnv.unauthenticatedContext().firestore();
      await assertFails(unauthDb.collection('restrooms').doc('rr_unauth').set(getValidRestroomData()));
    });

    test('unauthenticated contribution write to reports is rejected', async () => {
      const unauthDb = testEnv.unauthenticatedContext().firestore();
      await assertFails(unauthDb.collection('reports').doc('rep_unauth').set({
        restroomId: 'rr_1',
        reason: 'duplicate',
        createdAt: new Date(),
      }));
    });

    test('authenticated anonymous-style user can submit valid restroom with paired contribution', async () => {
      const authDb = testEnv.authenticatedContext('anon_user_123').firestore();
      const now = new Date();
      const batch = authDb.batch();
      batch.set(authDb.collection('restrooms').doc('rr_anon_1'), {
        ...getValidRestroomData(),
        id: 'rr_anon_1',
        status: 'unverified',
      });
      batch.set(authDb.collection('contributions').doc('restroom_rr_anon_1'), {
        id: 'restroom_rr_anon_1',
        contributionType: 'restroom',
        resourceId: 'rr_anon_1',
        restroomId: 'rr_anon_1',
        userUid: 'anon_user_123',
        moderationState: 'pending',
        createdAt: now,
        updatedAt: now,
      });
      await assertSucceeds(batch.commit());
    });
  });

  // ===============================================================
  // 4. PUBLIC/PRIVATE SEPARATION (NO CONTRIBUTOR UID IN PUBLIC DOCS)
  // ===============================================================
  describe('Public/Private Separation', () => {
    test('contributor UID (createdByUid, userUid, uid) cannot be injected into public restroom documents', async () => {
      const authDb = testEnv.authenticatedContext('user_123').firestore();

      await assertFails(authDb.collection('restrooms').doc('rr_with_uid1').set({
        ...getValidRestroomData(),
        createdByUid: 'user_123',
      }));

      await assertFails(authDb.collection('restrooms').doc('rr_with_uid2').set({
        ...getValidRestroomData(),
        userUid: 'user_123',
      }));

      await assertFails(authDb.collection('restrooms').doc('rr_with_uid3').set({
        ...getValidRestroomData(),
        uid: 'user_123',
      }));
    });

    test('contributor UID cannot be injected into public rating documents', async () => {
      const authDb = testEnv.authenticatedContext('user_123').firestore();
      const now = new Date();

      // Seed ownership record first
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('ratingOwnership').doc('rr_1_user_123').set({
          restroomId: 'rr_1',
          userUid: 'user_123',
          ratingId: 'rate_uid_test',
          createdAt: now,
          updatedAt: now,
        });
      });

      await assertFails(authDb.collection('ratings').doc('rate_uid_test').set({
        id: 'rate_uid_test',
        restroomId: 'rr_1',
        overall: 4.0,
        userUid: 'user_123',
        createdAt: now,
        updatedAt: now,
      }));
    });
  });

  // ===============================================================
  // 5. AGGREGATE INTEGRITY
  // ===============================================================
  describe('Aggregate Integrity', () => {
    test('client cannot forge positive initial aggregate values on restroom create', async () => {
      const authDb = testEnv.authenticatedContext('user_123').firestore();

      await assertFails(authDb.collection('restrooms').doc('rr_forged_rating').set({
        ...getValidRestroomData(),
        averageRating: 5.0,
      }));

      await assertFails(authDb.collection('restrooms').doc('rr_forged_count').set({
        ...getValidRestroomData(),
        ratingCount: 15,
      }));
    });

    test('client cannot modify protected aggregate fields or createdAt on restroom update', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('restrooms').doc('rr_up_1').set(getValidRestroomData());
      });

      const authDb = testEnv.authenticatedContext('user_123').firestore();

      // Attempt to modify averageRating
      await assertFails(authDb.collection('restrooms').doc('rr_up_1').update({
        averageRating: 4.8,
        updatedAt: new Date(),
      }));

      // Attempt to modify ratingCount
      await assertFails(authDb.collection('restrooms').doc('rr_up_1').update({
        ratingCount: 50,
        updatedAt: new Date(),
      }));

      // Attempt to modify createdAt
      await assertFails(authDb.collection('restrooms').doc('rr_up_1').update({
        createdAt: new Date('2020-01-01'),
        updatedAt: new Date(),
      }));
    });
  });

  // ===============================================================
  // 6. COORDINATES & CONTROLLED FIELDS VALIDATION
  // ===============================================================
  describe('Coordinates and Controlled Field Validation', () => {
    test('invalid latitude (> 90.0 or < -90.0) is rejected', async () => {
      const authDb = testEnv.authenticatedContext('user_123').firestore();

      await assertFails(authDb.collection('restrooms').doc('rr_bad_lat1').set({
        ...getValidRestroomData(),
        latitude: 91.5,
      }));

      await assertFails(authDb.collection('restrooms').doc('rr_bad_lat2').set({
        ...getValidRestroomData(),
        latitude: -90.1,
      }));
    });

    test('invalid longitude (> 180.0 or < -180.0) is rejected', async () => {
      const authDb = testEnv.authenticatedContext('user_123').firestore();

      await assertFails(authDb.collection('restrooms').doc('rr_bad_lng1').set({
        ...getValidRestroomData(),
        longitude: 181.0,
      }));

      await assertFails(authDb.collection('restrooms').doc('rr_bad_lng2').set({
        ...getValidRestroomData(),
        longitude: -180.5,
      }));
    });

    test('invalid controlled enum value (accessType or status) is rejected', async () => {
      const authDb = testEnv.authenticatedContext('user_123').firestore();

      await assertFails(authDb.collection('restrooms').doc('rr_bad_access').set({
        ...getValidRestroomData(),
        accessType: 'unknown_access',
      }));

      await assertFails(authDb.collection('restrooms').doc('rr_bad_status').set({
        ...getValidRestroomData(),
        status: 'super_active',
      }));
    });
  });

  // ===============================================================
  // 7. RATING OWNERSHIP (ONE PER USER PER RESTROOM)
  // ===============================================================
  describe('Rating Ownership Enforcement', () => {
    test('deterministic ownership document {restroomId}_{auth.uid} succeeds for owner', async () => {
      const authDb = testEnv.authenticatedContext('user_123').firestore();
      const now = new Date();

      await assertSucceeds(authDb.collection('ratingOwnership').doc('rr_1_user_123').set({
        restroomId: 'rr_1',
        userUid: 'user_123',
        ratingId: 'rate_abc',
        createdAt: now,
        updatedAt: now,
      }));
    });

    test('ownership document rejected if userUid does not match request.auth.uid', async () => {
      const authDb = testEnv.authenticatedContext('user_attacker').firestore();
      const now = new Date();

      await assertFails(authDb.collection('ratingOwnership').doc('rr_1_user_victim').set({
        restroomId: 'rr_1',
        userUid: 'user_victim',
        ratingId: 'rate_spoofed',
        createdAt: now,
        updatedAt: now,
      }));
    });

    test('ownership document rejected if ID does not follow {restroomId}_{auth.uid} scheme', async () => {
      const authDb = testEnv.authenticatedContext('user_123').firestore();
      const now = new Date();

      await assertFails(authDb.collection('ratingOwnership').doc('arbitrary_id_123').set({
        restroomId: 'rr_1',
        userUid: 'user_123',
        ratingId: 'rate_abc',
        createdAt: now,
        updatedAt: now,
      }));
    });

    test('another UID cannot modify an existing rating ownership document', async () => {
      const now = new Date();
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('ratingOwnership').doc('rr_1_userA').set({
          restroomId: 'rr_1',
          userUid: 'userA',
          ratingId: 'rate_a',
          createdAt: now,
          updatedAt: now,
        });
      });

      const userBDb = testEnv.authenticatedContext('userB').firestore();
      await assertFails(userBDb.collection('ratingOwnership').doc('rr_1_userA').update({
        ratingId: 'rate_b_hijacked',
        updatedAt: new Date(),
      }));
    });
  });
});
