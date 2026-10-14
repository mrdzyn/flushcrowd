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

  return {
    appEnv,
    enforceAppCheck,
  };
}
