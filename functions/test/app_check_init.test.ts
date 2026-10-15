process.env.NODE_ENV = 'test';
process.env.APP_ENV = 'test';

import { describe, it } from 'node:test';
import * as assert from 'node:assert/strict';
import { getAppConfig } from '../src/config';
import { createSubmitRestroom } from '../src/submit_restroom';

/**
 * Isolated unit test verifying Cloud Functions V2 SDK-level App Check enforcement
 * during initialization for staging and production environments.
 *
 * This test verifies the SDK declaration contract:
 *   onCall({ enforceAppCheck: true }, handler)
 *
 * It proves that the Firebase Functions runtime rejects incoming callable requests
 * lacking a valid App Check token at the HTTP transport/ingress layer with
 * HTTP 401 (UNAUTHENTICATED) before any application handler code is executed.
 */
describe('P2.6-C — App Check Callable Initialization Contract', () => {
  interface MockHttpResponse {
    statusCode: number | null;
    body: Record<string, unknown> | null;
  }

  function dispatchMockCallableRequest(
    callable: (req: unknown, res: unknown) => Promise<unknown>,
    headers: Record<string, string> = {}
  ): Promise<MockHttpResponse> {
    const normalizedHeaders: Record<string, string> = {
      'content-type': 'application/json',
      ...headers,
    };

    const req = {
      method: 'POST',
      headers: normalizedHeaders,
      header(name: string) {
        return this.headers[name.toLowerCase()];
      },
      body: { data: {} },
    };

    let statusCode: number | null = null;
    let body: Record<string, unknown> | null = null;

    const res = {
      setHeader() {},
      getHeader() {},
      status(code: number) {
        statusCode = code;
        return this;
      },
      send(data: Record<string, unknown>) {
        body = data;
      },
      json(data: Record<string, unknown>) {
        body = data;
      },
      on(event: string, callback: () => void) {
        if (event === 'finish') {
          setImmediate(callback);
        }
      },
    };

    return callable(req, res).then(() => ({ statusCode, body }));
  }

  it('Staging environment initializes callable with SDK-level App Check enforcement enabled', async () => {
    const savedAppEnv = process.env.APP_ENV;
    const savedEnforce = process.env.ENFORCE_APP_CHECK;

    try {
      process.env.APP_ENV = 'staging';
      delete process.env.ENFORCE_APP_CHECK;

      const config = getAppConfig();
      assert.equal(config.appEnv, 'staging');
      assert.equal(config.enforceAppCheck, true);

      // Create callable endpoint with staging configuration
      const stagingCallable = createSubmitRestroom(config);

      // Request without X-Firebase-AppCheck header must be rejected at the SDK layer
      const response = await dispatchMockCallableRequest(stagingCallable as any);

      // Firebase Functions SDK responds with HTTP 401 and UNAUTHENTICATED error
      assert.equal(response.statusCode, 401);
      assert.ok(response.body);
      const errorObj = (response.body as any).error;
      assert.equal(errorObj?.status, 'UNAUTHENTICATED');
      assert.equal(errorObj?.message, 'Unauthenticated');
    } finally {
      process.env.APP_ENV = savedAppEnv;
      if (savedEnforce !== undefined) {
        process.env.ENFORCE_APP_CHECK = savedEnforce;
      } else {
        delete process.env.ENFORCE_APP_CHECK;
      }
    }
  });

  it('Production environment initializes callable with SDK-level App Check enforcement enabled', async () => {
    const savedAppEnv = process.env.APP_ENV;
    const savedEnforce = process.env.ENFORCE_APP_CHECK;

    try {
      process.env.APP_ENV = 'production';
      delete process.env.ENFORCE_APP_CHECK;

      const config = getAppConfig();
      assert.equal(config.appEnv, 'production');
      assert.equal(config.enforceAppCheck, true);

      // Create callable endpoint with production configuration
      const prodCallable = createSubmitRestroom(config);

      // Request without X-Firebase-AppCheck header must be rejected at the SDK layer
      const response = await dispatchMockCallableRequest(prodCallable as any);

      assert.equal(response.statusCode, 401);
      assert.ok(response.body);
      const errorObj = (response.body as any).error;
      assert.equal(errorObj?.status, 'UNAUTHENTICATED');
      assert.equal(errorObj?.message, 'Unauthenticated');
    } finally {
      process.env.APP_ENV = savedAppEnv;
      if (savedEnforce !== undefined) {
        process.env.ENFORCE_APP_CHECK = savedEnforce;
      } else {
        delete process.env.ENFORCE_APP_CHECK;
      }
    }
  });

  it('Development environment with enforceAppCheck=false allows SDK-level pass-through', async () => {
    const savedAppEnv = process.env.APP_ENV;
    const savedEnforce = process.env.ENFORCE_APP_CHECK;

    try {
      process.env.APP_ENV = 'development';
      process.env.ENFORCE_APP_CHECK = 'false';

      const config = getAppConfig();
      assert.equal(config.appEnv, 'development');
      assert.equal(config.enforceAppCheck, false);

      const devCallable = createSubmitRestroom(config);

      // Request without X-Firebase-AppCheck header is NOT rejected by SDK App Check
      const response = await dispatchMockCallableRequest(devCallable as any);

      // In development with enforceAppCheck=false, the SDK does not block the request at ingress.
      // The request passes into the application handler, which evaluates caller authentication
      // and throws the application-level message ('User must be authenticated anonymously.'),
      // proving that the SDK App Check gate was NOT engaged.
      assert.ok(response.body);
      const errorObj = (response.body as any).error;
      assert.equal(errorObj?.status, 'UNAUTHENTICATED');
      assert.equal(errorObj?.message, 'User must be authenticated anonymously.');
    } finally {
      process.env.APP_ENV = savedAppEnv;
      if (savedEnforce !== undefined) {
        process.env.ENFORCE_APP_CHECK = savedEnforce;
      } else {
        delete process.env.ENFORCE_APP_CHECK;
      }
    }
  });

  it('Staging and Production configurations strictly reject attempts to disable App Check', () => {
    const savedAppEnv = process.env.APP_ENV;
    const savedEnforce = process.env.ENFORCE_APP_CHECK;

    try {
      process.env.APP_ENV = 'staging';
      process.env.ENFORCE_APP_CHECK = 'false';
      assert.throws(
        () => getAppConfig(),
        /Cannot disable App Check.*in staging/
      );

      process.env.APP_ENV = 'production';
      process.env.ENFORCE_APP_CHECK = 'false';
      assert.throws(
        () => getAppConfig(),
        /Cannot disable App Check.*in production/
      );
    } finally {
      process.env.APP_ENV = savedAppEnv;
      if (savedEnforce !== undefined) {
        process.env.ENFORCE_APP_CHECK = savedEnforce;
      } else {
        delete process.env.ENFORCE_APP_CHECK;
      }
    }
  });

  it('Staging environment strictly validates project ID flushcrowd-staging in live runtime', () => {
    const savedAppEnv = process.env.APP_ENV;
    const savedNodeEnv = process.env.NODE_ENV;
    const savedGcloud = process.env.GCLOUD_PROJECT;
    const savedEmulator = process.env.FUNCTIONS_EMULATOR;
    const savedFirestoreHost = process.env.FIRESTORE_EMULATOR_HOST;

    try {
      process.env.APP_ENV = 'staging';
      delete process.env.NODE_ENV;
      delete process.env.FUNCTIONS_EMULATOR;
      delete process.env.FIRESTORE_EMULATOR_HOST;

      // When GCLOUD_PROJECT is incorrect, it must fail closed
      process.env.GCLOUD_PROJECT = 'wrong-project-id';
      assert.throws(
        () => getAppConfig(),
        /Staging environment targeted invalid project "wrong-project-id"/
      );

      // When GCLOUD_PROJECT is 'flushcrowd-staging', it succeeds
      process.env.GCLOUD_PROJECT = 'flushcrowd-staging';
      const config = getAppConfig();
      assert.equal(config.appEnv, 'staging');
      assert.equal(config.enforceAppCheck, true);
    } finally {
      process.env.APP_ENV = savedAppEnv;
      if (savedNodeEnv !== undefined) process.env.NODE_ENV = savedNodeEnv;
      else delete process.env.NODE_ENV;
      if (savedGcloud !== undefined) process.env.GCLOUD_PROJECT = savedGcloud;
      else delete process.env.GCLOUD_PROJECT;
      if (savedEmulator !== undefined) process.env.FUNCTIONS_EMULATOR = savedEmulator;
      else delete process.env.FUNCTIONS_EMULATOR;
      if (savedFirestoreHost !== undefined) process.env.FIRESTORE_EMULATOR_HOST = savedFirestoreHost;
      else delete process.env.FIRESTORE_EMULATOR_HOST;
    }
  });
});
