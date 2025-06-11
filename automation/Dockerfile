FROM python:3.11-slim

# 1. System requirements
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      # network i/o
      iproute2 \
      iputils-ping \
      net-tools \
      dnsutils \
      curl \
      nmap \
      # Redis CLI
      redis-tools \
      # mailing
      msmtp \
      # scheduling
      cron \
      # process and log management
      procps \
      # cloning git repos
      git \
      # SSL certificates
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. Python dependencies
RUN pip install \
      python-gvm \
      python3-nmap \
      reportlab \
      redis

# 3. Copy scripts and make them executable
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh /opt/scripts/*.py

# 4. Entrypoint
ENTRYPOINT ["/opt/scripts/entrypoint.sh"]



