# Dockerfile: ubuntu-xrdp-ngrok-v3
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
# Não coloque token direto aqui em repositório público. Defina NGROK_AUTHTOKEN no Koyeb env vars.
ENV NGROK_AUTHTOKEN=""

RUN apt-get update && apt-get install -y \
    xfce4 xfce4-goodies xrdp dbus-x11 wget curl unzip sudo iproute2 net-tools jq ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# criar usuário teste com senha 449090
RUN useradd -m -s /bin/bash teste \
    && echo 'teste:449090' | chpasswd \
    && adduser teste sudo

# configurar XFCE pro xrdp
RUN sed -i.bak '/^#.*session=.*$/d' /etc/xrdp/startwm.sh || true
RUN echo "startxfce4" > /home/teste/.xsession
RUN chown teste:teste /home/teste/.xsession

# Instalar ngrok v3 (tenta baixar o binário estável v3)
RUN set -eux; \
    NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz"; \
    mkdir -p /tmp/ngrok && \
    if curl -fsSL "$NGROK_URL" -o /tmp/ngrok/ngrok.tgz; then \
       tar -xzf /tmp/ngrok/ngrok.tgz -C /tmp/ngrok || true; \
       mv /tmp/ngrok/ngrok /usr/local/bin/ngrok || true; \
       chmod +x /usr/local/bin/ngrok || true; \
       rm -rf /tmp/ngrok; \
    else \
       echo "Failed to download ngrok v3 from $NGROK_URL"; \
    fi

EXPOSE 3389

# entrypoint
COPY <<'EOT' /opt/startup/entrypoint.sh
#!/usr/bin/env bash
set -euo pipefail

# NGROK token priority: runtime env NGROK_AUTHTOKEN
if [ -z "${NGROK_AUTHTOKEN:-}" ]; then
  echo "[WARN] NGROK_AUTHTOKEN not set. Set it in Koyeb environment variables for ngrok to auth."
else
  echo "Configuring ngrok authtoken..."
  /usr/local/bin/ngrok config add-authtoken "${NGROK_AUTHTOKEN}" >/dev/null 2>&1 || true
fi

# start required services
service dbus start || true
service xrdp start || true

echo "==============================="
echo "RDP Server started!"
echo "Username: teste  |  Password: 449090"
echo "Internal IP (container):"
ip addr show | grep 'inet ' | grep -v '127.0.0.1' || true

# start ngrok tcp tunnel (background). region can be changed if você preferir (eu usei us)
echo "Starting ngrok tunnel (tcp -> 3389)..."
/usr/local/bin/ngrok tcp 3389 --region=us --log=stdout > /var/log/ngrok.log 2>&1 &

# wait for ngrok local API then print tcp endpoint
for i in $(seq 1 15); do
  sleep 1
  if curl --silent --max-time 2 http://127.0.0.1:4040/api/tunnels >/dev/null 2>&1; then
    break
  fi
done

NG_JSON="$(curl --silent http://127.0.0.1:4040/api/tunnels || true)"
if [ -n "$NG_JSON" ]; then
  TCP_URL="$(echo "$NG_JSON" | jq -r '.tunnels[] | select(.proto=="tcp") | .public_url' | head -n1 || true)"
  if [ -n "$TCP_URL" ] && [ "$TCP_URL" != "null" ]; then
    echo "NGROK RDP endpoint: $TCP_URL"
    HOST="$(echo $TCP_URL | sed -E 's|tcp://([^:]+):([0-9]+)|\1|')"
    PORT="$(echo $TCP_URL | sed -E 's|tcp://([^:]+):([0-9]+)|\2|')"
    echo "Host: $HOST"
    echo "Port: $PORT"
    echo "Use these values in your RDP client (username: teste / password: 449090)"
  else
    echo "[WARN] ngrok is running but no tcp tunnel info found. Check /var/log/ngrok.log"
  fi
else
  echo "[WARN] ngrok local API returned empty. Check /var/log/ngrok.log"
fi

# tail logs to keep container alive and allow you to see ngrok/xrdp output
tail -F /var/log/ngrok.log /var/log/xrdp-sesman.log /var/log/xrdp.log
EOT

RUN chmod +x /opt/startup/entrypoint.sh

CMD ["/opt/startup/entrypoint.sh"]
