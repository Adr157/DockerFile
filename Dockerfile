# Dockerfile: ubuntu-xrdp atualizado
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Instala XFCE, xrdp e utilitários
RUN apt-get update && apt-get install -y \
    xfce4 xfce4-goodies xrdp dbus-x11 wget sudo net-tools iproute2 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Cria usuário teste com senha 449090 e adiciona ao sudo
RUN useradd -m -s /bin/bash teste \
    && echo 'teste:449090' | chpasswd \
    && adduser teste sudo

# Configura xrdp para usar XFCE
RUN sed -i.bak '/^#.*session=.*$/d' /etc/xrdp/startwm.sh || true
RUN echo "startxfce4" > /home/teste/.xsession
RUN chown teste:teste /home/teste/.xsession

# Expor porta 3389
EXPOSE 3389

# Script de inicialização que inicia dbus, xrdp e exibe IP
CMD bash -c "\
    service dbus start && \
    service xrdp start && \
    echo '===============================' && \
    echo 'RDP Server started!' && \
    echo 'Use username: teste | password: 449090' && \
    echo 'IP interno do container:' && ip addr show | grep 'inet ' | grep -v '127.0.0.1' && \
    tail -f /var/log/xrdp-sesman.log /var/log/xrdp.log \
"
