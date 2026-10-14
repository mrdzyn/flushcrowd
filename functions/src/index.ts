import * as admin from 'firebase-admin';

// Initialize Firebase Admin SDK if not already initialized
if (admin.apps.length === 0) {
  admin.initializeApp();
}

export { submitRestroom } from './submit_restroom';
export { validateAndNormalizePayload } from './validation';
export { encodeGeohash } from './geohash';
