FROM python:3.11-slim

# 1. Systemowe zależności – komplet narzędzi sieciowych i użytkowych
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      # sieć i diagnostyka
      iproute2 \
      iputils-ping \
      net-tools \
      dnsutils \
      curl \
      # skanowanie
      nmap \
      # Redis CLI
      redis-tools \
      # mailing
      msmtp \
      # harmonogram
      cron \
      # podgląd procesów, logów
      procps \
      # ewentualne klonowanie/skrypty
      git \
      # certyfikaty SSL
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. Pythonowe biblioteki do GMP, nmap, PDF i Redis
RUN pip install \
      python-gvm \
      python3-nmap \
      reportlab \
      redis

# 3. Kopiujemy skrypty i nadajemy im prawa wykonania
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh /opt/scripts/*.py

# 4. Punkt wejścia
ENTRYPOINT ["/opt/scripts/entrypoint.sh"]



