import { ref, computed, nextTick } from 'vue';
import { useAlert } from 'dashboard/composables';
import AgendaNotificationLogsAPI from '@plugins/agenda/frontend/api/agendaNotificationLogs';

export function useSettingsNotifications(store) {
  const notifRuleTypes = [
    { value: 'reminder', icon: 'i-lucide-bell', label: 'Lembrete de consulta', hint: 'Enviar X horas antes da consulta' },
    { value: 'confirmation', icon: 'i-lucide-calendar-check', label: 'Confirmação de agendamento', hint: 'Enviar ao criar o agendamento' },
    { value: 'followup', icon: 'i-lucide-refresh-cw', label: 'Follow-up / Pós-consulta', hint: 'Enviar após a consulta ou no-show' },
    { value: 'birthday', icon: 'i-lucide-gift', label: 'Aniversário do paciente', hint: 'Enviar no dia do aniversário' },
    { value: 'custom', icon: 'i-lucide-settings-2', label: 'Personalizado', hint: 'Configuração manual de disparo' },
  ];

  const notifVars = [
    { key: '{nome_paciente}', desc: 'Nome completo do paciente' },
    { key: '{nome_clinica}', desc: 'Nome da clínica/conta' },
    { key: '{nome_profissional}', desc: 'Nome do profissional responsável' },
    { key: '{data_agendada}', desc: 'Data do agendamento' },
    { key: '{horario_consulta}', desc: 'Horário da consulta' },
    { key: '{link_confirmacao}', desc: 'Link de confirmação online' },
  ];

  const notifIconOptions = [
    { value: 'i-lucide-message-circle', icon: 'i-lucide-message-circle', label: 'Mensagem' },
    { value: 'i-lucide-bell', icon: 'i-lucide-bell', label: 'Sino' },
    { value: 'i-lucide-x-circle', icon: 'i-lucide-x-circle', label: 'X' },
    { value: 'i-lucide-heart', icon: 'i-lucide-heart', label: 'Coração' },
    { value: 'i-lucide-cake', icon: 'i-lucide-cake', label: 'Bolo' },
    { value: 'i-lucide-star', icon: 'i-lucide-star', label: 'Estrela' },
    { value: 'i-lucide-calendar-check', icon: 'i-lucide-calendar-check', label: 'Calendário' },
    { value: 'i-lucide-user-check', icon: 'i-lucide-user-check', label: 'Usuário' },
  ];

  const notifIconColors = [
    { value: 'green', label: 'Verde' },
    { value: 'blue', label: 'Azul' },
    { value: 'red', label: 'Vermelho' },
    { value: 'pink', label: 'Rosa' },
    { value: 'purple', label: 'Roxo' },
    { value: 'yellow', label: 'Amarelo' },
    { value: 'orange', label: 'Laranja' },
  ];

  const notifEditModal = ref(false);
  const notifEditTarget = ref(null);
  const previewRuleIds = ref([]);
  
  const notifAiModal = ref(false);
  const notifAiTarget = ref(null);
  const notifAiAction = ref(null);
  const notifAiLoading = ref(false);
  const notifAiResult = ref('');

  const notifNewModal = ref(false);
  const notifNewDraft = ref(null);

  // Logs state
  const logsOpen = ref(false);
  const logsLoading = ref(false);
  const logsData = ref([]);
  const logsMeta = ref({ total: 0, page: 1, per_page: 25 });
  const logsFilter = ref('');

  // Dropdown states for inboxes
  const openDropdownIndex = ref(null);
  const dropdownPos = ref(null);

  // Getters
  const notifRules = computed(() => store.getters['agendaNotificationRules/allRules']);
  const notifRulesLoading = computed(() => store.getters['agendaNotificationRules/getUIFlags'].isFetching);
  const availableInboxes = computed(() => store.getters['inboxes/getInboxes'] || []);
  
  const showNewInboxDropdown = computed(() => openDropdownIndex.value === 'new_inbox');
  const showEditInboxDropdown = computed(() => openDropdownIndex.value === 'edit_inbox');

  const toggleDropdown = (index, event) => {
    if (openDropdownIndex.value === index) {
      openDropdownIndex.value = null;
      dropdownPos.value = null;
    } else {
      const rect = event.currentTarget.getBoundingClientRect();
      dropdownPos.value = {
        top: rect.bottom + 4,
        left: rect.left,
        width: rect.width,
      };
      openDropdownIndex.value = index;
    }
  };

  // ─── UTILS ───
  const highlightVars = (text) => {
    if (!text) return '';
    return text.replace(/\{[a-zA-Z_]+\}/g, m => `<span class="msg-var("${m}")>${m}</span>`);
  };

  const ruleIconColorHex = (colorName) => {
    const map = {
      green: '#22c55e', blue: '#3b82f6', red: '#ef4444',
      pink: '#ec4899', purple: '#a855f7', yellow: '#eab308',
      orange: '#f97316',
    };
    return map[colorName] || '#94a3b8';
  };

  const ruleTypeLabel = (type) => {
    const labels = {
      confirmation: 'Confirmação', followup: 'Follow-up',
      birthday: 'Aniversário', custom: 'Custom',
    };
    return labels[type] || type;
  };

  const formatOffset = (rule) => {
    const hours = rule.trigger_offset_hours;
    if (!hours && hours !== 0) return null;
    const h = Number(hours);
    const isBefore = rule.rule_type === 'reminder';
    const dirText = isBefore ? 'antes' : 'após';
    if (h === 0) return 'No momento';
    if (h < 1) return `${Math.round(h * 60)}min ${dirText}`;
    if (h === 1) return `1h ${dirText}`;
    if (h < 24) return `${h}h ${dirText}`;
    const days = Math.floor(h / 24);
    const rem = h % 24;
    if (rem === 0) return `${days}d ${dirText}`;
    return `${days}d ${rem}h ${dirText}`;
  };

  const formatDateTime = (isoStr) => {
    if (!isoStr) return '—';
    const d = new Date(isoStr);
    return d.toLocaleString('pt-BR', {
      day: '2-digit', month: '2-digit', year: 'numeric',
      hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo',
    });
  };

  const togglePreview = (ruleId) => {
    const idx = previewRuleIds.value.indexOf(ruleId);
    if (idx > -1) previewRuleIds.value.splice(idx, 1);
    else previewRuleIds.value.push(ruleId);
  };

  const getPreviewText = (message) => {
    if (!message) return '';
    const fakeData = {
      nome_paciente: 'Gabriel',
      nome_clinica: 'BeClinic',
      nome_profissional: 'Dr. Oliveira',
      data_agendada: '15/03/2026',
      horario_consulta: '14:30',
      link_confirmacao: 'https://klivy.app/xyz',
    };
    return message.replace(/\{([a-zA-Z_]+)\}/g, (match, p1) => {
      const val = fakeData[p1];
      return val ? `<span class="msg-var">$\{val\}</span>` : match;
    });
  };

  // ─── EDIT MODAL ───
  const openEditModal = (rule) => {
    const clone = JSON.parse(JSON.stringify(rule));
    if (clone.trigger_offset_hours !== null && clone.trigger_offset_hours < 1 && clone.trigger_offset_hours > 0) {
      clone._offsetUnit = 'minutes';
      clone.trigger_offset_hours = Math.round(clone.trigger_offset_hours * 60);
    } else if (clone.trigger_offset_hours !== null && clone.trigger_offset_hours >= 24 && clone.trigger_offset_hours % 24 === 0) {
      clone._offsetUnit = 'days';
      clone.trigger_offset_hours /= 24;
    } else {
      clone._offsetUnit = 'hours';
    }
    notifEditTarget.value = clone;
    notifEditModal.value = true;
  };

  const closeEditModal = () => {
    notifEditModal.value = false;
    notifEditTarget.value = null;
  };

  const saveEditModal = async () => {
    if (!notifEditTarget.value) return;
    const { id, _offsetUnit, ...updateData } = notifEditTarget.value;
    if (_offsetUnit === 'minutes' && updateData.trigger_offset_hours) {
      updateData.trigger_offset_hours /= 60;
    } else if (_offsetUnit === 'days' && updateData.trigger_offset_hours) {
      updateData.trigger_offset_hours *= 24;
    }
    try {
      await store.dispatch('agendaNotificationRules/update', { id, ...updateData });
      closeEditModal();
      useAlert('Regra atualizada!');
    } catch (e) {
      console.error('[AgendaSettings] Falha ao atualizar regra:', e);
      useAlert('Falha ao atualizar regra.');
    }
  };

  // ─── AI MODAL ───
  const openAiModal = (rule) => {
    notifAiTarget.value = JSON.parse(JSON.stringify(rule));
    notifAiAction.value = null;
    notifAiResult.value = '';
    notifAiModal.value = true;
  };

  const closeAiModal = () => {
    notifAiModal.value = false;
    notifAiTarget.value = null;
    notifAiResult.value = '';
  };

  const runAiAction = async (action) => {
    notifAiAction.value = action;
    notifAiLoading.value = true;
    notifAiResult.value = '';
    try {
      // API call simulated as in the original component
      const msg = notifAiTarget.value.message;
      await new Promise(resolve => setTimeout(resolve, 800));
      const actions = {
        grammar: `(Corrigido) ${msg}`,
        improve: `(Melhorado) ${msg}`,
        professional: `Prezado(a) paciente, ${msg}`,
        friendly: `Oiê! ${msg} :)`,
      };
      notifAiResult.value = actions[action] || msg;
    } finally {
      notifAiLoading.value = false;
    }
  };

  const applyAiResult = async () => {
    if (!notifAiResult.value || !notifAiTarget.value) return;
    try {
      await store.dispatch('agendaNotificationRules/update', {
        id: notifAiTarget.value.id,
        message: notifAiResult.value,
      });
      useAlert('Sugestão aplicada!');
      closeAiModal();
    } catch (e) {
      useAlert('Falha ao aplicar sugestão.');
    }
  };

  // ─── NEW MODAL ───
  const openNewModal = () => {
    notifNewDraft.value = {
      title: '', rule_type: 'reminder', trigger_offset_hours: 24, _offsetUnit: 'hours',
      message: 'Olá {nome_paciente}, sua consulta está agendada para {data_agendada} às {horario_consulta}.',
      icon: 'i-lucide-bell', iconColor: 'blue', inboxes: [], _newInbox: '',
    };
    notifNewModal.value = true;
  };

  const closeNewModal = () => {
    notifNewModal.value = false;
    notifNewDraft.value = null;
  };

  const saveNewRule = async () => {
    if (!notifNewDraft.value.title.trim() || !notifNewDraft.value.message.trim()) return;
    const { _newInbox, id: _tempId, _offsetUnit, ...ruleData } = notifNewDraft.value;
    if (_offsetUnit === 'minutes' && ruleData.trigger_offset_hours) {
      ruleData.trigger_offset_hours /= 60;
    } else if (_offsetUnit === 'days' && ruleData.trigger_offset_hours) {
      ruleData.trigger_offset_hours *= 24;
    }
    try {
      await store.dispatch('agendaNotificationRules/create', ruleData);
      closeNewModal();
      useAlert('Nova regra criada!');
    } catch (e) {
      console.error('[AgendaSettings] Falha ao criar regra:', e);
      useAlert('Falha ao criar regra.');
    }
  };

  const deleteNotifRule = async (ruleId) => {
    if (!confirm('Deseja realmente excluir esta regra automática?')) return;
    try {
      await store.dispatch('agendaNotificationRules/delete', ruleId);
      useAlert('Regra excluída.');
    } catch (e) {
      console.error('Falha ao excluir:', e);
      useAlert('Falha ao excluir.');
    }
  };

  // ─── INBOXES LOGIC ───
  const toggleNewInbox = (inbox) => {
    const idx = notifNewDraft.value.inboxes.findIndex(i => i.inbox_id === inbox.id);
    if (idx > -1) {
      notifNewDraft.value.inboxes.splice(idx, 1);
    } else {
      notifNewDraft.value.inboxes.push({ inbox_id: inbox.id, label: inbox.name, color: 'wa' });
    }
  };

  const isNewInboxSelected = (inbox) => {
    if (!notifNewDraft.value || !notifNewDraft.value.inboxes || !inbox) return false;
    return notifNewDraft.value.inboxes.some(i => i.inbox_id === inbox.id);
  };

  const toggleEditInbox = (inbox) => {
    if (!notifEditTarget.value) return;
    const idx = notifEditTarget.value.inboxes.findIndex(i => i.inbox_id === inbox.id);
    if (idx > -1) {
      notifEditTarget.value.inboxes.splice(idx, 1);
    } else {
      notifEditTarget.value.inboxes.push({ inbox_id: inbox.id, label: inbox.name, color: 'wa' });
    }
  };

  const isEditInboxSelected = (inbox) => {
    if (!notifEditTarget.value || !notifEditTarget.value.inboxes || !inbox) return false;
    return notifEditTarget.value.inboxes.some(i => i.inbox_id === inbox.id);
  };

  // ─── LOGS PANEL ───
  const toggleLogsPanel = () => {
    logsOpen.value = !logsOpen.value;
    if (logsOpen.value && logsData.value.length === 0) {
      fetchLogs();
    }
  };

  const fetchLogs = async (page = 1) => {
    logsLoading.value = true;
    try {
      const response = await AgendaNotificationLogsAPI.getLogs({
        status: logsFilter.value || undefined,
        page,
        per_page: 25,
      });
      logsData.value = response.data.logs || [];
      logsMeta.value = response.data.meta || { total: 0, page: 1, per_page: 25 };
    } catch (e) {
      console.error('[AgendaSettings] Falha ao carregar logs:', e);
    } finally {
      logsLoading.value = false;
    }
  };

  // ─── VAR INSERTION (refs used locally inside component) ───
  // Requer que o componente .vue passe uma referência ($refs) do textarea
  const insertVar = (varKey, targetDraft, textareaRef) => {
    if (!textareaRef) {
      targetDraft.message += varKey;
      return;
    }
    const s = textareaRef.selectionStart;
    const e = textareaRef.selectionEnd;
    const v = targetDraft.message;
    targetDraft.message = v.substring(0, s) + varKey + v.substring(e);
    nextTick(() => {
      textareaRef.focus();
      textareaRef.setSelectionRange(s + varKey.length, s + varKey.length);
    });
  };

  const insertVarInEdit = (varKey, ref) => insertVar(varKey, notifEditTarget.value, ref);
  const insertVarInNew = (varKey, ref) => insertVar(varKey, notifNewDraft.value, ref);

  return {
    notifRuleTypes, notifVars, notifIconOptions, notifIconColors,
    notifEditModal, notifEditTarget, previewRuleIds,
    notifAiModal, notifAiTarget, notifAiAction, notifAiLoading, notifAiResult,
    notifNewModal, notifNewDraft,
    logsOpen, logsLoading, logsData, logsMeta, logsFilter,
    openDropdownIndex, dropdownPos, showNewInboxDropdown, showEditInboxDropdown,
    notifRules, notifRulesLoading, availableInboxes,
    highlightVars, ruleIconColorHex, ruleTypeLabel, formatOffset, formatDateTime,
    togglePreview, getPreviewText, toggleDropdown,
    openEditModal, closeEditModal, saveEditModal,
    openAiModal, closeAiModal, runAiAction, applyAiResult,
    openNewModal, closeNewModal, saveNewRule, deleteNotifRule,
    toggleNewInbox, isNewInboxSelected, toggleEditInbox, isEditInboxSelected,
    toggleLogsPanel, fetchLogs, insertVarInEdit, insertVarInNew
  };
}
