FROM node:20

# Instala ferramentas necessárias pro build do Baileys e de compactação
RUN apt-get update && apt-get install -y \
    python3 \
    make \
    g++ \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# Define o fuso horário (ajuste se quiser)
ENV TZ=America/Sao_Paulo

# Define o diretório de trabalho na imagem
WORKDIR /app

# Copia e instala as dependências
COPY package.json ./
RUN npm install

# Copia o restante do código
COPY . .

# Expõe a porta que o motor usa
EXPOSE 3002

# Inicia o servidor Node
CMD ["node", "server.js"]
