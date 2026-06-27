require 'rails_helper'

RSpec.describe AiAgent::ChatService::StateMachineUpdater do
  # Fake do ConversationContext: captura as chamadas sem tocar no banco.
  let(:ctx_state) do
    Class.new do
      attr_reader :offers, :listed_id

      def initialize
        @offers = []
        @ambiguous = false
      end

      def set_active_service!(**); end
      def remember_listed_appointment!(id) = @listed_id = id
      def remember_ambiguous_listing! = @ambiguous = true
      def recent_listing_ambiguous? = @ambiguous
      def recent_listed_appointment_id = @listed_id
      def offer_slot!(**kwargs) = @offers << kwargs
    end.new
  end

  def slots_result(slots, requested_time: nil)
    {
      available: true,
      service: { id: 13, name: 'Avaliação', duration_minutes: 60 },
      requested_time: requested_time,
      slots: slots.map do |time|
        { starts_at: "2026-06-15T#{time}:00-03:00", time: time, date: '15/06/2026',
          available_with: [{ id: 721, name: 'Henrique Carvalho' }] }
      end
    }
  end

  # Regressão 2026-06-11: paciente pediu 15h; slots vieram [09h, 15h, 17h];
  # a oferta pendente ficou no PRIMEIRO slot (09h) e o "Sim" bookou 09:00.
  it 'oferta pendente é o slot do requested_time, não o primeiro da lista' do
    described_class.record(ctx_state, 'search_available_slots', slots_result(%w[09:00 15:00 17:00], requested_time: '15:00'))

    expect(ctx_state.offers.last[:starts_at]).to eq('2026-06-15T15:00:00-03:00')
  end

  it 'sem requested_time, oferta segue sendo o primeiro slot' do
    described_class.record(ctx_state, 'search_available_slots', slots_result(%w[09:00 15:00 17:00]))

    expect(ctx_state.offers.last[:starts_at]).to eq('2026-06-15T09:00:00-03:00')
  end

  # Regressão 2026-06-11: paciente tinha 2 consultas e pediu remarcação; o
  # "Sim" determinístico criou um TERCEIRO agendamento. Com 2+ listadas, a
  # oferta nasce ambígua e o auto-book fica proibido.
  it 'listagem com 2+ consultas marca a oferta como ambiguous_reschedule' do
    described_class.record(ctx_state, 'list_appointments', { appointments: [{ id: 1 }, { id: 2 }] })
    described_class.record(ctx_state, 'search_available_slots', slots_result(%w[09:00 15:00]))

    expect(ctx_state.offers.last[:ambiguous_reschedule]).to be(true)
  end

  it 'listagem com 1 consulta vira target_appointment_id (remarcação dirigida)' do
    described_class.record(ctx_state, 'list_appointments', { appointments: [{ id: 42 }] })
    described_class.record(ctx_state, 'search_available_slots', slots_result(%w[09:00]))

    expect(ctx_state.offers.last[:target_appointment_id]).to eq(42)
    expect(ctx_state.offers.last[:ambiguous_reschedule]).to be(false)
  end
end
