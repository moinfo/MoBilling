/**
 * Read a safe post-login redirect from a query string's ?next= parameter.
 *
 * Visitors arriving from moinfo.co.tz at /order/* are bounced through login,
 * and ?next= carries the plan they picked so they land back on it. Only
 * same-site absolute paths are honoured — anything scheme- or
 * protocol-relative is discarded so ?next= can't become an open redirect.
 */
export function safeNext(search: string): string | null {
  const raw = new URLSearchParams(search).get('next');
  if (!raw) return null;
  if (!raw.startsWith('/') || raw.startsWith('//')) return null;
  return raw;
}