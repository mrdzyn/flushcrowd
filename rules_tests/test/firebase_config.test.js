import fs from 'node:fs';
import path from 'node:path';
import { describe, it } from 'node:test';
import * as assert from 'node:assert/strict';

/**
 * Automated configuration-level validation verifying that:
 * 1. Default firebase.json selects original staging rules (firestore.rules)
 * 2. Cutover firebase.cutover.json selects restrictive production candidate rules (firestore.production.rules)
 * 3. Configuration parity is maintained across functions and emulators definitions
 * 4. Staging environment file (.env.flushcrowd-staging) exists and declares APP_ENV=staging
 */
describe('P2.6-QA — Deterministic Firebase Configuration Selection', () => {
  const rootDir = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../../');

  it('Default firebase.json selects firestore.rules for staging operations', () => {
    const configPath = path.join(rootDir, 'firebase.json');
    assert.ok(fs.existsSync(configPath), 'firebase.json must exist in project root');

    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    assert.ok(config.firestore, 'firebase.json must contain firestore configuration');
    assert.equal(
      config.firestore.rules,
      'firestore.rules',
      'firebase.json must target firestore.rules for staging direct-write operations'
    );
    assert.equal(config.firestore.indexes, 'firestore.indexes.json');
  });

  it('Cutover firebase.cutover.json selects firestore.production.rules for lockdown', () => {
    const cutoverPath = path.join(rootDir, 'firebase.cutover.json');
    assert.ok(fs.existsSync(cutoverPath), 'firebase.cutover.json must exist in project root');

    const config = JSON.parse(fs.readFileSync(cutoverPath, 'utf8'));
    assert.ok(config.firestore, 'firebase.cutover.json must contain firestore configuration');
    assert.equal(
      config.firestore.rules,
      'firestore.production.rules',
      'firebase.cutover.json must target firestore.production.rules for production cutover'
    );
    assert.equal(config.firestore.indexes, 'firestore.indexes.json');
  });

  it('firebase.json and firebase.cutover.json maintain configuration parity across non-rules blocks', () => {
    const defaultConfig = JSON.parse(fs.readFileSync(path.join(rootDir, 'firebase.json'), 'utf8'));
    const cutoverConfig = JSON.parse(fs.readFileSync(path.join(rootDir, 'firebase.cutover.json'), 'utf8'));

    assert.deepEqual(
      defaultConfig.functions,
      cutoverConfig.functions,
      'Functions deployment block must be identical between default and cutover configs'
    );
    assert.deepEqual(
      defaultConfig.emulators,
      cutoverConfig.emulators,
      'Emulators block must be identical between default and cutover configs'
    );
  });

  it('firestore.rules retains permissive direct-write verification rules for staging development', () => {
    const rulesContent = fs.readFileSync(path.join(rootDir, 'firestore.rules'), 'utf8');

    assert.ok(
      rulesContent.includes('function isValidRestroomCreate('),
      'firestore.rules must contain isValidRestroomCreate function for staging client batch writes'
    );
    assert.ok(
      rulesContent.includes('function isValidContributionCreate('),
      'firestore.rules must contain isValidContributionCreate function for staging client batch writes'
    );
    assert.ok(
      !rulesContent.includes('match /restrooms/{restroomId} {\n    allow read: if true;\n    allow create: if false;'),
      'firestore.rules must NOT contain blanket client create denial on /restrooms'
    );
  });

  it('firestore.production.rules strictly disables direct client creation of restrooms and contributions', () => {
    const prodRulesContent = fs.readFileSync(path.join(rootDir, 'firestore.production.rules'), 'utf8');

    // Restrooms collection: read allowed, direct create/update/delete disabled
    assert.ok(
      prodRulesContent.includes('match /restrooms/{restroomId}'),
      'Must contain match /restrooms/{restroomId}'
    );
    assert.match(
      prodRulesContent,
      /match \/restrooms\/\{restroomId\}[\s\S]*?allow create: if false;/,
      'firestore.production.rules must deny direct client create on /restrooms'
    );

    // Contributions collection: read allowed for owner, direct create/update/delete disabled
    assert.ok(
      prodRulesContent.includes('match /contributions/{contributionId}'),
      'Must contain match /contributions/{contributionId}'
    );
    assert.match(
      prodRulesContent,
      /match \/contributions\/\{contributionId\}[\s\S]*?allow create: if false;/,
      'firestore.production.rules must deny direct client create on /contributions'
    );

    // Rate limits collection: strictly internal to Admin SDK
    assert.ok(
      prodRulesContent.includes('match /contributionRateLimits/{uid}'),
      'Must contain match /contributionRateLimits/{uid}'
    );
    assert.match(
      prodRulesContent,
      /match \/contributionRateLimits\/\{uid\}[\s\S]*?allow read, write: if false;/,
      'firestore.production.rules must deny client access to /contributionRateLimits'
    );
  });

  it('functions/.env.flushcrowd-staging provisions non-secret APP_ENV=staging for CLI and runtime', () => {
    const envPath = path.join(rootDir, 'functions/.env.flushcrowd-staging');
    assert.ok(fs.existsSync(envPath), 'functions/.env.flushcrowd-staging must exist');

    const envContent = fs.readFileSync(envPath, 'utf8');
    assert.match(
      envContent,
      /^APP_ENV=staging$/m,
      'functions/.env.flushcrowd-staging must explicitly declare APP_ENV=staging'
    );
  });
});
