# Estratégia de Documentação de API (Scalar + Plugins)

Este documento descreve a arquitetura de documentação de API adotada para o KlivyApp, utilizando **Scalar** para renderização e uma estrutura modular baseada em **Plugins**.

## 1. Visão Geral
Para manter o núcleo (core) do Chatwoot limpo e garantir que novos módulos (como a Agenda) sejam independentes, adotamos uma estratégia de documentação distribuída. Cada plugin é responsável por definir sua própria interface de API.

## 2. Estrutura de Arquivos

### 2.1. No Plugin (Ex: `plugins/agenda`)
Cada plugin deve conter uma pasta `swagger/` com a seguinte estrutura:
- `plugins/[NOME_DO_PLUGIN]/swagger/index.yml`: Arquivo principal do plugin.
- `plugins/[NOME_DO_PLUGIN]/swagger/paths/`: Definição de endpoints.
- `plugins/[NOME_DO_PLUGIN]/swagger/definitions/`: Schemas e modelos de dados.

### 2.2. No Core (`swagger/`)
- `swagger/plugins_index.yml`: O agregador global. Ele usa `$ref` para apontar para o `index.yml` de cada plugin ativo.
- `swagger/plugins_swagger.json`: O arquivo final buildado (compilado) que o Scalar consome.
- `swagger/scalar.html`: A interface visual que renderiza a documentação.

## 3. Fluxo de Trabalho

### Como Adicionar Documentação a um Novo Plugin
1. Crie a pasta `swagger/` dentro do seu plugin.
2. Defina os endpoints seguindo o padrão OpenAPI 3.0.
3. Adicione a referência do seu plugin no arquivo `swagger/plugins_index.yml`:
   ```yaml
   paths:
     /api/v1/novo-plugin:
       $ref: '../plugins/novo-plugin/swagger/index.yml'
   ```

### Como Gerar a Documentação (Build)
Rode a tarefa rake para compilar todos os fragmentos em um único JSON:
```bash
bundle exec rails swagger:build_plugins
```
*(Nota: Esta tarefa será implementada em `lib/tasks/swagger.rake`)*

## 4. Visualização
As documentações podem ser acessadas em:
- **Plugins:** `http://localhost:3000/docs/plugins`
- **Core (Chatwoot):** `http://localhost:3000/docs/core`

## 5. Por que Scalar?
- **Interatividade:** Permite testar requisições diretamente no navegador.
- **Modernidade:** Design premium e responsivo.
- **Isolamento:** Facilita a separação entre a API pública do Chatwoot e as APIs customizadas dos seus plugins.
