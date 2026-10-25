import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import test from 'node:test';

const source = await readFile(new URL('../worker/index.js', import.meta.url), 'utf8');
const pages = JSON.parse(source.split('\n')[0].slice('const PAGES='.length, -1));

function fixture() {
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) elements.set(id, { value: '', hidden: false, checked: false, textContent: '', handlers: {}, addEventListener(name, callback) { this.handlers[name] = callback; }, replaceChildren() {} });
    return elements.get(id);
  };
  const calls = [];
  const context = vm.createContext({
    document: { getElementById: element, querySelector: () => ({ content: '/console/config.json' }), querySelectorAll: () => [], addEventListener() {} },
    window: { addEventListener() {} }, Date, Error,
    fetch: async (url, options = {}) => {
      const body = options.body ? JSON.parse(options.body) : null;
      calls.push({ url, body, options });
      if (url === '/console/config.json') return { ok: true, json: async () => ({ url: 'https://auth.invalid', anon_key: 'public-fixture' }) };
      let data = {};
      if (url.endsWith('/auth/v1/verify')) data = { access_token: 'fixture-session', expires_in: 1800 };
      if (url.endsWith('/auth/v1/user')) data = { factors: [{ factor_type: 'totp', status: 'verified', id: 'factor-fixture' }] };
      if (url.endsWith('/challenge')) data = { id: 'challenge-fixture' };
      if (url.endsWith('/factors/factor-fixture/verify')) data = { access_token: 'fixture-aal2-session', expires_in: 1800 };
      const status = url.endsWith('/mefrion_operator_queue') ? 403 : 200;
      return { ok: status === 200, status, json: async () => data };
    },
  });
  vm.runInContext(pages['/console/cloud.js'].body, context);
  const trigger = async (id, type = 'submit') => {
    element(id).handlers[type]({ preventDefault() {} });
    for (let i = 0; i < 10; i++) await new Promise(resolve => setImmediate(resolve));
  };
  return { element, calls, trigger, context };
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
