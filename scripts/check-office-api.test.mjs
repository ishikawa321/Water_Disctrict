import { test } from 'node:test';
import assert from 'node:assert/strict';
import { officeApiOrigin } from './check-office-api.mjs';
test('Supabase REST is never configured as the ASP.NET workflow API', () => {
  assert.throws(() => officeApiOrigin('https://kaeespcylucvsazfdaks.supabase.co/rest/v1/'), /Supabase data API/);
});
test('only a public HTTPS origin without credentials or path is accepted', () => {
  assert.equal(officeApiOrigin('https://my-api.onrender.com/'),'https://my-api.onrender.com');
  for (const url of ['http://my-api.onrender.com','https://localhost','https://127.0.0.1','https://user:password@example.com','https://example.com/api','https://example.com/?token=secret','https://example.com/#secret','not a URL']) assert.throws(() => officeApiOrigin(url));
});
