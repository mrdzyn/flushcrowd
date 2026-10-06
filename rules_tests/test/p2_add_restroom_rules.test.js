import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import fs from 'node:fs';
import path from 'node:path';
import { test, before, after, beforeEach, describe } from 'node:test';

const PROJECT_ID = 'looradar-p2-rules-test';
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

function getValidRestroomData(restroomId = 'rr_test_100') {
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
    accessInstructions: 'Near the courtyard entrance',
    createdAt: now,
    updatedAt: now,
  };
}

function getValidContributionData(restroomId = 'rr_test_100', uid = 'test_user_1') {
  const now = new Date();
  return {
    id: `restroom_${restroomId}`,
    contributionType: 'restroom',
    resourceId: restroomId,
    restroomId: restroomId,
    userUid: uid,
    moderationState: 'pending',
    createdAt: now,
    updatedAt: now,
  };
}

describe('Firestore Security Rules — LooRadar Phase 2 Milestone P2.1', () => {
  // ===============================================================
  // Group 1: Public/Private Pair Invariants (Tests 1–10)
  // ===============================================================
  describe('Group 1: Public/Private Pair Invariants (10 Tests)', () => {
    test('1. Valid atomic restroom + contribution pair within Firestore access-call limits -> ALLOW', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch = authDb.batch();
      const rrId = 'rr_valid_pair_1';
      batch.set(authDb.collection('restrooms').doc(rrId), getValidRestroomData(rrId));
      batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), getValidContributionData(rrId, 'test_user_1'));
      await assertSucceeds(batch.commit());
    });

    test('2. Restroom created without contribution -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const rrId = 'rr_orphan_restroom';
      await assertFails(authDb.collection('restrooms').doc(rrId).set(getValidRestroomData(rrId)));
    });

    test('3. Contribution created without restroom -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const rrId = 'rr_orphan_contrib';
      await assertFails(
        authDb.collection('contributions').doc(`restroom_${rrId}`).set(getValidContributionData(rrId, 'test_user_1'))
      );
    });

    test('4. Pre-existing contribution then restroom created -> REJECT', async () => {
      const rrId = 'rr_preexisting_contrib';
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('contributions').doc(`restroom_${rrId}`).set(
          getValidContributionData(rrId, 'test_user_1')
        );
      });

      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      await assertFails(authDb.collection('restrooms').doc(rrId).set(getValidRestroomData(rrId)));
    });

    test('5. Pre-existing restroom then contribution created -> REJECT', async () => {
      const rrId = 'rr_preexisting_restroom';
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('restrooms').doc(rrId).set(getValidRestroomData(rrId));
      });

      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      await assertFails(
        authDb.collection('contributions').doc(`restroom_${rrId}`).set(getValidContributionData(rrId, 'test_user_1'))
      );
    });

    test('6. Mismatched resourceId between restroom and contribution -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch = authDb.batch();
      const rrId = 'rr_mismatch_res_1';
      batch.set(authDb.collection('restrooms').doc(rrId), getValidRestroomData(rrId));
      const badContrib = {
        ...getValidContributionData(rrId, 'test_user_1'),
        resourceId: 'rr_different_res_id',
      };
      batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), badContrib);
      await assertFails(batch.commit());
    });

    test('7. Mismatched restroomId between restroom and contribution -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch = authDb.batch();
      const rrId = 'rr_mismatch_rr_1';
      batch.set(authDb.collection('restrooms').doc(rrId), getValidRestroomData(rrId));
      const badContrib = {
        ...getValidContributionData(rrId, 'test_user_1'),
        restroomId: 'rr_different_rr_id',
      };
      batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), badContrib);
      await assertFails(batch.commit());
    });

    test('8. Wrong deterministic contribution ID format (not restroom_{id}) -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch = authDb.batch();
      const rrId = 'rr_bad_id_format';
      batch.set(authDb.collection('restrooms').doc(rrId), getValidRestroomData(rrId));
      const badContrib = {
        ...getValidContributionData(rrId, 'test_user_1'),
        id: `contribution_${rrId}`,
      };
      batch.set(authDb.collection('contributions').doc(`contribution_${rrId}`), badContrib);
      await assertFails(batch.commit());
    });

    test('9. Forged userUid in contribution record -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch = authDb.batch();
      const rrId = 'rr_forged_uid';
      batch.set(authDb.collection('restrooms').doc(rrId), getValidRestroomData(rrId));
      batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), getValidContributionData(rrId, 'spoofed_user_id'));
      await assertFails(batch.commit());
    });

    test('10. Wrong moderationState on creation (not pending) -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch = authDb.batch();
      const rrId = 'rr_bad_mod_state';
      batch.set(authDb.collection('restrooms').doc(rrId), getValidRestroomData(rrId));
      const badContrib = {
        ...getValidContributionData(rrId, 'test_user_1'),
        moderationState: 'approved',
      };
      batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), badContrib);
      await assertFails(batch.commit());
    });
  });

  // ===============================================================
  // Group 2: Public Restroom Creation & Restrictions (Tests 11–15)
  // ===============================================================
  describe('Group 2: Public Restroom Creation & Restrictions (5 Tests)', () => {
    test('11. Unauthenticated restroom creation -> REJECT', async () => {
      const unauthDb = testEnv.unauthenticatedContext().firestore();
      const batch = unauthDb.batch();
      const rrId = 'rr_unauth_write';
      batch.set(unauthDb.collection('restrooms').doc(rrId), getValidRestroomData(rrId));
      batch.set(unauthDb.collection('contributions').doc(`restroom_${rrId}`), getValidContributionData(rrId, 'anon'));
      await assertFails(batch.commit());
    });

    test('12. Attempt to create restroom with status: active -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch = authDb.batch();
      const rrId = 'rr_active_status';
      const badRestroom = {
        ...getValidRestroomData(rrId),
        status: 'active',
      };
      batch.set(authDb.collection('restrooms').doc(rrId), badRestroom);
      batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), getValidContributionData(rrId, 'test_user_1'));
      await assertFails(batch.commit());
    });

    test('13. Attempt to create restroom with non-zero initial aggregates -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch = authDb.batch();
      const rrId = 'rr_forged_aggregates';
      const badRestroom = {
        ...getValidRestroomData(rrId),
        averageRating: 4.8,
        ratingCount: 10,
      };
      batch.set(authDb.collection('restrooms').doc(rrId), badRestroom);
      batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), getValidContributionData(rrId, 'test_user_1'));
      await assertFails(batch.commit());
    });

    test('14. Contributor UID injected into public restroom document -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch = authDb.batch();
      const rrId = 'rr_injected_uid';
      const badRestroom = {
        ...getValidRestroomData(rrId),
        createdByUid: 'test_user_1',
      };
      batch.set(authDb.collection('restrooms').doc(rrId), badRestroom);
      batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), getValidContributionData(rrId, 'test_user_1'));
      await assertFails(batch.commit());
    });

    test('15. Public id field does not match Firestore document ID -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch = authDb.batch();
      const rrId = 'rr_doc_id_actual';
      const badRestroom = {
        ...getValidRestroomData(rrId),
        id: 'rr_mismatched_inner_id',
      };
      batch.set(authDb.collection('restrooms').doc(rrId), badRestroom);
      batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), getValidContributionData(rrId, 'test_user_1'));
      await assertFails(batch.commit());
    });
  });

  // ===============================================================
  // Group 3: Updates & Deletions Prohibited (Tests 16–20)
  // ===============================================================
  describe('Group 3: Updates & Deletions Prohibited in Phase 2 (5 Tests)', () => {
    const seededRrId = 'rr_seeded_facility';

    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('restrooms').doc(seededRrId).set(getValidRestroomData(seededRrId));
        await context.firestore().collection('contributions').doc(`restroom_${seededRrId}`).set(
          getValidContributionData(seededRrId, 'creator_uid')
        );
      });
    });

    test('16. Original creator attempts direct update of public restroom -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('creator_uid').firestore();
      await assertFails(
        authDb.collection('restrooms').doc(seededRrId).update({
          name: 'Updated Name Attempt',
          updatedAt: new Date(),
        })
      );
    });

    test('17. Another authenticated user attempts direct update of public restroom -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('different_uid').firestore();
      await assertFails(
        authDb.collection('restrooms').doc(seededRrId).update({
          name: 'Attacker Updated Name',
          updatedAt: new Date(),
        })
      );
    });

    test('18. Client attempts status modification on public restroom -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('creator_uid').firestore();
      await assertFails(
        authDb.collection('restrooms').doc(seededRrId).update({
          status: 'active',
          updatedAt: new Date(),
        })
      );
    });

    test('19. Client attempts coordinate or geohash update on public restroom -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('creator_uid').firestore();
      await assertFails(
        authDb.collection('restrooms').doc(seededRrId).update({
          latitude: 14.9999,
          geohash: 'wdw4zz',
          updatedAt: new Date(),
        })
      );
    });

    test('20. Client attempts deletion of public restroom -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('creator_uid').firestore();
      await assertFails(authDb.collection('restrooms').doc(seededRrId).delete());
    });
  });

  // ===============================================================
  // Group 4: Nullable Truth & Field Validation at Rule Layer (Tests 21–22)
  // ===============================================================
  describe('Group 4: Nullable Truth & Field Validation at Rule Layer (2 Tests)', () => {
    test('21. Valid nullable amenity fields (explicit bool or missing/null) -> ALLOW', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch = authDb.batch();
      const rrId = 'rr_nullable_valid';
      const validNullableRestroom = {
        ...getValidRestroomData(rrId),
        male: true,
        female: false,
        allGender: null,
        hasBidet: true,
        hasToiletPaper: null,
        hasSoap: false,
        pwdAccessible: null,
      };
      batch.set(authDb.collection('restrooms').doc(rrId), validNullableRestroom);
      batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), getValidContributionData(rrId, 'test_user_1'));
      await assertSucceeds(batch.commit());
    });

    test('22. Invalid amenity data type in Firestore doc (e.g. string instead of bool) -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch = authDb.batch();
      const rrId = 'rr_invalid_type';
      const invalidTypeRestroom = {
        ...getValidRestroomData(rrId),
        hasBidet: 'yes', // Invalid type: must be bool or null
      };
      batch.set(authDb.collection('restrooms').doc(rrId), invalidTypeRestroom);
      batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), getValidContributionData(rrId, 'test_user_1'));
      await assertFails(batch.commit());
    });
  });
});
