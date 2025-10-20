# Dockerfile: ubuntu-xrdp
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    xfce4 xfce4-goodies xrdp dbus-x11 wget sudo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# cria usuário (troca "koyuser" e senha "changeme" por algo seguro)
RUN useradd -m -s /bin/bash koyuser \
    && echo 'koyuser:changeme' | chpasswd \
    && adduser koyuser sudo

# configurar xrdp para usar xfce
RUN sed -i.bak '/^#.*session=.*$/d' /etc/xrdp/startwm.sh || true
RUN echo "startxfce4" > /home/koyuser/.xsession
RUN chown koyuser:koyuser /home/koyuser/.xsession

# abrir porta 3389
EXPOSE 3389

CMD ["/usr/sbin/xrdp-sesman","--nodaemon"] 
# (alternativa CMD para iniciar xrdp completo se precisar: /usr/sbin/xrdp --nodaemon)
