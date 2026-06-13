# frozen_string_literal: true

require 'rails_helper'

# Cobre o filtro `financial_status` da listagem de pacientes.
# Canon (decisão do cliente 2026-06-01): "inadimplente" = tem parcela VENCIDA
# (due_date < hoje) em aberto com saldo > 0. Quem só tem parcela a vencer ou
# está tudo quitado é "adimplente".
RSpec.describe 'Patients API — filtro de situação financeira', type: :request do
  let!(:account) { create(:account) }
  let!(:admin)   { create(:user, account: account, role: 'administrator') }

  let!(:overdue_patient) { create(:patient, account: account, name: 'Devedor Vencido') }
  let!(:future_patient)  { create(:patient, account: account, name: 'Parcela A Vencer') }
  let!(:paid_patient)    { create(:patient, account: account, name: 'Tudo Quitado') }

  let(:base_path) { "/api/v1/accounts/#{account.id}/patients" }

  def create_installment(patient, status:, due_date:, amount: 50_000, received: 0)
    budget = Financial::Budget.create!(
      account: account, patient: patient, origin: 'orcamento', status: 'concluido',
      installments_count: 1, subtotal_cents: amount, total_cents: amount
    )
    Financial::Installment.create!(
      account: account, patient: patient, budget: budget,
      number: 1, total_in_series: 1,
      amount_cents: amount, received_amount_cents: received, status: status,
      due_date: due_date, competence_date: due_date
    )
  end

  before do
    # Vencida em aberto → inadimplente
    create_installment(overdue_patient, status: 'pendente', due_date: 1.month.ago.to_date)
    # A vencer (futuro) → adimplente/em dia
    create_installment(future_patient, status: 'pendente', due_date: 1.month.from_now.to_date)
    # Quitada → adimplente
    create_installment(paid_patient, status: 'recebido', due_date: 1.month.ago.to_date, received: 50_000)
  end

  def payload_ids(response)
    JSON.parse(response.body)['payload'].map { |p| p['id'] }
  end

  it 'retorna só inadimplentes (parcela vencida em aberto)' do
    get base_path, params: { financial_status: 'inadimplente', per_page: 200 },
                   headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    ids = payload_ids(response)
    expect(ids).to include(overdue_patient.id)
    expect(ids).not_to include(future_patient.id, paid_patient.id)
  end

  it 'retorna adimplentes (a vencer e quitados, nunca os vencidos)' do
    get base_path, params: { financial_status: 'adimplente', per_page: 200 },
                   headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    ids = payload_ids(response)
    expect(ids).to include(future_patient.id, paid_patient.id)
    expect(ids).not_to include(overdue_patient.id)
  end

  it 'sem o filtro retorna todos' do
    get base_path, params: { per_page: 200 },
                   headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    ids = payload_ids(response)
    expect(ids).to include(overdue_patient.id, future_patient.id, paid_patient.id)
  end

  it 'expõe saldo total e recorte vencido (overdue_cents) no payload' do
    get base_path, params: { per_page: 200 },
                   headers: admin.create_new_auth_token, as: :json

    by_id = JSON.parse(response.body)['payload'].index_by { |p| p['id'] }
    # `SUM(expr)` volta como BigDecimal (serializado string "50000.0"); o front
    # já normaliza via `Number()`. Coagimos com `.to_i` pra comparar centavos.
    # Vencida: saldo total = vencido
    expect(by_id[overdue_patient.id]['balance_due_cents'].to_i).to eq(50_000)
    expect(by_id[overdue_patient.id]['overdue_cents'].to_i).to eq(50_000)
    # A vencer: saldo total em aberto, nada vencido
    expect(by_id[future_patient.id]['balance_due_cents'].to_i).to eq(50_000)
    expect(by_id[future_patient.id]['overdue_cents'].to_i).to eq(0)
  end
end
