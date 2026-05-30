# 08 — Migração dos PDFs Atuais (Prawn → Editor)

> O sistema hoje gera 10 tipos de documento clínico via Prawn e 11 tipos de consentimento via templates fixos no `body`. A decisão é **migrar tudo pro editor novo** — Prawn vira legado, mantido só pra compatibilidade reversa.

## 8.1 Inventário do que migrar

### Documentos clínicos (gerados em [`patients/pdf_generator.rb`](../../plugins/patients/app/services/patients/pdf_generator.rb))

| Tipo | Enum | Estado atual | Complexidade da migração |
|---|---|---|---|
| Receita Médica | `receita` (0) | Prawn em `lib/pdf/receita.rb` | Média (medicamentos em lista) |
| Atestado Médico | `atestado` (1) | Prawn | Baixa (texto simples) |
| Pedido de Exame | `pedido_exame` (2) | Prawn | Média (lista de exames) |
| Declaração | `declaracao` (3) | Prawn | Baixa |
| Relatório Clínico | `relatorio_clinico` (4) | Prawn | Média (texto longo, seções) |
| Encaminhamento | `encaminhamento` (5) | Prawn | Baixa |
| Contrato | `contrato` (6) | Prawn | Alta (texto extenso, cláusulas) |
| Orçamento | `orcamento` (7) | Prawn (com prawn-table) | Alta (tabela de itens) |
| Instrução de Procedimento | `instrucao_procedimento` (8) | Prawn | Média |
| Questionário | `questionario` (9) | Prawn | Média (perguntas+respostas) |

### Consentimentos (do `consent_records.body`)

Os 11 tipos atuais armazenam o texto cru no campo `body` (TEXT). Não é Prawn — é só template de string com placeholders `[NOME]`, `[CPF]`, etc.

| Tipo | Estado |
|---|---|
| Termo LGPD | Texto fixo + placeholders simples |
| Autorização de Uso de Imagem | Texto fixo |
| Consentimento Toxina Botulínica | Texto + lista de riscos/benefícios |
| Consentimento Preenchimento Dérmico | Texto + lista |
| Consentimento Laser | Texto |
| Consentimento Fototerapia LED | Texto |
| Consentimento Peeling Químico | Texto |
| Consentimento Dermoabrasão | Texto |
| Autorização Paciente Menor | Texto + dados do responsável |
| Consentimento Procedimento Cirúrgico Menor | Texto longo |
| Consentimento Anestesia Local/Tópica | Texto |
| Termo de Consentimento Geral | Texto |

## 8.2 Estratégia de migração

### Fase A — Coexistência (durante o desenvolvimento)

**Nenhuma quebra no caminho atual.** Templates Prawn e textos legados continuam servindo. Documentos novos podem ser gerados de qualquer lado.

```ruby
# patients/pdf_generator.rb (modificado — ver 04-backend.md, seção 4.9)
def call!
  if @template_id.present?
    delegate_to_new_engine   # Grover
  else
    legacy_prawn_generation  # Prawn (intacto)
  end
end
```

A coluna `documents.document_template_id` é nullable. Linha sem essa FK = gerada pelo legado.

### Fase B — Catálogo Klivy

Pra cada um dos 21 tipos (10 clínicos + 11 consentimentos), criar **um template Klivy equivalente** em `db/seeds/document_templates/`:

```
db/seeds/document_templates/
├── klivy_seed.rb                       # script principal (idempotente)
└── content/
    ├── 01_receita_medica.json
    ├── 02_atestado.json
    ├── 03_pedido_exame.json
    ...
    ├── 11_termo_lgpd.json
    ├── 12_autorizacao_imagem.json
    ...
```

Cada `.json` é um **documento ProseMirror válido** com as variáveis já posicionadas.

#### Exemplo: `02_atestado.json`

