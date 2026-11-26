import { pathToFileURL } from 'node:url';

export function officeApiOrigin(value) {
  let url;
  try { url = new URL(value); } catch { throw new Error('Enter the public HTTPS origin of the ASP.NET API.'); }
  if (url.hostname.endsWith('.supabase.co')) throw new Error('That is the Supabase data API. Use the separately hosted WaterDistrict.Api HTTPS address.');
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.pathname !== '/' || ['localhost','127.0.0.1','[::1]'].includes(url.hostname))
    throw new Error('Use a public HTTPS origin without credentials, query parameters, or an /api path.');
  return url.origin;
}

export async function checkOfficeApi(value) {
  const origin = officeApiOrigin(value);
  const get = path => fetch(origin + path, { redirect: 'error', signal: AbortSignal.timeout(70000), headers: { Accept: 'application/json' } });
  const live = await get('/health');
  const liveness = await live.json().catch(() => null);
  if (!live.ok || liveness?.service !== 'Water District API' || liveness?.status !== 'running') throw new Error('This address is not serving the shared WaterDistrict.Api health contract.');
  const [ready, session, capabilities] = await Promise.all([get('/health/ready'),get('/api/session'),get('/api/workflow/capabilities')]);
  const readiness = await ready.json().catch(() => null);
  if (!ready.ok || readiness?.status !== 'ready') throw new Error(`The API is online but its shared database is not ready (${readiness?.status ?? ready.status}). Configure the existing database connection and verify the reviewed migrations before connecting Vercel.`);
  if (session.status !== 401 || capabilities.status !== 401) throw new Error('The API must deny anonymous session and workflow requests with HTTP 401.');
  return { origin, status: 'ready', anonymousSession: session.status, anonymousCapabilities: capabilities.status };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { console.log(JSON.stringify(await checkOfficeApi(process.argv[2]), null, 2)); }
  catch (error) { console.error(error instanceof Error ? error.message : 'The office API check failed.'); process.exitCode = 1; }
}
