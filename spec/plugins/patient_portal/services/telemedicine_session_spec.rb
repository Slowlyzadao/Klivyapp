require 'rails_helper'

RSpec.describe Telemed::Session do
  let(:account) { create(:account) }

  # AgendaEvent stub mínimo — não precisamos do model real pra exercitar a regra.
  def event(custom: {}, starts_at: 1.hour.from_now, ends_at: 2.hours.from_now,
            status: 'scheduled', discarded: false)
    OpenStruct.new(
      custom_attributes: custom,
      starts_at: starts_at, ends_at: ends_at,
      status: status, account: account,
      discarded?: discarded
    )
  end

  describe '#call — habilitação' do
    it 'retorna enabled=false quando custom_attributes vazio' do
      r = described_class.new(event: event).call
      expect(r.enabled?).to eq(false)
      expect(r.reason).to eq('not_configured')
    end

    it 'retorna enabled=false quando flag falsa mesmo com URL' do
      attrs = { 'telemedicine_enabled' => false, 'telemedicine_url' => 'https://meet.test/abc' }
      r = described_class.new(event: event(custom: attrs)).call
      expect(r.enabled?).to eq(false)
    end

    it 'Sprint K — URL é opcional (sala interna gerada on-demand pelo SessionIssuer)' do
      attrs = { 'telemedicine_enabled' => true } # sem URL
      r = described_class.new(event: event(custom: attrs)).call
      expect(r.enabled?).to eq(true)
      expect(r.url).to be_nil
    end

    it 'retorna enabled=true + provider default livekit' do
      attrs = { 'telemedicine_enabled' => true, 'telemedicine_url' => 'https://meet.test/abc' }
      r = described_class.new(event: event(custom: attrs)).call
      expect(r.enabled?).to eq(true)
      expect(r.provider).to eq('livekit')
      expect(r.url).to eq('https://meet.test/abc')
    end

    it 'respeita provider explícito (futuro: jitsi/zoom/etc)' do
      attrs = { 'telemedicine_enabled' => true, 'telemedicine_url' => 'x', 'telemedicine_provider' => 'jitsi' }
      r = described_class.new(event: event(custom: attrs)).call
      expect(r.provider).to eq('jitsi')
    end
  end

  describe '#call — janela de liberação (defaults pre=10 post=30)' do
    let(:attrs) { { 'telemedicine_enabled' => true, 'telemedicine_url' => 'https://meet.test/abc' } }

    it 'too_early se ainda falta mais de 10 min pro início' do
      e = event(custom: attrs, starts_at: 30.minutes.from_now, ends_at: 90.minutes.from_now)
      r = described_class.new(event: e).call
      expect(r.can_join_now?).to eq(false)
      expect(r.reason).to eq('too_early')
    end

    it 'in_window quando faltam <= 10 min pro início' do
      e = event(custom: attrs, starts_at: 5.minutes.from_now, ends_at: 65.minutes.from_now)
      r = described_class.new(event: e).call
      expect(r.can_join_now?).to eq(true)
      expect(r.reason).to eq('in_window')
    end

    it 'in_window durante a consulta' do
      e = event(custom: attrs, starts_at: 5.minutes.ago, ends_at: 55.minutes.from_now)
      r = described_class.new(event: e).call
      expect(r.can_join_now?).to eq(true)
    end

    it 'in_window até 30 min após o término' do
      e = event(custom: attrs, starts_at: 90.minutes.ago, ends_at: 20.minutes.ago)
      r = described_class.new(event: e).call
      expect(r.can_join_now?).to eq(true)
    end

    it 'window_closed após 30 min do término' do
      e = event(custom: attrs, starts_at: 2.hours.ago, ends_at: 1.hour.ago)
      r = described_class.new(event: e).call
      expect(r.can_join_now?).to eq(false)
      expect(r.reason).to eq('window_closed')
    end
  end

  describe '#call — status do AgendaEvent' do
    let(:attrs) { { 'telemedicine_enabled' => true, 'telemedicine_url' => 'https://meet.test/abc' } }

    it 'bloqueia status completed' do
      e = event(custom: attrs, status: 'completed', starts_at: 5.minutes.from_now, ends_at: 65.minutes.from_now)
      r = described_class.new(event: e).call
      expect(r.can_join_now?).to eq(false)
      expect(r.reason).to eq('event_not_joinable')
    end

    it 'bloqueia status no_show' do
      e = event(custom: attrs, status: 'no_show', starts_at: 5.minutes.from_now, ends_at: 65.minutes.from_now)
      r = described_class.new(event: e).call
      expect(r.can_join_now?).to eq(false)
    end

    it 'bloqueia eventos cancelados (discarded)' do
      e = event(custom: attrs, status: 'scheduled', starts_at: 5.minutes.from_now, ends_at: 65.minutes.from_now, discarded: true)
      r = described_class.new(event: e).call
      expect(r.can_join_now?).to eq(false)
      expect(r.reason).to eq('event_cancelled')
    end

    it 'permite status in_progress' do
      e = event(custom: attrs, status: 'in_progress', starts_at: 5.minutes.ago, ends_at: 55.minutes.from_now)
      r = described_class.new(event: e).call
      expect(r.can_join_now?).to eq(true)
    end
  end

  describe '#call — janela configurável pelo PatientPortalSetting' do
    let(:attrs) { { 'telemedicine_enabled' => true, 'telemedicine_url' => 'https://meet.test/abc' } }

    before do
      PatientPortalSetting.create!(
        account: account, active_preset: 'autonomy_guided',
        scheduling: { 'telemedicine_pre_minutes' => 30, 'telemedicine_post_minutes' => 5 }
      )
    end

    it 'usa pre=30 do setting (libera 30 min antes)' do
      e = event(custom: attrs, starts_at: 20.minutes.from_now, ends_at: 80.minutes.from_now)
      r = described_class.new(event: e, account: account).call
      expect(r.can_join_now?).to eq(true)
    end

    it 'usa post=5 do setting (fecha 5 min após)' do
      e = event(custom: attrs, starts_at: 65.minutes.ago, ends_at: 10.minutes.ago)
      r = described_class.new(event: e, account: account).call
      expect(r.can_join_now?).to eq(false)
      expect(r.reason).to eq('window_closed')
    end
  end

  describe '#call — informativos' do
    let(:attrs) { { 'telemedicine_enabled' => true, 'telemedicine_url' => 'https://meet.test/abc' } }

    it 'expõe starts_in_seconds e ends_in_seconds' do
      e = event(custom: attrs, starts_at: 120.seconds.from_now, ends_at: 3600.seconds.from_now)
      r = described_class.new(event: e).call
      expect(r.starts_in_seconds).to be_within(2).of(120)
      expect(r.ends_in_seconds).to   be_within(2).of(3600)
    end

    it 'to_h serializa todos os campos relevantes' do
      e = event(custom: attrs, starts_at: 5.minutes.from_now, ends_at: 65.minutes.from_now)
      h = described_class.new(event: e).call.to_h
      expect(h.keys).to include(:enabled, :url, :provider, :can_join_now, :reason)
    end
  end
end