```json
{
  "type": "doc",
  "content": [
    {
      "type": "heading", "attrs": {"level": 1, "textAlign": "center"},
      "content": [{"type": "text", "text": "ATESTADO MÉDICO"}]
    },
    {
      "type": "paragraph", "attrs": {"textAlign": "justify"},
      "content": [
        {"type": "text", "text": "Atesto, para os devidos fins, que o(a) Sr(a). "},
        {"type": "variable", "attrs": {"key": "patient.full_name", "label": "Nome completo"}},
        {"type": "text", "text": ", portador(a) do CPF "},
        {"type": "variable", "attrs": {"key": "patient.cpf", "label": "CPF"}},
        {"type": "text", "text": ", esteve sob meus cuidados na presente data."}
      ]
    },
    {"type": "paragraph", "content": [{"type": "text", "text": ""}]},
    {
      "type": "paragraph", "attrs": {"textAlign": "right"},
      "content": [
        {"type": "variable", "attrs": {"key": "date.city_today", "label": "Cidade, data por extenso"}}
      ]
    },
    {"type": "paragraph", "content": [{"type": "text", "text": ""}]},
    {
      "type": "paragraph", "attrs": {"textAlign": "center"},
      "content": [
        {"type": "text", "text": "_______________________________"},
        {"type": "hardBreak"},
        {"type": "variable", "attrs": {"key": "professional.name", "label": "Nome do profissional"}},
        {"type": "hardBreak"},
        {"type": "variable", "attrs": {"key": "professional.council_full", "label": "Conselho completo"}}
      ]
    }
  ]
}
```

### Fase C — Seed automatizado

```ruby
# db/seeds/document_templates/klivy_seed.rb
module DocumentTemplates
  class SeedKlivyLibrary
    BASE_PATH = Rails.root.join('db/seeds/document_templates/content')

    DEFINITIONS = {
      'Receita Médica Padrão'              => { type: :receita,           file: '01_receita_medica.json' },
      'Atestado Médico Padrão'             => { type: :atestado,          file: '02_atestado.json' },
      'Pedido de Exame Padrão'             => { type: :pedido_exame,      file: '03_pedido_exame.json' },
      'Declaração de Comparecimento'       => { type: :declaracao,        file: '04_declaracao.json' },
      'Relatório Clínico Padrão'           => { type: :relatorio_clinico, file: '05_relatorio_clinico.json' },
      'Encaminhamento Médico'              => { type: :encaminhamento,    file: '06_encaminhamento.json' },
      'Contrato de Tratamento Estético'    => { type: :contrato,          file: '07_contrato_estetico.json' },
      'Contrato de Tratamento Odontológico' => { type: :contrato,         file: '07b_contrato_odonto.json' },
      'Orçamento Padrão'                   => { type: :orcamento,         file: '08_orcamento.json' },
      'Instruções Pós-Procedimento Botox'  => { type: :instrucao_procedimento, file: '09a_pos_botox.json' },
      'Instruções Pós-Limpeza de Pele'     => { type: :instrucao_procedimento, file: '09b_pos_limpeza.json' },

      # Consentimentos
      'Termo de Consentimento LGPD'        => { type: :consentimento_lgpd,        file: '11_termo_lgpd.json' },
      'Autorização de Uso de Imagem'       => { type: :consentimento_imagem,      file: '12_autorizacao_imagem.json' },
      'Consentimento — Toxina Botulínica'  => { type: :consentimento_toxina,      file: '13_cons_toxina.json' },
      'Consentimento — Preenchimento Dérmico' => { type: :consentimento_preenchimento, file: '14_cons_preench.json' },
      'Consentimento — Laser'              => { type: :consentimento_laser,       file: '15_cons_laser.json' },
      'Consentimento — Fototerapia LED'    => { type: :consentimento_fototerapia_led, file: '16_cons_led.json' },
      'Consentimento — Peeling Químico'    => { type: :consentimento_peeling,     file: '17_cons_peeling.json' },
      'Consentimento — Dermoabrasão'       => { type: :consentimento_dermoabrasao,file: '18_cons_dermoabrasao.json' },
      'Autorização — Paciente Menor'       => { type: :consentimento_menor,       file: '19_cons_menor.json' },
      'Consentimento — Cirurgia Menor'     => { type: :consentimento_cirurgico,   file: '20_cons_cirurgico.json' },
      'Consentimento — Anestesia Local'    => { type: :consentimento_anestesia,   file: '21_cons_anestesia.json' },
      'Termo de Consentimento Geral'       => { type: :consentimento_geral,       file: '22_cons_geral.json' }
    }.freeze

    def self.call!
      DEFINITIONS.each do |name, spec|
        content = JSON.parse(File.read(BASE_PATH.join(spec[:file])))
        DocumentTemplate.find_or_create_by!(
          name: name, source: 'klivy', account_id: nil, document_type: spec[:type]
        ) do |t|
          t.content_json = content
          t.status = 'active'
          t.paper_size = 'A4'
          t.orientation = 'portrait'
          t.created_by_user_id = nil
        end
      end
    end
  end
end
```

