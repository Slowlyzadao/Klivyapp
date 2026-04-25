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

RUN chmod +x docker/entrypoints/rails.sh
RUN chmod +x docker/entrypoints/helpers/*.rb

EXPOSE 3000
CMD ["rails", "server", "-b", "0.0.0.0", "-p", "3000"]