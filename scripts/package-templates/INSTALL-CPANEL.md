# Installing MoBilling on cPanel / shared hosting

Use this instead of `INSTALL.md` if you're on shared or reseller hosting
with cPanel and don't have root/SSH access to configure Nginx yourself.
The app itself is identical — only how you wire up the web server differs,
because cPanel gives one Apache document root per (sub)domain, while
MoBilling is really two things (the Laravel API and the built frontend)
that our own Nginx setup serves from two different roots on the same
domain. On cPanel we merge them into one folder instead, with a custom
`.htaccess` doing the routing Nginx's `location` blocks did for us.

## 1. Requirements

- PHP **8.2 or 8.3**, selectable in cPanel's **MultiPHP Manager** (or
  **Select PHP Version**) for the domain you're using.
- In that same PHP Selector page, under **Extensions**, confirm these are
  checked: `pdo_mysql`, `mbstring`, `openssl`, `bcmath`, `fileinfo`,
  `curl`. (`tokenizer`, `xml`, `ctype`, `json` are virtually always on by
  default.)
- MySQL/MariaDB — cPanel's own **MySQL Databases** tool.
- A domain, subdomain, or addon domain pointed at this hosting account.

## 2. Create the database

In cPanel → **MySQL Databases**:

1. Create a database, e.g. `mobilling` (cPanel will prefix it with your
   account username, e.g. `cpaneluser_mobilling` — that's normal, use the
   full prefixed name everywhere below).
2. Create a database user with a strong password.
3. Add that user to the database with **All Privileges**.

## 3. Upload and extract

In cPanel → **File Manager**, go to your home directory (one level above
`public_html`) — **not** into `public_html` itself, so the Laravel source
isn't nakedly web-accessible. Upload `mobilling-<version>.zip` there and
extract it. You should end up with something like:

```
~/mobilling-app/
  api/           <- Laravel backend
  public_html/   <- built frontend (NOT the cPanel public_html — same name, different folder)
  INSTALL.md
  INSTALL-CPANEL.md (this file)
```

(If your host only offers a File Manager with no zip-extract button, or
you do have Terminal access, `unzip mobilling-<version>.zip` works the
same from cPanel's **Terminal** app if it's enabled on your plan.)

## 4. Point a domain at it

Use a domain, subdomain, or addon domain dedicated to this install — don't
share one with an existing site. In cPanel → **Domains** (or **Subdomains**
/ **Addon Domains** depending on your cPanel version), when creating it,
set the **Document Root** directly to:

```
mobilling-app/api/public
```

If your cPanel version doesn't let you set a custom document root for the
domain, use the standard `public_html` (or the subdomain's default folder)
and symlink it instead — from Terminal, or ask your host to run:

```bash
rm -rf ~/public_html
ln -s ~/mobilling-app/api/public ~/public_html
```

Either way, the domain's document root must end up being
`mobilling-app/api/public` — that's Laravel's own public folder, which
we're about to merge the frontend into.

## 5. Merge the frontend into Laravel's public folder

Copy the built frontend's files into `api/public` (there are no filename
clashes — Laravel's `public/` has `index.php`, `.htaccess`, `favicon.ico`,
`robots.txt`, `storage`; the frontend build has `index.html`, `assets/`,
`sitemap.xml`, `vite.svg`, a logo image):

```bash
cp -r ~/mobilling-app/public_html/* ~/mobilling-app/api/public/
```

(In File Manager: open the `public_html` folder from step 3, select
everything inside it, Copy, paste into `api/public`.)

Now **replace** `api/public/.htaccess` with this — it's Laravel's default
rewrite rules, extended to hand anything under `/api`, `/sanctum`, or
`/storage` to Laravel's `index.php`, and everything else that isn't a real
file to the frontend's `index.html` (so client-side routes like
`/dashboard` or `/install` load the React app, which then makes its own
`/api/...` calls that this same file routes correctly):

```apache
<IfModule mod_rewrite.c>
    <IfModule mod_negotiation.c>
        Options -MultiViews -Indexes
    </IfModule>

    RewriteEngine On

    # Forward the Authorization header (Laravel/Sanctum need this)
    RewriteCond %{HTTP:Authorization} .
    RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

    # Redirect trailing slashes if not a real folder
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteCond %{REQUEST_URI} (.+)/$
    RewriteRule ^ %1 [L,R=301]

    # A real file on disk (frontend assets, favicon, uploaded files via
    # the storage symlink, etc.) — serve it directly, skip everything below.
    RewriteCond %{REQUEST_FILENAME} -f
    RewriteRule ^ - [L]

    # /api, /sanctum, /storage with no matching file — Laravel's front controller.
    RewriteCond %{REQUEST_URI} ^/(api|sanctum|storage)(/|$)
    RewriteRule ^ index.php [L]

    # Everything else — the frontend's SPA shell.
    RewriteRule ^ index.html [L]
</IfModule>
```

Leave `~/mobilling-app/public_html` (the pre-merge copy) in place until
you've confirmed the site works, then you can delete it.

## 6. Permissions

In File Manager (or Terminal), make these writable by the web server:

```bash
chmod -R 775 ~/mobilling-app/api/storage ~/mobilling-app/api/bootstrap/cache
chmod 666 ~/mobilling-app/api/.env
```

`.env` ships world-writable already for this exact reason — cPanel's PHP
runs as your own account user (not a separate `www-data`), so ownership is
usually already correct and this is mostly a no-op safety net.

## 7. SSL

cPanel → **SSL/TLS Status**, run **AutoSSL** for the domain (most hosts do
this automatically within a few minutes of the domain existing). The
installer and every API call require HTTPS.

## 8. Run the setup wizard

Visit `https://<yourdomain>/install`. Same four steps as the VPS guide:
Requirements → Database (use the prefixed database name/user/password
from step 2, host is usually `localhost`) → License → Admin account.

Once it finishes, log in at `https://<yourdomain>/login`.

## 9. Lock down `.env`

```bash
chmod 640 ~/mobilling-app/api/.env
```

## 10. Scheduled tasks (cron)

cPanel → **Cron Jobs**. Add a new job:

- **Common Settings**: Once Per Minute (`* * * * *`)
- **Command**:
  ```bash
  cd ~/mobilling-app/api && php artisan schedule:run >> /dev/null 2>&1
  ```

If your host restricts minute-level cron (some shared plans cap the
minimum interval at 5 or 15 minutes), that's fine — Laravel's scheduler
only actually runs `license:check` once it's past its scheduled time
(05:00 daily), a less frequent trigger just means it may run a few
minutes late that one time a day, not that it's skipped.

If you'd rather not deal with the scheduler at all, you can instead cron
the command directly, once a day:

```bash
0 5 * * * cd ~/mobilling-app/api && php artisan license:check >> /dev/null 2>&1
```

Without either of these, `license:check` never runs and the install's
license status will silently go stale — it'll keep saying "Active" under
Settings → License even long past when a check should have happened.

## Troubleshooting

- **500 error on every page**: check `api/storage/logs/laravel.log` via
  File Manager. Almost always a permissions issue from step 6, or a PHP
  extension missing from step 1.
- **API calls 404, only the frontend shell loads**: the `.htaccess` from
  step 5 didn't take — confirm `mod_rewrite` is enabled (cPanel almost
  always has it on) and that you replaced (not merged into)
  `api/public/.htaccess`.
- **"Base table or view not found" during the Database step**: the
  database name you entered doesn't include your cPanel username prefix —
  use the full name exactly as cPanel created it.
