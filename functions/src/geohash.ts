const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/**
 * Encodes latitude and longitude into a standard base32 geohash string.
 * Matches FlushCrowd Dart GeohashService implementation exactly.
 */
export function encodeGeohash(
  latitude: number,
  longitude: number,
  precision: number = 6
): string {
  if (precision < 1 || precision > 12) {
    throw new Error('Geohash precision must be between 1 and 12');
  }

  let minLat = -90.0;
  let maxLat = 90.0;
  let minLng = -180.0;
  let maxLng = 180.0;

  let result = '';
  let isEven = true;
  let bit = 0;
  let ch = 0;

  while (result.length < precision) {
    if (isEven) {
      const mid = (minLng + maxLng) / 2.0;
      if (longitude > mid) {
        ch |= 1 << (4 - bit);
        minLng = mid;
      } else {
        maxLng = mid;
      }
    } else {
      const mid = (minLat + maxLat) / 2.0;
      if (latitude > mid) {
        ch |= 1 << (4 - bit);
        minLat = mid;
      } else {
        maxLat = mid;
      }
    }

    isEven = !isEven;
    if (bit < 4) {
      bit++;
    } else {
      result += BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }

  return result;
}

/**
 * Validates whether a geohash string matches canonical geohash format.
 */
export function isValidGeohashFormat(geohash: string): boolean {
  return (
    typeof geohash === 'string' &&
    geohash.length >= 4 &&
    geohash.length <= 12 &&
    /^[0-9bcdefghjkmnpqrstuvwxyz]{4,12}$/.test(geohash)
  );
}
