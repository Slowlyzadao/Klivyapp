# Figurinhas padrão da Klivy

Coloque aqui as figurinhas que devem aparecer **automaticamente em todas as contas** da Klivy. As figurinhas são organizadas por **categoria** (subpasta).

## Estrutura

```
seed_stickers/
├── README.md
├── dentista/        ← figurinhas relacionadas a odontologia
├── bem_estar/       ← bem-estar, spa, wellness
└── estetica/        ← estética, beauty, dermato
```

Apenas estas três categorias são reconhecidas. Subpastas com outros nomes são ignoradas.

## Formato do arquivo

- **Extensão**: `.webp` (recomendado), `.png` ou `.gif`
- **Tamanho ideal**: 512×512px quadrado, fundo transparente
- **Limite**: 300KB por arquivo (a task rejeita maiores)

### Conversão de PNG/JPG → WebP otimizado

Use `cwebp` (libwebp) instalado via `brew install webp`:

```sh
cwebp -q 80 -resize 512 0 -mt input.png -o output.webp
```

Em PNGs de 1024×1024 isso costuma reduzir de ~1.8MB pra ~60KB.

Para converter uma pasta inteira:

```sh
for f in *.png; do
  cwebp -q 80 -resize 512 0 -mt "$f" -o "${f%.png}.webp"
done
```

## Nomenclatura

O nome do arquivo (sem extensão) vira o "rótulo" da figurinha exibido na busca:

- `dentista_01.webp` → nome: "dentista 01"
- `coracao-rosa.webp` → nome: "coracao rosa"

## Como aplicar

```sh
bundle exec rails internal_chat:seed_default_stickers
```

A task:
1. Lê cada subpasta de categoria
2. Cria/atualiza figurinhas com `kind='default'`, `category=<subpasta>`, `account_id=NULL`
3. **Idempotente**: re-rodar só atualiza arquivos cujo conteúdo mudou (compara byte size)
4. **GC**: remove figurinhas defaults cujo arquivo não existe mais na pasta

## Comportamento no app

- Figurinhas **default aparecem para todos os usuários, em todas as contas**, sem precisar favoritar
- Aparecem na **aba correspondente** do picker (ícone de dente, folha, sparkle)
- **Não podem ser removidas** pelos usuários — a gestão é via esta pasta + rake task
- Podem ser enviadas em mensagens normalmente
- O criador da clínica continua podendo subir figurinhas próprias via UI (essas são privadas, não-categorizadas, e seguem o fluxo de favoritar/desfavoritar)
