export type AppEnvironment = 'development' | 'staging' | 'production' | 'test';

export interface AppConfig {
  appEnv: AppEnvironment;
  enforceAppCheck: boolean;
}

/**
 * Loads and validates runtime security and environment configuration.
 * Fails closed if production or staging environments lack required security configuration.
 */
export function getAppConfig(): AppConfig {
  const isTestOrEmulator =
    process.env.NODE_ENV === 'test' ||
    process.env.FUNCTIONS_EMULATOR === 'true' ||
    process.env.FIRESTORE_EMULATOR_HOST !== undefined;

  const rawEnv = process.env.APP_ENV ?? (isTestOrEmulator ? 'test' : undefined);

  if (!rawEnv) {
    throw new Error(
      'FATAL: APP_ENV environment variable is missing. ' +
      'Explicit configuration (development | staging | production | test) is required. ' +
      'Unconfigured environments fail closed.'
    );
  }

  const validEnvs: AppEnvironment[] = ['development', 'staging', 'production', 'test'];
  if (!validEnvs.includes(rawEnv as AppEnvironment)) {
    throw new Error(
      `FATAL: Invalid APP_ENV="${rawEnv}". Must be one of: ${validEnvs.join(', ')}.`
    );
  }

  const appEnv = rawEnv as AppEnvironment;

  // Staging and Production FAIL CLOSED: App Check is mandatory
  let enforceAppCheck: boolean;
  if (appEnv === 'production' || appEnv === 'staging') {
    if (process.env.ENFORCE_APP_CHECK === 'false') {
      throw new Error(
        `FATAL: Cannot disable App Check (ENFORCE_APP_CHECK=false) in ${appEnv} environment.`
      );
    }
    enforceAppCheck = true;
  } else if (appEnv === 'test') {
    enforceAppCheck = process.env.ENFORCE_APP_CHECK === 'true';
  } else {
    // development: opt-in via ENFORCE_APP_CHECK=true
    enforceAppCheck = process.env.ENFORCE_APP_CHECK === 'true';
  }

  // Explicit project ID validation: staging runtime must target 'flushcrowd-staging'
  const runtimeProjectId =
    process.env.GCLOUD_PROJECT ??
    process.env.PROJECT_ID ??
    (process.env.FIREBASE_CONFIG
      ? (() => {
          try {
            return JSON.parse(process.env.FIREBASE_CONFIG).projectId;
          } catch {
            return undefined;
          }
        })()
      : undefined);

  if (!isTestOrEmulator) {
    if (appEnv === 'staging') {
      if (!runtimeProjectId) {
        throw new Error(
          'FATAL: Live staging environment is missing project identity (GCLOUD_PROJECT, PROJECT_ID, or FIREBASE_CONFIG.projectId). ' +
          'Expected "flushcrowd-staging".'
        );
      }
      if (runtimeProjectId !== 'flushcrowd-staging') {
        throw new Error(
          `FATAL: Staging environment targeted invalid project "${runtimeProjectId}". Expected "flushcrowd-staging".`
        );
      }
    } else if (appEnv === 'production') {
      if (!runtimeProjectId) {
        throw new Error(
          'FATAL: Live production environment is missing project identity (GCLOUD_PROJECT, PROJECT_ID, or FIREBASE_CONFIG.projectId).'
        );
      }
      if (runtimeProjectId === 'flushcrowd-staging') {
        throw new Error(
          'FATAL: Production environment targeted staging project "flushcrowd-staging". Refusing to initialize.'
        );
      }
    }
  }

  return {
    appEnv,
    enforceAppCheck,
  };
}
