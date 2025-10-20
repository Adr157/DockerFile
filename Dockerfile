# Dockerfile: ubuntu-xrdp-ngrok-authtoken-ready
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV NGROK_AUTHTOKEN_DEFAULT=32Welp3eTScxos06FCnQkXay9YB_2vMrSx2JosPzgy7TQ1RLP
# Preferência: defina NGROK_AUTHTOKEN via runtime env var (Koyeb secret). 
# Se não definido, usará NGROK_AUTHTOKEN_DEFAULT (que é o token fornecido).

RUN apt-get update && apt-get install -y \
    xfce4 xfce4-goodies xrdp dbus-x11 wget curl unzip sudo iproute2 net-tools jq \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# criar usuário teste com senha 449090
RUN useradd -m -s /bin/bash teste \
    && echo 'teste:449090' | chpasswd \
    && adduser teste sudo

# configurar XFCE pro xrdp
RUN sed -i.bak '/^#.*session=.*$/d' /etc/xrdp/startwm.sh || true
RUN echo "startxfce4" > /home/teste/.xsession
RUN chown teste:teste /home/teste/.xsession

# baixar ngrok
RUN wget -q https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip -O /tmp/ngrok.zip \
    && unzip /tmp/ngrok.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/ngrok \
    && rm -f /tmp/ngrok.zip

EXPOSE 3389

# entrypoint script
RUN mkdir -p /opt/startup
COPY <<'EOT' /opt/startup/entrypoint.sh
#!/usr/bin/env bash
set -e

# Decide qual token usar: variável NGROK_AUTHTOKEN tem prioridade, senão usa o default embutido.
NGROK_TOKEN="${NGROK_AUTHTOKEN:-$NGROK_AUTHTOKEN_DEFAULT}"

if [ -z "$NGROK_TOKEN" ]; then
  echo "[ERROR] No ngrok token provided. Set NGROK_AUTHTOKEN env var or NGROK_AUTHTOKEN_DEFAULT in the image."
  exit 1
fi

# Configure ngrok (safe even se já configurado)
ngrok authtoken "$NGROK_TOKEN" >/dev/null 2>&1 || true

# Start services
service dbus start || true
service xrdp start || true

echo "==============================="
echo "RDP Server started!"
echo "Username: teste  |  Password: 449090"
echo "Internal IP (container):"
ip addr show | grep 'inet ' | grep -v '127.0.0.1' || true
echo "Starting ngrok tunnel (tcp -> 3389)..."

# Start ngrok in background (region can be changed: us, eu, ap, au, sa, jp, in)
ngrok tcp 3389 --region=us --log=stdout > /var/log/ngrok.log 2>&1 &

# Wait a bit for ngrok to start and then query the local API for the tcp endpoint
# Retry loop to wait for 4040 to be ready
for i in $(seq 1 12); do
  sleep 1
  if curl --silent --max-time 2 http://127.0.0.1:4040/api/tunnels >/dev/null 2>&1; then
    break
  fi
done

# Get tcp endpoint from ngrok API
NGROK_TUNNELS_JSON="$(curl --silent http://127.0.0.1:4040/api/tunnels || true)"
TCP_ENDPOINT="$(echo "$NGROK_TUNNELS_JSON" | jq -r '.tunnels[] | select(.proto=="tcp") | .public_url' | head -n1)"

if [ -n "$TCP_ENDPOINT" ]; then
  # public_url comes like tcp://0.tcp.ngrok.io:12345
  echo "NGROK RDP endpoint: $TCP_ENDPOINT"
  # Split host/port for convenience
  HOST="$(echo $TCP_ENDPOINT | sed -E 's|tcp://([^:]+):([0-9]+)|\1|')"
  PORT="$(echo $TCP_ENDPOINT | sed -E 's|tcp://([^:]+):([0-9]+)|\2|')"
  echo "Host: $HOST"
  echo "Port: $PORT"
  echo "Use these values in your RDP client (username: teste / password: 449090)"
else
  echo "[WARN] Could not obtain ngrok tcp endpoint from local API. Check /var/log/ngrok.log"
fi

# keep container running and stream important logs
tail -F /var/log/ngrok.log /var/log/xrdp-sesman.log /var/log/xrdp.log
EOT

RUN chmod +x /opt/startup/entrypoint.sh

CMD ["/opt/startup/entrypoint.sh"]
