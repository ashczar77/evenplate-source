import { documents } from "./content.ts";

const titles = { privacy: 'Privacy Policy', terms: 'Terms of Use', support: 'Support' };

Deno.serve((request) => {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, HEAD' } });
  }
  const document = new URL(request.url).searchParams.get('document') ?? 'privacy';
  if (!['privacy', 'terms', 'support'].includes(document)) return new Response('Not found', { status: 404 });
  const key = document as keyof typeof documents;
  const body = `EvenPlate ${titles[key]}\n\n${documents[key]}\n\nContact: evenplatesupport@gmail.com\n`;
  return new Response(request.method === 'HEAD' ? null : body, { headers: {
    'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'public, max-age=300',
    'Content-Security-Policy': "default-src 'none'; base-uri 'none'; frame-ancestors 'none'",
    'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
  } });
});
