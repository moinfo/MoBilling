# MoBilling Deployment Guide

Complete guide for deploying the MoBilling platform (API + Frontend) to a production server.

---

## Prerequisites

| Requirement | Version |
|-------------|---------|
| PHP | 8.3+ |
| Composer | 2.x |
| Node.js | 20+ |
| npm | 10+ |
| MySQL | 8.0+ |
| Nginx | 1.18+ (or Apache 2.4+) |
| Supervisor | (for queue workers) |
| SSL Certificate | Required for production |

### Required PHP Extensions

```
php-mbstring php-xml php-curl php-mysql php-zip php-gd php-bcmath php-uuid
```

---

## 1. Server Setup

### Create application user and directories

```bash
sudo adduser mobilling
sudo mkdir -p /var/www/mobilling/api
sudo mkdir -p /var/www/mobilling/frontend
sudo chown -R mobilling:www-data /var/www/mobilling
```

---

## 2. Backend Deployment (Laravel API)

### 2.1 Clone and install

```bash
cd /var/www/mobilling/api
git clone <your-repo-url> .
composer install --no-dev --optimize-autoloader
```

### 2.2 Environment configuration

```bash
cp .env.example .env
php artisan key:generate
```

Edit `.env` with production values:

```env
APP_NAME=MoBilling
APP_ENV=production
APP_DEBUG=false
APP_URL=https://api.yourdomain.com

# Database
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=unganisha
DB_USERNAME=mobilling_user
DB_PASSWORD=<strong-password>

# Session & Cache
SESSION_DRIVER=file
CACHE_STORE=file
QUEUE_CONNECTION=database

# Mail (SMTP example)
MAIL_MAILER=smtp
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=your@email.com
MAIL_PASSWORD=your-app-password
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=no-reply@yourdomain.com
MAIL_FROM_NAME=MoBilling

# Frontend URL (for CORS)
FRONTEND_URL=https://app.yourdomain.com

# SMS Gateway (optional)
SMS_GATEWAY_URL=https://sms-gateway.example.com
SMS_GATEWAY_MASTER_AUTH=<auth-token>
SMS_GATEWAY_TIMEOUT=30

# Pesapal Payment Gateway (optional)
PESAPAL_CONSUMER_KEY=<key>
PESAPAL_CONSUMER_SECRET=<secret>
PESAPAL_SANDBOX=false
PESAPAL_IPN_ID=<ipn-id>
PESAPAL_CALLBACK_URL=https://app.yourdomain.com/subscription
PESAPAL_IPN_URL=https://api.yourdomain.com/api/pesapal/ipn
PESAPAL_CURRENCY=TZS
```

### 2.3 Database setup

```bash
# Create database and user
mysql -u root -p <<EOF
CREATE DATABASE unganisha CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'mobilling_user'@'localhost' IDENTIFIED BY '<strong-password>';
GRANT ALL PRIVILEGES ON unganisha.* TO 'mobilling_user'@'localhost';
FLUSH PRIVILEGES;
EOF

# Run migrations
php artisan migrate --force
```

### 2.4 Optimize for production

```bash
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan storage:link
```

### 2.5 Set permissions

```bash
sudo chown -R mobilling:www-data /var/www/mobilling/api
sudo chmod -R 775 storage bootstrap/cache
```

---

## 3. Frontend Deployment (React + Vite)

### 3.1 Build

```bash
cd /var/www/mobilling/frontend
git clone <your-frontend-repo-url> .

# Create production env
echo "VITE_API_URL=https://api.yourdomain.com/api" > .env

# Install and build
npm ci
npm run build
```

The build output is in `dist/` — this is what Nginx serves.

### 3.2 For subsequent deployments

```bash
git pull
npm ci
npm run build
```

---

## 4. Nginx Configuration

### API (api.yourdomain.com)

```nginx
server {
    listen 80;
    server_name api.yourdomain.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/api.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.yourdomain.com/privkey.pem;

    root /var/www/mobilling/api/public;
    index index.php;

    client_max_body_size 20M;

    # CORS headers
    add_header Access-Control-Allow-Origin "https://app.yourdomain.com" always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, PATCH, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With" always;
    add_header Access-Control-Allow-Credentials "true" always;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
```

### Frontend (app.yourdomain.com)

```nginx
server {
    listen 80;
    server_name app.yourdomain.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name app.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/app.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.yourdomain.com/privkey.pem;

    root /var/www/mobilling/frontend/dist;
    index index.html;

    # SPA: all routes fall back to index.html
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

### Enable and test

```bash
sudo ln -s /etc/nginx/sites-available/mobilling-api /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/mobilling-frontend /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

