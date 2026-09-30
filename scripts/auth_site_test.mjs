import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readLink, passwordError, createAuth, endpoint} from '../docs/auth/core.mjs';
const hash = 'a'.repeat(64);
test('only supported actions and valid hashes are accepted', () => {
  assert.equal(readLink('?type=invite&token_hash='+hash), null);
  assert.equal(readLink('?type=email&token_hash=short'), null);
  assert.equal(readLink('?type=recovery&token_hash='+hash).type, 'recovery');
});
test('native redirect cannot point to an attacker or another callback', () => {
  const link = native => readLink('?type=recovery&token_hash='+hash+'&confirmation_url='+encodeURIComponent(native));
  assert.equal(link('https://attacker.example/auth/v1/verify').native, null);
  assert.equal(link(endpoint+'/auth/v1/verify?type=recovery&redirect_to=https://attacker.example').native, null);
  const valid = endpoint+'/auth/v1/verify?type=recovery&token='+hash+'&redirect_to=evenplate%3A%2F%2Fauth-callback';
  assert.equal(link(valid).native, valid);
});
test('loading and parsing do not consume a token', () => {
  let calls = 0;
  createAuth('public-test-key', () => {calls++;});
  readLink('?type=email&token_hash='+hash);
  assert.equal(calls, 0);
});
test('verify and password update send the correct scoped credentials', async () => {
  const calls = [];
  const auth = createAuth('public-test-key', async (url, options) => {
    calls.push({url, options});
    return {ok:true, json: async () => ({access_token:'session-fixture'})};
  });
  await auth.verify({hash, type:'recovery'});
  await auth.update('FixturePassword9!', 'session-fixture');
  assert.deepEqual(JSON.parse(calls[0].options.body), {token_hash:hash, type:'recovery'});
  assert.equal(calls[0].options.headers.Authorization, undefined);
  assert.equal(calls[1].options.headers.Authorization, 'Bearer session-fixture');
  assert.equal(calls[1].options.referrerPolicy, 'no-referrer');
  assert.equal(calls[1].options.credentials, 'omit');
});
test('failed updates reject rather than claim success or reveal server messages', async () => {
  const auth = createAuth('public-test-key', async () => ({ok:false,json:async()=>({code:'same_password',message:'sensitive server fixture'})}));
  await assert.rejects(auth.update('FixturePassword9!', 'session-fixture'), e => e.code === 'same_password' && !e.message.includes('sensitive'));
});
test('password strength and confirmation are required', () => {
  assert.ok(passwordError('weak', 'weak'));
  assert.ok(passwordError('FixturePassword9!', 'different'));
  assert.equal(passwordError('FixturePassword9!', 'FixturePassword9!'), null);
});