**Idempotente**: `find_or_create_by` evita duplicação. Reruns são seguros.

Roda em:
- `db/seeds.rb` (deploy ou após migration).
- Task rake dedicada: `rake klivy:seed_document_templates`.
- Pode ser chamado em background quando uma nova versão é deployada (compara checksums dos arquivos JSON).

### Fase D — Onboarding da clínica

Conta nova → vê na aba "Documentos" a seção "Modelos Klivy" com os 22 templates. **Não clona automático** — clínica clica "Usar este modelo" e o template é copiado pra conta dela (`source: 'cloned'`, mantém `source_template_id`).

### Fase E — Desativação gradual do Prawn

**Não desativar imediatamente.** Plano:

1. **Mês 1-2 pós-launch**: Prawn segue como fallback se template_id for null.
2. **Mês 3+**: monitorar uso — quando < 5% dos documentos novos usarem Prawn, marcar como deprecated no UI ("Esse caminho será descontinuado").
3. **Mês 6+**: remover código Prawn dos services. Documentos antigos já gerados continuam acessíveis via Active Storage — não dependem do código pra serem lidos.

## 8.3 Conversão Prawn → ProseMirror JSON

**Como produzir os arquivos `.json` de seed?** Três caminhos:

### Caminho 1 (recomendado): manualmente, com ajuda da IA

1. Abrir cada arquivo `lib/pdf/<tipo>.rb` atual
2. Extrair a sequência de texto/variáveis (basicamente as chamadas `pdf.text "..."` e `pdf.move_down`)
3. Pedir pra IA (Claude) converter em JSON ProseMirror
4. Validar no editor TipTap rodando local (cola o JSON, vê se render certo)
5. Salvar como seed

**Estimativa**: 30 minutos por documento × 22 docs ≈ 11 horas.

### Caminho 2: gerar via Prawn render mockado

Roda o Prawn atual com dados de teste, captura output, parseia. Complicado porque Prawn não expõe estrutura — só pinta no canvas.

❌ **Não recomendado**.

### Caminho 3: editor visual no seed

Sobe a feature, abre o editor logado como super admin, cria os 22 templates Klivy manualmente, exporta como JSON com botão "Export Klivy Seed".

**Mais ergonômico, mas exige que o editor já esteja funcionando.** Bom pra ajustes finos depois do MVP.

> **Decisão**: começar pelo Caminho 1 com 5-6 templates principais; usar Caminho 3 pros 16 restantes depois que a UI estiver pronta.

## 8.4 Compatibilidade reversa

`Document` gerados antes do release continuam acessíveis:
- `document_template_id IS NULL` → renderer Prawn (mantido).
- `rendered_html IS NULL` → não tem HTML congelado (legado).
- `file` (Active Storage) continua intacto.

**UI da aba Documentos do paciente** consegue listar ambos sem distinção visual — usuário não percebe a transição.

## 8.5 Riscos da migração

| Risco | Mitigação |
|---|---|
| Template Klivy mal-formatado quebra geração | Validador JSON ProseMirror obrigatório no seed; testes E2E gerando PDF de cada template |
| Diferença visual entre PDF Prawn antigo e Grover novo confunde clínica | Documentar como changelog visível; preview lado-a-lado nas configurações |
| Variáveis não mapeadas no novo modelo (ex: `responsible_name`) | Auditoria prévia (seção 7.2 deste doc); adicionar migrations se faltarem campos |
| Performance — Chromium é mais lento que Prawn (200ms vs 50ms p99) | Sempre rodar em background job; mostrar spinner; aceitar tradeoff |
| Schema do consent_record.body legado conflita com novo rendered_html | Manter ambos; preferência: rendered_html quando presente, senão body |

## 8.6 Plano de teste da migração

- [ ] Cada um dos 22 templates Klivy gera PDF sem erro
- [ ] Variáveis resolvem corretamente com paciente de teste
- [ ] Paciente sem CPF mostra fallback (não crasha)
- [ ] PDF gerado tem mesma estrutura básica do Prawn (header, body, signature line)
- [ ] Documento antigo (sem `document_template_id`) continua sendo aberto sem erro
- [ ] Performance: 22 templates seedados < 5s; cada PDF < 3s
- [ ] Tamanho do arquivo Grover ≤ 1.5x do Prawn (Chromium tende a inflar)
