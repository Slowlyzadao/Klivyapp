require 'rails_helper'

RSpec.describe AiAgent::Multimodal::ImageHandler do
  # build_result é puro (não chama OpenAI) — testamos só o roteamento por
  # categoria, que é o que decide responder x escalar.
  def route(category)
    described_class.new(attachment: nil).send(:build_result, category)
  end

  it 'greeting é uma categoria válida do classificador' do
    expect(described_class::VALID_CATEGORIES).to include('greeting')
  end

  it 'saudação/social responde com carinho e NÃO escala (sem nota pra equipe)' do
    result = route('greeting')

    expect(result.handoff_required).to be(false)
    expect(result.staff_note).to be_nil
    expect(result.patient_message).to be_present
  end

  it 'conteúdo clínico/documento continua escalando pra humano (CFM)' do
    %w[prescription clinical_photo exam_image document other].each do |category|
      result = route(category)
      expect(result.handoff_required).to be(true), "esperava handoff para #{category}"
      expect(result.staff_note).to be_present
    end
  end
end
