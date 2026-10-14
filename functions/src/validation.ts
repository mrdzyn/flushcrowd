import { HttpsError } from 'firebase-functions/v2/https';
import { encodeGeohash, isValidGeohashFormat } from './geohash';

export interface SubmitRestroomPayload {
  restroomId: string;
  name: string;
  latitude: number;
  longitude: number;
  accessType: 'free' | 'paid' | 'customer_only' | 'key_required';
  geohash?: string;

  countryCode?: string | null;
  region?: string | null;
  city?: string | null;
  buildingName?: string | null;
  buildingSection?: string | null;
  floor?: string | null;
  unitOrArea?: string | null;
  landmark?: string | null;
  directionsNote?: string | null;
  accessInstructions?: string | null;

  feeAmount?: number | null;
  feeCurrency?: string | null;

  male?: boolean | null;
  female?: boolean | null;
  allGender?: boolean | null;

  pwdAccessible?: boolean | null;
  babyChanging?: boolean | null;
  hasBidet?: boolean | null;
  hasToiletPaper?: boolean | null;
  hasSoap?: boolean | null;
  hasHandDryer?: boolean | null;

  // Untrusted fields if client sends them
  status?: string;
  averageRating?: number;
  ratingCount?: number;
  verificationCount?: number;
  negativeVerificationCount?: number;
  lastVerifiedAt?: unknown;
  createdAt?: unknown;
  updatedAt?: unknown;
  userUid?: string;
  createdByUid?: string;
}

export interface ValidatedRestroomData {
  restroomId: string;
  name: string;
  latitude: number;
  longitude: number;
  geohash: string;
  accessType: 'free' | 'paid' | 'customer_only' | 'key_required';

  countryCode: string | null;
  region: string | null;
  city: string | null;
  buildingName: string | null;
  buildingSection: string | null;
  floor: string | null;
  unitOrArea: string | null;
  landmark: string | null;
  directionsNote: string | null;
  accessInstructions: string | null;

  feeAmount: number | null;
  feeCurrency: string | null;

  male: boolean | null;
  female: boolean | null;
  allGender: boolean | null;

  pwdAccessible: boolean | null;
  babyChanging: boolean | null;
  hasBidet: boolean | null;
  hasToiletPaper: boolean | null;
  hasSoap: boolean | null;
  hasHandDryer: boolean | null;
}

function validateOptionalString(
  val: unknown,
  fieldName: string,
  minLen: number,
  maxLen: number
): string | null {
  if (val === undefined || val === null || val === '') {
    return null;
  }
  if (typeof val !== 'string') {
    throw new HttpsError('invalid-argument', `${fieldName} must be a string.`);
  }
  const trimmed = val.trim();
  if (trimmed.length === 0) {
    return null;
  }
  if (trimmed.length < minLen || trimmed.length > maxLen) {
    throw new HttpsError(
      'invalid-argument',
      `${fieldName} must be between ${minLen} and ${maxLen} characters.`
    );
  }
  return trimmed;
}

function validateOptionalNullableBool(val: unknown, fieldName: string): boolean | null {
  if (val === undefined || val === null) {
    return null;
  }
  if (typeof val !== 'boolean') {
    throw new HttpsError(
      'invalid-argument',
      `${fieldName} must be a boolean or null.`
    );
  }
  return val;
}

