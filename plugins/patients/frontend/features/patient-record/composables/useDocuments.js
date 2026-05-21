/**
 * useDocuments — fetch + mutations da aba Documentos.
 *
 *   fetch()                          → carrega lista
 *   generate(form)                   → POST com payload tipado por document_type;
 *                                      auto-abre PDF retornado em nova aba
 *   download(doc)                    → busca signed URL e abre em nova aba
 *   sendWhatsApp(documentId)         → envia link via WhatsApp
 *   remove(documentId)               → delete + remove local sem refetch
 */

import { ref } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { useI18n } from 'vue-i18n';
import DocumentsAPI from '@plugins/patients/frontend/api/patients/documents';
import {
  DOC_TYPE_LABELS,
  FREE_CONTENT_TYPES,
} from '@plugins/patients/frontend/constants/documents';

const buildVariables = form => {
  const variables = {};
  switch (form.document_type) {
    case 'atestado':
      if (form.cid) variables.cid = form.cid;
      if (form.dias_afastamento) variables.dias_afastamento = form.dias_afastamento;
      break;
    case 'receita':
      if (form.medicamentos) variables.medicamentos = form.medicamentos;
      if (form.posologia) variables.posologia = form.posologia;
      break;
    case 'pedido_exame':
      if (form.exames_solicitados)
        variables.exames_solicitados = form.exames_solicitados;
      break;
    case 'encaminhamento':
      if (form.encaminhado_para) variables.encaminhado_para = form.encaminhado_para;
      if (form.especialidade) variables.especialidade = form.especialidade;
      break;
    default:
      if (FREE_CONTENT_TYPES.includes(form.document_type) && form.conteudo_livre) {
        variables.conteudo = form.conteudo_livre;
      }
  }
  if (form.observacoes) variables.observacoes = form.observacoes;
  return variables;
};

export function useDocuments(patientIdRef) {
  const { t } = useI18n();

  const documents = ref([]);
  const isGenerating = ref(false);

  const resolveId = () =>
    typeof patientIdRef === 'function'
      ? patientIdRef()
      : patientIdRef?.value ?? patientIdRef;

  const fetch = async () => {
    try {
      const res = await DocumentsAPI.get(resolveId());
      documents.value = res.data?.data || res.data || [];
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Documents] Falha ao carregar lista', error);
      useNotification.error(t('PATIENT_DOCUMENTS.MESSAGES.LOAD_ERROR'));
    }
  };

  const generate = async form => {
    isGenerating.value = true;
    try {
      const payload = {
        document_type: form.document_type,
        title:
          form.title ||
          DOC_TYPE_LABELS[form.document_type] ||
          form.document_type,
        variables: buildVariables(form),
      };
      const res = await DocumentsAPI.generate(resolveId(), payload);
      await fetch();
      if (res.data?.url) window.open(res.data.url, '_blank');
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Documents] Falha ao gerar documento', error);
      useNotification.error(t('PATIENT_DOCUMENTS.MESSAGES.GENERATE_ERROR'));
      return { ok: false };
    } finally {
      isGenerating.value = false;
    }
  };

  const download = async doc => {
    if (!doc?.id) return { ok: false };
    try {
      const res = await DocumentsAPI.download(resolveId(), doc.id);
      if (res.data?.url) window.open(res.data.url, '_blank');
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Documents] Falha no download', error);
      useNotification.error(t('PATIENT_DOCUMENTS.MESSAGES.DOWNLOAD_ERROR'));
      return { ok: false };
    }
  };

  // Retorna a URL assinada do PDF sem abrir em nova aba — usado pelo modal de
  // preview que renderiza o PDF dentro de um <iframe>. O SecureBlobsController
  // serve PDFs com `disposition: :inline` same-origin via `send_data`, então
  // o iframe renderiza com o visualizador nativo do browser.
  const fetchPreviewUrl = async doc => {
    if (!doc?.id) return null;
    try {
      const res = await DocumentsAPI.download(resolveId(), doc.id);
      return res.data?.url || null;
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Documents] Falha ao gerar URL de preview', error);
      useNotification.error(t('PATIENT_DOCUMENTS.MESSAGES.DOWNLOAD_ERROR'));
      return null;
    }
  };

  // O backend monta um link wa.me com o PDF (URL assinada de 7 dias) e
  // devolve em `whatsapp_payload.wa_url`. Abrimos em nova aba — o usuário
  // confirma o envio dentro do WhatsApp dele. NÃO marcamos como enviado
  // automaticamente: wa.me só abre a janela, não garante envio.
  const sendWhatsApp = async documentId => {
    if (!documentId) return { ok: false };
    try {
      const res = await DocumentsAPI.sendWhatsApp(resolveId(), documentId);
      const waUrl = res.data?.whatsapp_payload?.wa_url;
      if (!waUrl) {
        useNotification.error(t('PATIENT_DOCUMENTS.MESSAGES.WHATSAPP_ERROR'));
        return { ok: false };
      }
      window.open(waUrl, '_blank', 'noopener,noreferrer');
      useNotification.info(t('PATIENT_DOCUMENTS.MESSAGES.WHATSAPP_OPENED'));
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Documents] Falha ao preparar envio WhatsApp', error);
      useNotification.error(t('PATIENT_DOCUMENTS.MESSAGES.WHATSAPP_ERROR'));
      return { ok: false };
    }
  };

  const remove = async documentId => {
    if (!documentId) return { ok: false };
    try {
      await DocumentsAPI.delete(resolveId(), documentId);
      // Remove local sem refetch — UI atualiza imediato.
      documents.value = documents.value.filter(d => d.id !== documentId);
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Documents] Falha ao excluir', error);
      useNotification.error(t('PATIENT_DOCUMENTS.MESSAGES.DELETE_ERROR'));
      return { ok: false };
    }
  };

  return {
    documents,
    isGenerating,
    fetch,
    generate,
    download,
    fetchPreviewUrl,
    sendWhatsApp,
    remove,
  };
}
