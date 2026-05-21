class AddSpecialtiesToBeclinicAccountProfiles < ActiveRecord::Migration[7.0]
  # Permite que cada clínica configure:
  #   - `enabled_specialties` (jsonb array): quais especialidades ela atende.
  #     O FormSelect da Anamnese (e futuras telas como Plano de Tratamento)
  #     filtra opções por essa lista quando preenchida — reduz ruído pra
  #     clínicas mono-especialidade e evita escolher uma especialidade que
  #     a clínica não atende.
  #   - `default_specialty` (string): qual delas é o padrão. Anamneses novas
  #     pré-preenchem com esse valor → reduz atrito de digitação repetitiva.
  #
  # Motivação: em pacientes/16/record?tab=anamnesis o `Especialidade / Foco
  # Principal` era um select hardcoded com 4 opções genéricas, sem nenhuma
  # ligação com o tipo de clínica. Cada anamnese o profissional re-selecionava
  # a mesma coisa.
  def change
    change_table :beclinic_account_profiles, bulk: true do |t|
      t.string :default_specialty
      t.jsonb :enabled_specialties, default: []
    end
  end
end