export function validateAndNormalizePayload(data: unknown): ValidatedRestroomData {
  if (!data || typeof data !== 'object') {
    throw new HttpsError('invalid-argument', 'Payload must be a non-null object.');
  }

  const p = data as SubmitRestroomPayload;

  // 1. Restroom ID validation
  if (!p.restroomId || typeof p.restroomId !== 'string') {
    throw new HttpsError('invalid-argument', 'restroomId is required and must be a string.');
  }
  const restroomId = p.restroomId;
  if (
    restroomId !== restroomId.trim() ||
    restroomId.length < 1 ||
    restroomId.length > 100 ||
    restroomId.includes('/') ||
    restroomId === '.' ||
    restroomId === '..'
  ) {
    throw new HttpsError(
      'invalid-argument',
      'Invalid stable restroom ID: must be 1-100 characters without path separators or leading/trailing whitespace.'
    );
  }

  // 2. Name validation
  if (!p.name || typeof p.name !== 'string') {
    throw new HttpsError('invalid-argument', 'name is required and must be a string.');
  }
  const name = p.name.trim();
  if (name.length < 1 || name.length > 100) {
    throw new HttpsError('invalid-argument', 'name must be between 1 and 100 characters.');
  }

  // 3. Coordinates validation
  if (typeof p.latitude !== 'number' || !Number.isFinite(p.latitude)) {
    throw new HttpsError('invalid-argument', 'latitude must be a finite number.');
  }
  if (p.latitude < -90.0 || p.latitude > 90.0) {
    throw new HttpsError('invalid-argument', 'latitude must be between -90.0 and 90.0.');
  }

  if (typeof p.longitude !== 'number' || !Number.isFinite(p.longitude)) {
    throw new HttpsError('invalid-argument', 'longitude must be a finite number.');
  }
  if (p.longitude < -180.0 || p.longitude > 180.0) {
    throw new HttpsError('invalid-argument', 'longitude must be between -180.0 and 180.0.');
  }

  // 4. Server-authoritative geohash calculation
  const computedGeohash = encodeGeohash(p.latitude, p.longitude, 6);
  if (p.geohash) {
    if (!isValidGeohashFormat(p.geohash)) {
      throw new HttpsError('invalid-argument', 'geohash format is invalid.');
    }
    // Verify client geohash is consistent with coordinates (prefix match)
    if (!p.geohash.startsWith(computedGeohash) && !computedGeohash.startsWith(p.geohash)) {
      throw new HttpsError(
        'invalid-argument',
        'Client-supplied geohash does not match latitude/longitude coordinates.'
      );
    }
  }

  // 5. Access Type validation
  const validAccessTypes: Array<'free' | 'paid' | 'customer_only' | 'key_required'> = [
    'free',
    'paid',
    'customer_only',
    'key_required',
  ];
  if (!p.accessType || !validAccessTypes.includes(p.accessType)) {
    throw new HttpsError(
      'invalid-argument',
      `accessType must be one of: ${validAccessTypes.join(', ')}.`
    );
  }
  const accessType = p.accessType;

  // 6. Fee validation
  let feeAmount: number | null = null;
  let feeCurrency: string | null = null;
  if (accessType === 'paid') {
    if (typeof p.feeAmount !== 'number' || !Number.isFinite(p.feeAmount) || p.feeAmount < 0 || p.feeAmount > 1000000) {
      throw new HttpsError(
        'invalid-argument',
        'feeAmount is required for paid restrooms and must be between 0 and 1,000,000.'
      );
    }
    feeAmount = p.feeAmount;

    if (!p.feeCurrency || typeof p.feeCurrency !== 'string' || !/^[A-Z]{3}$/.test(p.feeCurrency.trim())) {
      throw new HttpsError(
        'invalid-argument',
        'feeCurrency is required for paid restrooms and must be a 3-letter uppercase currency code.'
      );
    }
    feeCurrency = p.feeCurrency.trim();
  } else {
    if (p.feeAmount !== undefined && p.feeAmount !== null) {
      throw new HttpsError('invalid-argument', 'feeAmount is prohibited for non-paid restrooms.');
    }
    if (p.feeCurrency !== undefined && p.feeCurrency !== null) {
      throw new HttpsError('invalid-argument', 'feeCurrency is prohibited for non-paid restrooms.');
    }
  }

  // 7. Stalls & Gender validation
  const male = validateOptionalNullableBool(p.male, 'male');
  const female = validateOptionalNullableBool(p.female, 'female');
  const allGender = validateOptionalNullableBool(p.allGender, 'allGender');

  const allUnknown = male === null && female === null && allGender === null;
  const hasPositive = male === true || female === true || allGender === true;
  if (!allUnknown && !hasPositive) {
    throw new HttpsError(
      'invalid-argument',
      'Invalid stall configuration: at least one gender stall must be true, or all three must be unknown.'
    );
  }

  // 8. Amenities validation
  const pwdAccessible = validateOptionalNullableBool(p.pwdAccessible, 'pwdAccessible');
  const babyChanging = validateOptionalNullableBool(p.babyChanging, 'babyChanging');
  const hasBidet = validateOptionalNullableBool(p.hasBidet, 'hasBidet');
  const hasToiletPaper = validateOptionalNullableBool(p.hasToiletPaper, 'hasToiletPaper');
  const hasSoap = validateOptionalNullableBool(p.hasSoap, 'hasSoap');
  const hasHandDryer = validateOptionalNullableBool(p.hasHandDryer, 'hasHandDryer');

  // 9. Indoor Context Strings
  const countryCode = validateOptionalString(p.countryCode, 'countryCode', 2, 3);
  const region = validateOptionalString(p.region, 'region', 1, 100);
  const city = validateOptionalString(p.city, 'city', 1, 100);
  const buildingName = validateOptionalString(p.buildingName, 'buildingName', 1, 100);
  const buildingSection = validateOptionalString(p.buildingSection, 'buildingSection', 1, 100);
  const floor = validateOptionalString(p.floor, 'floor', 1, 20);
  const unitOrArea = validateOptionalString(p.unitOrArea, 'unitOrArea', 1, 100);
  const landmark = validateOptionalString(p.landmark, 'landmark', 1, 100);
  const directionsNote = validateOptionalString(p.directionsNote, 'directionsNote', 1, 500);
  const accessInstructions = validateOptionalString(p.accessInstructions, 'accessInstructions', 1, 300);

  return {
    restroomId,
    name,
    latitude: p.latitude,
    longitude: p.longitude,
    geohash: computedGeohash,
    accessType,
    countryCode,
    region,
    city,
    buildingName,
    buildingSection,
    floor,
    unitOrArea,
    landmark,
    directionsNote,
    accessInstructions,
    feeAmount,
    feeCurrency,
    male,
    female,
    allGender,
    pwdAccessible,
    babyChanging,
    hasBidet,
    hasToiletPaper,
    hasSoap,
    hasHandDryer,
  };
}
