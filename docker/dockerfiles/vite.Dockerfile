FROM chatwoot:development

ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# Install pnpm + build tools for native gem compilation
RUN npm install -g pnpm && \
    apt-get update && apt-get install -y build-essential python3 libpq-dev && \
    ln -sf python3 /usr/bin/python && \
    rm -rf /var/lib/apt/lists/*

RUN chmod +x docker/entrypoints/vite.sh

EXPOSE 3036
CMD ["bin/vite", "dev"]
