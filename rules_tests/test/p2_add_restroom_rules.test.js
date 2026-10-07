import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import fs from 'node:fs';
import path from 'node:path';
import { test, before, after, beforeEach, describe } from 'node:test';

const PROJECT_ID = 'flushcrowd-p2-rules-test';
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

describe('Firestore Security Rules — FlushCrowd Phase 2 Milestone P2.1', () => {
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
  // Group 4: Nullable Truth & Field Validation at Rule Layer (Tests 21–28)
  // ===============================================================
  describe('Group 4: Nullable Truth & Field Validation at Rule Layer (8 Tests)', () => {
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

    test('23. Invalid gender configuration (all false) -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch = authDb.batch();
      const rrId = 'rr_gender_all_false';
      const invalidGenderRestroom = {
        ...getValidRestroomData(rrId),
        male: false,
        female: false,
        allGender: false,
      };
      batch.set(authDb.collection('restrooms').doc(rrId), invalidGenderRestroom);
      batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), getValidContributionData(rrId, 'test_user_1'));
      await assertFails(batch.commit());
    });

    test('24. Invalid gender configuration (false/null/false) -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch = authDb.batch();
      const rrId = 'rr_gender_false_null_false';
      const invalidGenderRestroom = {
        ...getValidRestroomData(rrId),
        male: false,
        female: null,
        allGender: false,
      };
      batch.set(authDb.collection('restrooms').doc(rrId), invalidGenderRestroom);
      batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), getValidContributionData(rrId, 'test_user_1'));
      await assertFails(batch.commit());
    });

    test('25. Valid gender configuration (at least one positive) -> ALLOW', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const rrId1 = 'rr_gender_one_true_all';
      const batch1 = authDb.batch();
      batch1.set(authDb.collection('restrooms').doc(rrId1), {
        ...getValidRestroomData(rrId1),
        male: false,
        female: false,
        allGender: true,
      });
      batch1.set(authDb.collection('contributions').doc(`restroom_${rrId1}`), getValidContributionData(rrId1, 'test_user_1'));
      await assertSucceeds(batch1.commit());

      const rrId2 = 'rr_gender_one_true_male';
      const batch2 = authDb.batch();
      batch2.set(authDb.collection('restrooms').doc(rrId2), {
        ...getValidRestroomData(rrId2),
        male: true,
        female: null,
        allGender: null,
      });
      batch2.set(authDb.collection('contributions').doc(`restroom_${rrId2}`), getValidContributionData(rrId2, 'test_user_1'));
      await assertSucceeds(batch2.commit());

      const rrId3 = 'rr_gender_one_true_female';
      const batch3 = authDb.batch();
      batch3.set(authDb.collection('restrooms').doc(rrId3), {
        ...getValidRestroomData(rrId3),
        male: null,
        female: true,
        allGender: false,
      });
      batch3.set(authDb.collection('contributions').doc(`restroom_${rrId3}`), getValidContributionData(rrId3, 'test_user_1'));
      await assertSucceeds(batch3.commit());
    });

    test('26. Invalid geohash format (uppercase or non-base32 chars like "a") -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch1 = authDb.batch();
      const rrId1 = 'rr_bad_geohash_upper';
      batch1.set(authDb.collection('restrooms').doc(rrId1), {
        ...getValidRestroomData(rrId1),
        geohash: 'WDW4FQ', // Uppercase invalid
      });
      batch1.set(authDb.collection('contributions').doc(`restroom_${rrId1}`), getValidContributionData(rrId1, 'test_user_1'));
      await assertFails(batch1.commit());

      const batch2 = authDb.batch();
      const rrId2 = 'rr_bad_geohash_char_a';
      batch2.set(authDb.collection('restrooms').doc(rrId2), {
        ...getValidRestroomData(rrId2),
        geohash: 'wdw4a', // 'a' is not in standard geohash base32
      });
      batch2.set(authDb.collection('contributions').doc(`restroom_${rrId2}`), getValidContributionData(rrId2, 'test_user_1'));
      await assertFails(batch2.commit());
    });

    test('27. Valid geohash charset matching ^[0-9bcdefghjkmnpqrstuvwxyz]{4,12}$ -> ALLOW', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      const batch = authDb.batch();
      const rrId = 'rr_valid_geohash';
      const validGeohashRestroom = {
        ...getValidRestroomData(rrId),
        geohash: 'wdw4fq9',
      };
      batch.set(authDb.collection('restrooms').doc(rrId), validGeohashRestroom);
      batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), getValidContributionData(rrId, 'test_user_1'));
      await assertSucceeds(batch.commit());
    });

    test('28. Paid access type with valid 3-letter ISO uppercase currencies (USD, EUR, PHP) -> ALLOW', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      for (const currency of ['USD', 'EUR', 'PHP']) {
        const batch = authDb.batch();
        const rrId = `rr_paid_${currency.toLowerCase()}`;
        batch.set(authDb.collection('restrooms').doc(rrId), {
          ...getValidRestroomData(rrId),
          accessType: 'paid',
          feeAmount: 20.0,
          feeCurrency: currency,
        });
        batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), getValidContributionData(rrId, 'test_user_1'));
        await assertSucceeds(batch.commit());
      }
    });

    test('29. Paid access type with invalid currencies (123, P1P, PH, PHPP, lowercase) -> REJECT', async () => {
      const authDb = testEnv.authenticatedContext('test_user_1').firestore();
      for (const badCurrency of ['123', 'P1P', 'PH', 'PHPP', 'php']) {
        const batch = authDb.batch();
        const rrId = `rr_bad_curr_${badCurrency}`;
        batch.set(authDb.collection('restrooms').doc(rrId), {
          ...getValidRestroomData(rrId),
          accessType: 'paid',
          feeAmount: 20.0,
          feeCurrency: badCurrency,
        });
        batch.set(authDb.collection('contributions').doc(`restroom_${rrId}`), getValidContributionData(rrId, 'test_user_1'));
        await assertFails(batch.commit());
      }
    });
  });
});
