class AiAgent::AccountSetting < ApplicationRecord
  self.table_name = 'ai_agent_account_settings'

  belongs_to :account
  belongs_to :persona,
             class_name: 'AiAgent::PersonaTemplate',
             optional: true
  # Médico (ou profissional do conselho equivalente — CRO, CRP, etc)
  # responsável técnico pela clínica. Identificado pelo User da conta
  # — CFM 2.454/2026 exige nome identificável + número do conselho.
  belongs_to :responsible_physician,
             class_name: 'User',
             optional: true

  validates :account_id, uniqueness: true
  # System message próprio da conta. Vazio = herda o default global do super
  # admin (ver ConfigResolver#system_prompt). Teto defensivo igual ao do
  # Captain::Document.content (200k) — o prompt real fica em ~30k.
  validates :system_prompt, length: { maximum: 200_000 }, allow_blank: true
  validates :monthly_token_budget,
            numericality: { greater_than: 0, allow_nil: true }
  validates :max_tokens_per_conversation,
            numericality: { greater_than: 0, allow_nil: true }
  # Conselho aceita texto livre (CRM, CRO, CRP, COREN, etc), uppercase.
  validates :responsible_physician_council,
            format: { with: /\A[A-Z]{2,8}\z/, message: 'use sigla maiúscula (ex: CRM, CRO, CRP)' },
            allow_blank: true
  # CRM/CRO/CRP no formato número + UF, ex: "123456/SP". Permissivo
  # com espaços e variações; valida só estrutura mínima.
  validates :responsible_physician_crm,
            format: { with: %r{\A\d{3,7}\s*[/\-]?\s*[A-Z]{2}\z}, message: 'use formato número/UF (ex: 123456/SP)' },
            allow_blank: true
end
