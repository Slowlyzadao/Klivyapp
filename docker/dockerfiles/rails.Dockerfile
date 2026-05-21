FROM chatwoot:development

ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# Install pnpm + build tools + python3
RUN npm install -g pnpm && \
    if command -v apk > /dev/null; then \
      apk add --no-cache python3 make g++ && ln -sf python3 /usr/bin/python; \
    elif command -v apt-get > /dev/null; then \
      apt-get update && apt-get install -y build-essential python3 libpq-dev && ln -sf python3 /usr/bin/python && rm -rf /var/lib/apt/lists/*; \
    fi

# PostgreSQL client v16 — pg_dump do dev tem que bater com o server v16
# (pgvector/pgvector:pg16 no compose). Default Debian bookworm traz v15 e
# pg_dump aborta com version mismatch. Necessário pro Financial::CreateBackup.
# Bookworm hardcoded porque a base é ruby:3.4.4-slim-bookworm e lsb_release
# pode não estar disponível na imagem base ainda.
RUN curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor > /etc/apt/trusted.gpg.d/postgresql.gpg \
  && echo "deb http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list \
  && apt-get update \
  && apt-get install -y postgresql-client-16 \
  && rm -rf /var/lib/apt/lists/*

RUN chmod +x docker/entrypoints/rails.sh
RUN chmod +x docker/entrypoints/helpers/*.rb

EXPOSE 3000
CMD ["rails", "server", "-b", "0.0.0.0", "-p", "3000"]