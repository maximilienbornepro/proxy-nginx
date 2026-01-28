# Shared Nginx Reverse Proxy

Reverse proxy configuration for routing traffic to multiple applications.

## Domains

| Domain | Application | Auth |
|--------|-------------|------|
| studio.vitess.tech | Delivery Tools | JWT |
| rndv.vitess.tech | RNDV Tools | htpasswd |

## Structure

```
proxy-nginx/
├── docker-compose.yml    # Nginx container config
├── nginx/
│   └── nginx.conf        # Nginx routing config
├── ssl/                  # SSL certificates (gitignored)
└── certbot/              # Let's Encrypt (gitignored)
```

## Deployment

Automatic deployment on push to `main` branch via GitHub Actions.

Manual deployment:
```bash
ssh user@server
cd /opt/apps/proxy
git pull origin main
docker compose exec nginx nginx -t
docker compose exec nginx nginx -s reload
```

## Local files (not versioned)

Ces fichiers doivent etre crees manuellement sur le serveur :
- `nginx/.htpasswd` - Credentials htpasswd pour rndv.vitess.tech
- `nginx/ssl/` - Certificats SSL (fullchain.pem, privkey.pem)

## Network

Le proxy utilise le network Docker externe `proxy-network` pour communiquer avec les containers des autres applications.

```bash
# Create network (one-time setup)
docker network create proxy-network
```
# Test deploy
