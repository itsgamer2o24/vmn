#!/bin/bash
set -e

echo "🚀 MoonLink Railway container starting..."

# Start tailscaled (userspace mode – REQUIRED for Railway)
tailscaled --tun=userspace-networking --state=/tmp/tailscale.state &
sleep 5

# Bring Tailscale up
tailscale up \
  --authkey="${TAILSCALE_AUTHKEY}" \
  --hostname="moonlink-railway" \
  --ssh || true

echo "✅ Tailscale connected"
tailscale status

# Keep container alive
echo "🟢 Container is running..."
tail -f /dev/null
