import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import test from 'node:test';

const source = await readFile(new URL('../worker/index.js', import.meta.url), 'utf8');
const pages = JSON.parse(source.split('\n')[0].slice('const PAGES='.length, -1));

function fixture({ failSettings = false, factorStatus = 'verified', verifyError = null, eligible = true } = {}) {
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) elements.set(id, { value: '', hidden: false, checked: false, textContent: '', handlers: {}, addEventListener(name, callback) { this.handlers[name] = callback; }, replaceChildren() {} });
    return elements.get(id);
  };
  const calls = [];
  const documentHandlers = {};
  const document = { hidden: false, getElementById: element, querySelector: () => ({ content: '/console/config.json' }), querySelectorAll: () => [], addEventListener(name, callback) { documentHandlers[name] = callback; } };
  const context = vm.createContext({
    document,
    window: { addEventListener() {} }, Date, Error, TypeError,
    fetch: async (url, options = {}) => {
      const body = options.body ? JSON.parse(options.body) : null;
      calls.push({ url, body, options });
      if (failSettings && url.endsWith('/auth/v1/settings')) throw new TypeError('Failed to fetch');
      if (url === '/console/config.json') return { ok: true, json: async () => ({ url: 'https://auth.invalid', anon_key: 'public-fixture' }) };
      let data = {};
      if (url.endsWith('/mefrion_operator_login_eligible')) data = eligible;
      if (url.endsWith('/auth/v1/verify')) data = { access_token: 'fixture-session', expires_in: 1800 };
      if (url.endsWith('/auth/v1/user')) data = { factors: [{ factor_type: 'totp', status: factorStatus, id: 'factor-fixture' }] };
      if (url.endsWith('/challenge')) data = { id: 'challenge-fixture' };
      if (url.endsWith('/factors/factor-fixture/verify')) data = { access_token: 'fixture-aal2-session', expires_in: 1800 };
      let status = url.endsWith('/mefrion_operator_queue') ? 403 : 200;
      if (verifyError && url.endsWith('/factors/factor-fixture/verify')) { status = 422; data = { code: verifyError }; }
      return { ok: status === 200, status, json: async () => data };
    },
  });
  vm.runInContext(pages['/console/cloud.js'].body, context);
  const trigger = async (id, type = 'submit') => {
    element(id).handlers[type]({ preventDefault() {} });
    for (let i = 0; i < 10; i++) await new Promise(resolve => setImmediate(resolve));
  };
  return { element, calls, trigger, context, document, documentHandlers };
}

async function loginFixture(f) {
  await f.trigger('email-login-toggle', 'click');
  f.element('otp-consent').checked = true;
  f.element('otp-email').value = 'owner@example.invalid';
  await f.trigger('email-login');
  f.element('email-code').value = '000000';
  await f.trigger('email-verify');
}

test('email login requires consent and does not send a request before user submission', async () => {
  const f = fixture();
  assert.equal(f.calls.length, 0);
  await f.trigger('email-login-toggle', 'click');
  await f.trigger('email-login');
  assert.equal(f.calls.length, 0);
  assert.match(f.element('status').textContent, /利用条件/);
});
test('email code flow retains mandatory MFA and cannot self-grant moderator access', async () => {
  const f = fixture();
  await f.trigger('email-login-toggle', 'click');
  f.element('otp-consent').checked = true;
  f.element('otp-email').value = 'owner@example.invalid';
  await f.trigger('email-login');
  assert.equal(f.element('email-verify').hidden, false);
  const otp = f.calls.find(call => call.url.endsWith('/auth/v1/otp'));
  assert.equal(otp.body.create_user, true);
  f.element('email-code').value = '000000';
  await f.trigger('email-verify');
  assert.equal(f.element('email-code').value, '');
  assert.equal(f.element('mfa').hidden, false);
  assert.equal(f.calls.some(call => call.url.includes('operator_queue')), false);
  f.element('code').value = '000000';
  await f.trigger('mfa');
  assert.match(f.element('status').textContent, /運営権限の有効化をお待ち/);
  assert.equal(f.element('session').hidden, false);
  assert.equal(f.calls.some(call => call.url.includes('set_operator')), false);
  assert.equal(vm.runInContext('token', f.context), 'fixture-aal2-session');
  await f.trigger('cancel-login', 'click');
  assert.equal(vm.runInContext('token', f.context), null);
  assert.equal(vm.runInContext('pendingEmail', f.context), null);
});