## 5. SSL Certificates (Let's Encrypt)

```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d api.yourdomain.com -d app.yourdomain.com
```

Auto-renewal is configured automatically by certbot.

---

## 6. Cron / Task Scheduling

Laravel's task scheduler needs a single cron entry:

```bash
sudo crontab -u mobilling -e
```

Add:

```
* * * * * cd /var/www/mobilling/api && php artisan schedule:run >> /dev/null 2>&1
```

This runs the following scheduled tasks:

| Time | Command | Purpose |
|------|---------|---------|
| 07:00 | `invoices:process-recurring` | Generate recurring invoices |
| 08:00 | `bills:send-reminders` | Send bill reminders (email/SMS) |
| 09:00 | `bills:generate-recurring` | Generate statutory bills (safety net) |
| Hourly | `subscriptions:expire` | Expire overdue tenant subscriptions |

---

## 7. Queue Worker (Optional)

If using `QUEUE_CONNECTION=database` for async jobs (email sending, etc.):

### Supervisor configuration

```bash
sudo nano /etc/supervisor/conf.d/mobilling-worker.conf
```

```ini
[program:mobilling-worker]
process_name=%(program_name)s_%(process_num)02d
command=php /var/www/mobilling/api/artisan queue:work --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=mobilling
numprocs=2
redirect_stderr=true
stdout_logfile=/var/www/mobilling/api/storage/logs/worker.log
stopwaitsecs=3600
```

```bash
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start mobilling-worker:*
```

---

## 8. Storage & Uploads

Uploaded files (receipts, logos) are stored in `storage/app/public/`. The symlink was created during setup:

```bash
php artisan storage:link
```

For production, consider using S3 or similar object storage by updating `FILESYSTEM_DISK=s3` in `.env`.

---

## 9. Updating / Deploying New Versions

### Backend

```bash
cd /var/www/mobilling/api
git pull
composer install --no-dev --optimize-autoloader
php artisan migrate --force
php artisan config:cache
php artisan route:cache
php artisan view:cache
sudo supervisorctl restart mobilling-worker:*
```

### Frontend

```bash
cd /var/www/mobilling/frontend
git pull
npm ci
npm run build
```

No server restart needed for frontend — Nginx serves the new static files immediately.

---

## 10. Monitoring & Logs

### Application logs

```bash
# Laravel logs
tail -f /var/www/mobilling/api/storage/logs/laravel.log

# Nginx access/error logs
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log

# Queue worker logs
tail -f /var/www/mobilling/api/storage/logs/worker.log
```

### Health checks

```bash
# Test API is responding
curl -s https://api.yourdomain.com/api/auth/login | head -c 200

# Test frontend is serving
curl -s -o /dev/null -w "%{http_code}" https://app.yourdomain.com

# Check scheduled tasks ran
php artisan schedule:list
```

---

## 11. Backup Strategy

### Database backup (daily)

```bash
# Add to crontab
0 2 * * * mysqldump -u mobilling_user -p'<password>' unganisha | gzip > /var/backups/mobilling/db-$(date +\%Y\%m\%d).sql.gz
```

### File backup

```bash
# Uploaded files
0 3 * * * tar czf /var/backups/mobilling/uploads-$(date +\%Y\%m\%d).tar.gz /var/www/mobilling/api/storage/app/public/
```

### Retention (keep 30 days)

```bash
0 4 * * * find /var/backups/mobilling/ -mtime +30 -delete
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| 500 error | Check `storage/logs/laravel.log`, ensure permissions on `storage/` and `bootstrap/cache/` |
| CORS errors | Verify `FRONTEND_URL` in `.env` matches your frontend domain exactly |
| Blank page on frontend | Ensure Nginx has `try_files $uri $uri/ /index.html` for SPA routing |
| Migrations fail | Ensure DB user has full privileges on the database |
| Queue jobs not running | Check Supervisor status: `sudo supervisorctl status` |
| Cron not running | Verify with `crontab -u mobilling -l`, check Laravel schedule: `php artisan schedule:list` |
| File uploads fail | Check `client_max_body_size` in Nginx and PHP `upload_max_filesize` |
| SMS not sending | Verify `SMS_GATEWAY_URL` and `SMS_GATEWAY_MASTER_AUTH` in `.env` |
