<?php

namespace App\Http\Controllers;

use App\Models\Tenant;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

/**
 * Serves link-preview crawlers (WhatsApp, Facebook, Twitter, Telegram, ...) a
 * server-rendered copy of the SPA shell with the right tenant's own name/logo
 * in <title>, favicon and Open Graph tags.
 *
 * These bots never run JavaScript, so the in-app branding swap (branding.ts,
 * applyFavicon()) never reaches them — they only ever see index.html exactly
 * as built, which is one static file shared by every host. Real browsers
 * never reach this route at all: nginx only rewrites here for known crawler
 * user-agents (see the site configs), so this has zero effect on real
 * visitors or on page-load performance.
 */
class LinkPreviewController extends Controller
{
    public function show(Request $request): Response
    {
        $host = strtolower(trim($request->getHost()));
        $tenant = Tenant::where('custom_domain', $host)->where('is_active', true)->first();

        // mobilling-ui is a sibling directory of this Laravel app.
        $distIndex = base_path('../mobilling-ui/dist/index.html');
        if (!is_file($distIndex)) {
            abort(404);
        }
        $html = file_get_contents($distIndex);

        $name = $tenant->name ?? 'MoBilling';
        // Default host (no tenant match) keeps Moinfotech's own logo — same
        // fallback the static file already shipped, just also used for og:image.
        $logo = $tenant?->logo_url ?: ('https://' . $request->getHost() . '/moinfotech-logo.png');
        $description = $tenant
            ? "{$tenant->name} — domains, hosting and business email."
            : 'MoBilling — billing, hosting and domain management.';
        $url = 'https://' . $host . $request->getRequestUri();

        $meta = '<title>' . e($name) . "</title>\n";
        $meta .= '<link rel="icon" type="image/png" href="' . e($logo) . "\">\n";
        $meta .= '<meta property="og:image" content="' . e($logo) . "\">\n";
        $meta .= '<meta property="og:title" content="' . e($name) . "\">\n";
        $meta .= '<meta property="og:description" content="' . e($description) . "\">\n";
        $meta .= '<meta property="og:url" content="' . e($url) . "\">\n";
        $meta .= "<meta property=\"og:type\" content=\"website\">\n";
        $meta .= "<meta name=\"twitter:card\" content=\"summary\">\n";

        // Strip the static <title> and favicon so there's exactly one of
        // each, then inject the tenant-aware versions right before </head>.
        $html = preg_replace('#<title>.*?</title>#s', '', $html, 1);
        $html = preg_replace('#<link rel="icon"[^>]*>#s', '', $html, 1);
        $html = str_replace('</head>', $meta . '</head>', $html);

        return response($html, 200)->header('Content-Type', 'text/html; charset=UTF-8');
    }
}
