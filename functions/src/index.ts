import * as admin from 'firebase-admin';
import { setGlobalOptions } from 'firebase-functions/v2';

// Set default Cloud Functions region
setGlobalOptions({ region: 'us-central1' });

// Initialize Firebase Admin SDK if not already initialized
if (admin.apps.length === 0) {
  admin.initializeApp();
}

export { submitRestroom, createSubmitRestroom, matchesCanonicalSubmission } from './submit_restroom';
export { validateAndNormalizePayload } from './validation';
export { encodeGeohash } from './geohash';
export { getAppConfig } from './config';
