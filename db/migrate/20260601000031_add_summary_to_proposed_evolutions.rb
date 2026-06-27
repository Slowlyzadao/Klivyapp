# 2026-05-22 — Resumo executivo dedicado da teleconsulta.
#
# Antes a UI "Resumo da Teleconsulta" caía no `raw_markdown` inteiro (SOAP
# bruto) com truncate de 600 chars, duplicando os cards S/O/A/P ao lado.
# Agora o Claude gera um bloco `## Resumo Executivo` separado (4-8 linhas
# em Markdown livre — negrito/bullets ok) e a UI renderiza esse campo
# isolado, sem corte.
#
# Encryption igual ao `raw_markdown` — PII clínica (LGPD #35). `support_
# unencrypted_data = true` no config global permite leitura de evoluções
# antigas (summary=nil enquanto não reprocessadas).
class AddSummaryToProposedEvolutions < ActiveRecord::Migration[7.1]
  def change
    add_column :proposed_evolutions, :summary, :text
  end
end
