# Auditoria BIA.md — COBERTURA DE PROMPT (FASE 1c).
#
# Decisões de roteamento da Bia (qual rota seguir, o que perguntar, quando
# escalar) são dirigidas pelo PROMPT do sistema. O prompt vive em runtime no
# InstallationConfig['CAPTAIN_BEA_SYSTEM_PROMPT'] (editável no /super_admin/bea),
# mas a versão canônica/revisável agora está versionada no repo em
# plugins/ai_agent/config/bea_system_prompt.txt — é a fonte que carregamos no
# banco e que este spec usa como contrato. Cada ramificação do BIA.md (T01–T23
# + regras transversais) precisa ter instrução explícita aqui; se alguém editar
# o prompt e remover uma regra-chave, este spec quebra no CI.
require 'rails_helper'

# Constantes no topo do arquivo (não dentro do bloco) pra evitar
# Lint/ConstantDefinitionInBlock — usadas pra GERAR os exemplos em loop, então
# precisam existir em tempo de carga.
BIA_PROMPT_PATH = Rails.root.join('plugins/ai_agent/config/bea_system_prompt.txt')

# Cada caso do BIA.md → trechos que TÊM que estar no prompt (lowercase).
BIA_PROMPT_COVERAGE = {
  'T01/T12_identifica_por_telefone' => ['find_patient_by_phone sempre na primeira'],
  'T02_checa_dependente_vinculado' => ['dependente', 'pra você ou pra alguém da família'],
  'T03_confirma_se_e_sobre_a_consulta' => ['list_appointments', 'é sobre ela'],
  'T04_duvida_rag_senao_humano' => ['search_knowledge', 'não resolver, transfer_to_human'],
  'T05_cancelamento_tenta_converter' => ['tente converter'],
  'T06_cancela_registra_e_checa_multa' => ['search_knowledge se existe política de multa', 'notify_staff'],
  'T08_reagenda_mesmo_doutor' => ['reschedule_appointment', 'mesmo doutor'],
  'T09_cadastral_vai_pra_recepcao' => ['atualização cadastral', 'transfer_to_human (recepção)'],
  'T10_motivo_fora_da_consulta_reroteia' => ['pergunte o motivo de forma aberta'],
  'T11_cadastrado_sem_consulta_vai_agendar' => ['vá para agendamento'],
  'T13_identifica_especialidade' => ['identifique a especialidade/profissional'],
  'T14_oferece_2_a_3_horarios' => ['de 2 a 3 horários'],
  'T15_preferencia_de_profissional' => ['preferência de profissional', 'ofereça outro profissional pelo nome'],
  'T16_resumo_com_drdra_e_maps' => ['link do google maps', 'dr./dra.'],
  'T18_lista_espera_e_como_conheceu' => ['add_to_waiting_list', 'como você conheceu a clínica'],
  'T19_disponibilidade_distante_1mes' => ['disponibilidade distante (> 1 mês)'],
  'T20_cadastro_minimo_nome_e_cpf' => ['nome completo + cpf'],
  'T21_busca_em_janelas_de_7_dias' => ['janelas de 7 dias'],
  'T22_forca_a_palavra_voce_terceiro' => ['confirme com a palavra "você"', 'use o patient_id'],
  'T23_menor_exige_responsavel' => ['menor de idade', 'responsável maior de idade',
                                    'data de nascimento do menor e do responsável'],
  'transversal_drdra_por_genero' => ['nome masculino → "dr.', 'nome feminino → "dra.'],
  'transversal_frase_banida_proibida' => ['são proibidas as frases', 'atendente humano'],
  'transversal_saida_limpa_sem_meta' => ['saída limpa'],
  'transversal_fecha_agendamento_sozinha' => ['você fecha o agendamento sozinha'],
  # Regras reforçadas após teste ao vivo (2026-06-06):
  'transversal_queixa_obrigatoria_antes_de_horarios' => ['para quem + queixa (obrigatório'],
  'transversal_rebusca_nao_chuta_horario' => ['re-busque, não chute'],
  'transversal_emoji_raro' => ['emoji é raro'],
  'transversal_como_conheceu_no_fechamento' => ['como você conheceu a gente'],
  'transversal_urgencia_dental_nao_e_samu' => ['urgência odontológica'],
  # 2026-06-11: a Bia citou "LGPD" pro paciente — agora a regra é a oposta:
  # tranquilização coloquial e PROIBIDO citar lei/sigla (LGPD, CFM).
  'transversal_cadastro_tranquiliza_sem_citar_lei' => ['proibido citar lgpd'],
  'transversal_fala_como_gente_sem_jargao' => ['fale como gente'],
  # 2026-06-11: "bom dia" → ela pediu nome completo + CPF + criou ficha +
  # presumiu consulta. Saudação não inicia cadastro nem presume agendamento.
  'transversal_saudacao_nao_pede_cpf_nem_presume_agendamento' => ['um "bom dia" é só um bom dia'],
  # 2026-06-12: "quero agendar um implante" → ela rebatizou pra "avaliação de
  # implante" e seguiu o fluxo. Serviço nomeado → checa a lista PRIMEIRO.
  'transversal_servico_nomeado_checa_lista_primeiro' => ['a clínica atende isso?', 'proibido rebatizar o pedido'],
  # Regras reforçadas após teste ao vivo (2026-06-07):
  'transversal_multa_so_do_rag' => ['multa só existe na sua boca se existir no rag'],
  'transversal_apresenta_como_bia' => ['apresente-se como a bia'],
  'transversal_pergunta_nome_se_nao_souber' => ['pergunte o nome'],
  'transversal_cancelamento_nas_observacoes_do_paciente' => ['observações do paciente'],
  'transversal_pergunta_pra_quem_no_agendamento' => ['pra você mesmo ou pra outra pessoa']
}.freeze

RSpec.describe 'BIA.md — cobertura do prompt do sistema da Bia' do
  # Lido uma vez, normalizado (lowercase + espaços colapsados) pra casar
  # com as frases independentemente de quebra de linha/caixa.
  let(:prompt) { File.read(BIA_PROMPT_PATH).downcase.gsub(/\s+/, ' ') }

  it 'o arquivo canônico do prompt existe e não está vazio' do
    expect(File).to exist(BIA_PROMPT_PATH)
    expect(File.read(BIA_PROMPT_PATH).strip.length).to be > 2000
  end

  BIA_PROMPT_COVERAGE.each do |caso, fragments|
    it "#{caso}: prompt cobre a ramificação" do
      fragments.each do |fragment|
        expect(prompt).to include(fragment.downcase),
                          "prompt NÃO cobre #{caso}: faltou o trecho #{fragment.inspect}"
      end
    end
  end

  # Garante que a regra que o dono pediu (substituir a frase fria) está
  # escrita como PROIBIÇÃO — não basta o sanitizer; o prompt também orienta.
  it 'manda usar "setor responsável" no lugar da frase banida' do
    expect(prompt).to include('setor responsável')
  end
end
