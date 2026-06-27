// Labels e mapeamento de severidade (cor) dos status de SignatureRequest.
// Fonte da verdade: plugins/signatures/app/models/signature_request.rb
// (STATUSES constant). Manter sincronizado.

export const STATUS_LABELS = {
  pending:   'Aguardando envio',
  sent:      'Enviado',
  viewed:    'Visualizado',
  signed:    'Assinado',
  completed: 'Concluído',
  cancelled: 'Cancelado',
  failed:    'Erro',
  expired:   'Expirado',
};

// Kind define a cor visual do badge.
// info/neutral/warning/success/danger são variantes que o CSS implementa.
export const STATUS_KIND = {
  pending:   'neutral',
  sent:      'info',
  viewed:    'info',
  signed:    'warning',   // não é o estado final — falta download
  completed: 'success',
  cancelled: 'neutral',
  failed:    'danger',
  expired:   'danger',
};
