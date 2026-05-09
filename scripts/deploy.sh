#!/bin/bash
set -e

DOCKERHUB_IMAGE=$1
IMAGE_TAG=$2
DOMAIN=$3
EMAIL=$4

echo "🚀 Starting deployment..."

# ── Install Docker ─────────────────────────────────────
if ! command -v docker &> /dev/null; then
    echo "📦 Installing Docker..."
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    sudo usermod -aG docker ubuntu
fi

# ── Install Nginx ──────────────────────────────────────
if ! command -v nginx &> /dev/null; then
    echo "📦 Installing Nginx..."
    sudo apt-get update -y
    sudo apt-get install -y nginx
    sudo systemctl enable nginx
fi

# ── Install Certbot ────────────────────────────────────
if ! command -v certbot &> /dev/null; then
    echo "📦 Installing Certbot..."
    sudo apt-get install -y certbot python3-certbot-nginx
fi

# ── Pull & Run Container ───────────────────────────────
echo "📥 Pulling image: $DOCKERHUB_IMAGE:$IMAGE_TAG"
sudo docker pull $DOCKERHUB_IMAGE:$IMAGE_TAG

echo "🛑 Stopping old container..."
sudo docker stop devops-app || true
sudo docker rm devops-app || true

echo "▶️  Starting new container..."
sudo docker run -d \
  --name devops-app \
  --restart always \
  -p 8000:8000 \
  -e DJANGO_SETTINGS_MODULE=studybud.settings \
  -e APP_VERSION=$IMAGE_TAG \
  $DOCKERHUB_IMAGE:$IMAGE_TAG

echo "🔄 Running migrations..."
sleep 5  # wait for container to fully start
sudo docker exec devops-app python manage.py migrate --noinput

echo "📁 Copying static files..."
sudo mkdir -p /home/ubuntu/static
sudo docker cp devops-app:/app/staticfiles/. /home/ubuntu/static/
sudo chown -R www-data:www-data /home/ubuntu/static

# ── Configure Nginx ────────────────────────────────────
echo "⚙️  Configuring Nginx..."
sudo tee /etc/nginx/sites-available/studybud > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
    }

    location /static/ {
        alias /home/ubuntu/static/;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/studybud /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

# ── Obtain SSL Certificate ─────────────────────────────
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    echo "🔒 Getting SSL certificate from Let's Encrypt..."
    sudo certbot --nginx \
      -d $DOMAIN \
      --non-interactive \
      --agree-tos \
      --email $EMAIL \
      --redirect
    echo "✅ SSL certificate obtained successfully!"
else
    echo "✅ SSL certificate already exists — skipping..."
    sudo certbot renew --quiet
fi

echo ""
echo "✅ Deployment complete!"
echo "🌍 App live at: https://$DOMAIN"
echo ""
sudo docker ps