test('connectivity check sends no mail and cannot create an account', async () => {
  const f = fixture();
  await f.trigger('check-connection', 'click');
  assert.match(f.element('status').textContent, /通信を確認できました/);
  const probe = f.calls.find(call => call.url.endsWith('/auth/v1/otp'));
  assert.equal(probe.body.create_user, false);
  assert.equal(probe.body.email, 'mefrion-connectivity-check@example.invalid');
  assert.equal(f.calls.some(call => call.url.includes('verify')), false);
});

test('network failure has a readable recovery instruction', async () => {
  const f = fixture({ failSettings: true });
  await f.trigger('check-connection', 'click');
  assert.match(f.element('status').textContent, /もう一度/);
  assert.doesNotMatch(f.element('status').textContent, /Failed to fetch/);
  assert.equal(f.calls.some(call => call.url.endsWith('/auth/v1/otp')), false);
});

test('pending enrollment resumes after re-login without creating another factor', async () => {
  const f = fixture({ factorStatus: 'unverified' });
  await loginFixture(f);
  assert.equal(f.element('mfa').hidden, false);
  assert.equal(f.element('restart-enroll').hidden, false);
  assert.match(f.element('status').textContent, /確認待ち/);
  assert.equal(f.calls.some(call => call.url.endsWith('/auth/v1/factors')), false);
});

test('invalid MFA input gives feedback before any verification request', async () => {
  const f = fixture(); await loginFixture(f);
  f.element('code').value = '12345678';
  await f.trigger('mfa');
  assert.match(f.element('status').textContent, /メールの確認コードとは別/);
  assert.equal(f.calls.some(call => call.url.endsWith('/challenge')), false);
});

test('normalizes full-width digits and spaces before verifying', async () => {
  const f = fixture(); await loginFixture(f);
  f.element('code').value = '０１２ ３４５';
  await f.trigger('mfa');
  const verify = f.calls.find(call => call.url.endsWith('/factors/factor-fixture/verify'));
  assert.equal(verify.body.code, '012345');
  assert.match(f.element('status').textContent, /二段階認証が完了/);
});

for (const [code, message] of [['mfa_verification_failed', /コードが一致しません/], ['mfa_challenge_expired', /期限が切れました/], ['mfa_ip_address_mismatch', /通信経路/]]) {
  test(`MFA error ${code} is actionable and keeps the primary session`, async () => {
    const f = fixture({ verifyError: code }); await loginFixture(f);
    f.element('code').value = '000000';
    await f.trigger('mfa');
    assert.match(f.element('status').textContent, message);
    assert.equal(vm.runInContext('token', f.context), 'fixture-session');
    assert.equal(vm.runInContext('mfaComplete', f.context), false);
    assert.equal(f.calls.some(call => call.url.includes('operator_queue')), false);
  });
}

test('returning from authenticator does not fetch privileged data before MFA', async () => {
  const f = fixture({ factorStatus: 'unverified' }); await loginFixture(f);
  const before = f.calls.length;
  f.documentHandlers.visibilitychange();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.calls.length, before);
});

test('restart button cannot unenroll an already verified factor', async () => {
  const f = fixture(); await loginFixture(f);
  await f.trigger('restart-enroll', 'click');
  assert.equal(f.calls.some(call => call.options.method === 'DELETE'), false);
  assert.match(f.element('status').textContent, /登録状態が変わりました/);
});


test('non-operator email is stopped before MFA enrollment and credentials are cleared', async () => {
 const f = fixture({ eligible: false });
 await loginFixture(f);
 assert.match(f.element('status').textContent, /運営専用のメールアドレス/);
 assert.equal(f.calls.some(call => call.url.endsWith('/auth/v1/user')), false);
 assert.equal(f.calls.some(call => call.url.endsWith('/auth/v1/factors')), false);
 assert.equal(vm.runInContext('token', f.context), null);
 assert.equal(f.element('mfa').hidden, true);
});
