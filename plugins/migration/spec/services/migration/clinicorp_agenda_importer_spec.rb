require 'rails_helper'

RSpec.describe Migration::ClinicorpAgendaImporter do
  # ──────────────────────────────────────────────────────────────────────────
  # Classifier — testes unitários, sem DB. Cobre todas as regras documentadas
  # no comentário acima de BLOCK_CATEGORIES / APPOINTMENT_CATEGORIES.
  # Foco da PR auditoria 2026-05-21.
  # ──────────────────────────────────────────────────────────────────────────
  describe '.classify_event_type' do
    subject(:classify) do
      described_class.classify_event_type(category: category, patient_present: patient_present)
    end

    context 'categorias de bloqueio (agenda_block)' do
      let(:patient_present) { false }

      [
        'Intervalo',
        'Intervalo Almoço',
        'INTERVALO ALMOÇO',
        '  intervalo  ',
        'Almoço',
        'almoco',
        'Pausa',
        'Bloqueio'
      ].each do |raw|
        context "category=#{raw.inspect}" do
          let(:category) { raw }
          it { is_expected.to eq('agenda_block') }
        end
      end
    end

    context 'categorias de compromisso (appointment)' do
      let(:patient_present) { true }

      ['Reunião', 'reuniao', 'Compromisso', 'Evento'].each do |raw|
        context "category=#{raw.inspect}" do
          let(:category) { raw }
          it { is_expected.to eq('appointment') }
        end
      end
    end

    context 'categorias clínicas (consultation) — com paciente presente' do
      let(:patient_present) { true }

      [
        'Odonto', 'Consulta', 'Avaliação', 'Retorno', 'Manutenção',
        'Particular', 'Cirurgia', 'Periódico', 'dental uni', '',
        nil
      ].each do |raw|
        context "category=#{raw.inspect}" do
          let(:category) { raw }
          it { is_expected.to eq('consultation') }
        end
      end
    end

    context 'sem paciente e sem categoria conhecida → agenda_block' do
      let(:patient_present) { false }

      [nil, '', 'Odonto', 'Particular'].each do |raw|
        context "category=#{raw.inspect}" do
          let(:category) { raw }
          it { is_expected.to eq('agenda_block') }
        end
      end
    end

    it 'bloqueio vence sobre paciente presente (Intervalo Almoço com PatientName mantém agenda_block)' do
      expect(described_class.classify_event_type(category: 'Intervalo Almoço', patient_present: true))
        .to eq('agenda_block')
    end

    it 'compromisso vence sobre paciente ausente (Reunião sem paciente continua appointment)' do
      expect(described_class.classify_event_type(category: 'Reunião', patient_present: false))
        .to eq('appointment')
    end
  end

  describe '.normalize_category_for_match' do
    it 'remove acentos e collapsa espaços' do
      expect(described_class.normalize_category_for_match('Intervalo Almoço'))
        .to eq('intervalo_almoco')
    end

    it 'lowercase + strip' do
      expect(described_class.normalize_category_for_match('  REUNIÃO  ')).to eq('reuniao')
    end

    it 'nil e string vazia retornam nil' do
      expect(described_class.normalize_category_for_match(nil)).to be_nil
      expect(described_class.normalize_category_for_match('')).to be_nil
      expect(described_class.normalize_category_for_match('   ')).to be_nil
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Dedup trivial case+accent-insensitive de CategoryDescription
  # (PR audit 2026-05-21): "Avaliação", "AVALIAÇÃO" e "avaliacao" viram UMA
  # opção no dropdown e UM valor único no JSONB, preservando a 1ª forma vista.
  # ──────────────────────────────────────────────────────────────────────────
  describe '#call — dedup trivial de CategoryDescription' do
    let(:account) { create(:account) }
    let(:run) do
      MigrationRun.create!(account_id: account.id, kind: 'agenda', source: 'clinicorp', csv_filename: 'Appointment.csv')
    end

    let(:csv_com_variantes) do
      <<~CSV
        CategoryDescription,DentistName,MobilePhone,Notes,PatientName,Procedures,Status,date,fromTime,id,toTime
        Avaliação,Dr A,(11) 92365-2248,,Paciente Um,,CONFIRMED,2026-05-21T00:00:00Z,09:00,EVT-001,10:00
        AVALIAÇÃO,Dr A,(11) 92365-2248,,Paciente Dois,,CONFIRMED,2026-05-22T00:00:00Z,09:00,EVT-002,10:00
        avaliacao,Dr A,(11) 92365-2248,,Paciente Tres,,CONFIRMED,2026-05-23T00:00:00Z,09:00,EVT-003,10:00
        AVALIAÇÃO (CRC),Dr A,(11) 92365-2248,,Paciente Quatro,,CONFIRMED,2026-05-24T00:00:00Z,09:00,EVT-004,10:00
      CSV
    end

    it 'dropdown da Categoria fica com 2 opções (Avaliação + AVALIAÇÃO (CRC)), não 4' do
      described_class.new(run, csv_com_variantes).call
      attr = AgendaCustomAttribute.where(account_id: account.id)
                                  .where('LOWER(name) = ?', 'categoria').first
      expect(attr).not_to be_nil
      options = attr.options.split(',').map(&:strip)
      # "Avaliação" (1ª vista) absorve "AVALIAÇÃO" e "avaliacao".
      # "AVALIAÇÃO (CRC)" continua distinta (parênteses = diferença semântica).
      expect(options.size).to eq(2)
      expect(options).to include('Avaliação', 'AVALIAÇÃO (CRC)')
    end

    it 'JSONB dos eventos grava a forma canonical (não a forma original do CSV)' do
      described_class.new(run, csv_com_variantes).call
      attr = AgendaCustomAttribute.where(account_id: account.id).where('LOWER(name) = ?', 'categoria').first
      key = "attr_#{attr.id}"

      events = AgendaEvent.where(account_id: account.id).order(:starts_at)
      # Os 3 primeiros eventos (Avaliação / AVALIAÇÃO / avaliacao) gravam todos "Avaliação"
      expect(events[0].custom_attributes[key]).to eq('Avaliação')
      expect(events[1].custom_attributes[key]).to eq('Avaliação')
      expect(events[2].custom_attributes[key]).to eq('Avaliação')
      # O 4º (AVALIAÇÃO (CRC)) preserva original
      expect(events[3].custom_attributes[key]).to eq('AVALIAÇÃO (CRC)')
    end

    it 're-importação respeita canonical histórica do dropdown' do
      # 1º import grava "Avaliação" como canonical
      described_class.new(run, csv_com_variantes).call

      # 2º CSV traz "AVALIAÇÃO" como 1ª linha — mas dropdown já tem "Avaliação"
      csv_v2 = <<~CSV
        CategoryDescription,DentistName,MobilePhone,Notes,PatientName,Procedures,Status,date,fromTime,id,toTime
        AVALIAÇÃO,Dr A,(11) 92365-2248,,Paciente Cinco,,CONFIRMED,2026-05-25T00:00:00Z,09:00,EVT-005,10:00
      CSV
      run2 = MigrationRun.create!(account_id: account.id, kind: 'agenda', source: 'clinicorp', csv_filename: 'Appointment2.csv')
      described_class.new(run2, csv_v2).call

      attr = AgendaCustomAttribute.where(account_id: account.id).where('LOWER(name) = ?', 'categoria').first
      key = "attr_#{attr.id}"
      novo = AgendaEvent.find_by(account_id: account.id, custom_attributes: { source: 'clinicorp', external_id: 'EVT-005' }) ||
             AgendaEvent.where(account_id: account.id).where("custom_attributes->>'external_id' = ?", 'EVT-005').first
      # Mantém "Avaliação" canonical (não vira "AVALIAÇÃO" porque histórico vence)
      expect(novo.custom_attributes[key]).to eq('Avaliação')
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Integração — regressão do B2 (update path ignorava event_type).
  # Garante que re-importar o mesmo external_id corrige eventos legados.
  # ──────────────────────────────────────────────────────────────────────────
  describe '#call — re-importação corrige event_type (regressão B2 PR 2026-05-21)' do
    let(:account) { create(:account) }
    let(:run) do
      MigrationRun.create!(account_id: account.id, kind: 'agenda', source: 'clinicorp', csv_filename: 'Appointment.csv')
    end

    # Telefone placeholder conforme regra (feedback_telefone_placeholder).
    let(:csv_with_category) do
      <<~CSV
        CategoryDescription,DentistName,MobilePhone,Notes,PatientName,Procedures,Status,date,fromTime,id,toTime
        Intervalo Almoço,Dr Teste,(11) 92365-2248,,Paciente Placeholder,,SCHEDULED,2026-05-21T00:00:00Z,12:00,EVT-001,13:00
      CSV
    end

    let(:csv_with_clinical_category) do
      <<~CSV
        CategoryDescription,DentistName,MobilePhone,Notes,PatientName,Procedures,Status,date,fromTime,id,toTime
        Odonto,Dr Teste,(11) 92365-2248,,Paciente Placeholder,limpeza,CONFIRMED,2026-05-21T00:00:00Z,14:00,EVT-001,15:00
      CSV
    end

    it 'segunda importação muda event_type quando a categoria muda no CSV' do
      described_class.new(run, csv_with_category).call
      event = AgendaEvent.find_by!(account_id: account.id)
      expect(event.event_type).to eq('agenda_block')

      # Mesmo external_id (EVT-001), categoria muda de Intervalo Almoço → Odonto.
      # Pré-PR-auditoria-2026-05-21 esse update mantinha o event_type antigo;
      # agora reclassifica.
      described_class.new(run, csv_with_clinical_category).call
      expect(event.reload.event_type).to eq('consultation')
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Multi-tenant — duas contas importando o mesmo external_id não colidem.
  # ──────────────────────────────────────────────────────────────────────────
  describe '#call — isolamento multi-tenant' do
    let(:account_a) { create(:account) }
    let(:account_b) { create(:account) }
    let(:csv) do
      <<~CSV
        CategoryDescription,DentistName,MobilePhone,Notes,PatientName,Procedures,Status,date,fromTime,id,toTime
        Odonto,Dr Teste,(11) 92365-2248,,Paciente Placeholder,limpeza,CONFIRMED,2026-05-21T00:00:00Z,14:00,EVT-001,15:00
      CSV
    end

    it 'cria um evento independente em cada conta com mesmo external_id' do
      run_a = MigrationRun.create!(account_id: account_a.id, kind: 'agenda', source: 'clinicorp', csv_filename: 'Appointment.csv')
      run_b = MigrationRun.create!(account_id: account_b.id, kind: 'agenda', source: 'clinicorp', csv_filename: 'Appointment.csv')

      described_class.new(run_a, csv).call
      described_class.new(run_b, csv).call

      expect(AgendaEvent.where(account_id: account_a.id).count).to eq(1)
      expect(AgendaEvent.where(account_id: account_b.id).count).to eq(1)
      expect(AgendaEvent.where(account_id: account_a.id).first.event_type).to eq('consultation')
      expect(AgendaEvent.where(account_id: account_b.id).first.event_type).to eq('consultation')
    end
  end
end
