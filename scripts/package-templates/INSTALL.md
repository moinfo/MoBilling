# Installing MoBilling on your own server

This package is a ready-to-run build — the backend's PHP dependencies and
the frontend's production bundle are already included. You do **not** need
Composer, Node, or npm on this server; you only need PHP, MySQL, and a web
server.

## 1. Requirements

| Requirement | Version |
|---|---|
| PHP | 8.2+ |
| PHP extensions | pdo_mysql, mbstring, openssl, tokenizer, xml, ctype, json, bcmath, fileinfo, curl |
| MySQL / MariaDB | 8.0+ / 10.6+ |
| Nginx | 1.18+ (or Apache 2.4+, with equivalent rewrite rules) |
| SSL certificate | Required — the license check and every API call expect HTTPS |

A domain name pointed at this server (an A record) is required before you
start — the installer binds your license key to whichever domain you're
running on when you complete setup.

## 2. Unpack

```bash
unzip mobilling-<version>.zip -d /var/www/mobilling
cd /var/www/mobilling
```

## 3. Web server

Copy `nginx.conf.example` to `/etc/nginx/sites-available/<yourdomain>`,
replace `{{DOMAIN}}` and `{{PATH}}` (the directory you unzipped into, e.g.
`/var/www/mobilling`), then:

```bash
ln -s /etc/nginx/sites-available/<yourdomain> /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
certbot --nginx -d <yourdomain>   # get an SSL certificate before continuing
```

## 4. Permissions

```bash
chown -R www-data:www-data /var/www/mobilling/api/storage /var/www/mobilling/api/bootstrap/cache
chmod -R 775 /var/www/mobilling/api/storage /var/www/mobilling/api/bootstrap/cache
```

`.env` ships world-writable so the setup wizard's first step (which checks
it's writable by whichever user PHP-FPM runs as) passes regardless of that
user's name — see step 6 below to lock it back down once setup is done.

## 5. Run the setup wizard

Visit `https://<yourdomain>/install` in a browser. It will walk you
through, in order:

1. **Requirements check** — confirms PHP version, extensions, and file
   permissions are all correct (fixes anything it flags before letting you
   continue).
2. **Database** — enter the MySQL host/database/username/password for a
   database you've already created; the wizard tests the connection, writes
   it into `.env`, and creates the schema.
3. **License** — enter the license key you were issued when you purchased
   MoBilling. This is checked against MoBilling's license server and, once
   accepted, is bound to this domain.
4. **Admin account** — your company name and your own admin login.

Once the wizard finishes, log in at `https://<yourdomain>/login` with the
admin account you just created.

## 6. Lock down `.env`

The wizard just wrote your database password into `.env`, which is still
world-writable from step 4. Tighten it now:

```bash
chown www-data:www-data /var/www/mobilling/api/.env
chmod 640 /var/www/mobilling/api/.env
```

## After installation

- This install re-validates its license once a day. As long as the license
  is active, nothing further is needed. Its status is visible any time
  under **Settings → License**, including whether a newer version has been
  published.
- The `/install` wizard permanently disables itself the moment your first
  company/admin exists — it cannot be run again against this install.
- For anything not covered here (mail/SMTP, SMS gateway, payment gateway
  configuration), edit `api/.env` directly and reload PHP-FPM
  (`systemctl reload php8.2-fpm`) after changing it.
