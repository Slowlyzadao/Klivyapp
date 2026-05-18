import { computed, ref } from 'vue';

// Detecta gatilho `@<termo>` antes do caret. Retorna { active, query, anchor }.
// Não tenta parsear @ no meio de palavra ("foo@bar.com" não dispara).
const TRIGGER_RE = /(^|\s)@(\S{0,40})$/;

export function useMentionAutocomplete({ candidatesRef, getValue, getCaret, applyReplacement }) {
  const isOpen = ref(false);
  const query = ref('');
  const anchorIndex = ref(-1); // posição do '@' no texto
  const highlightedIndex = ref(0);
  // Separa por tipo pra construir mentioned_user_ids vs mentioned_ai_agent_ids.
  const insertedUserIds = ref(new Set());
  const insertedAiAgentIds = ref(new Set());
  const insertedAll = ref(false); // marca que @todos foi inserido

  const filteredCandidates = computed(() => {
    const list = candidatesRef.value || [];
    if (!query.value) return list.slice(0, 8);
    const q = query.value.toLowerCase();
    return list
      .filter(c => (c.name || '').toLowerCase().includes(q))
      .slice(0, 8);
  });

  const close = () => {
    isOpen.value = false;
    query.value = '';
    anchorIndex.value = -1;
    highlightedIndex.value = 0;
  };

  // Chamar após qualquer edição do textarea/input.
  const evaluate = () => {
    const value = getValue() || '';
    const caret = getCaret();
    const before = value.slice(0, caret);
    const m = before.match(TRIGGER_RE);
    if (!m) {
      close();
      return;
    }
    isOpen.value = true;
    query.value = m[2] || '';
    anchorIndex.value = before.length - m[2].length - 1; // posição do '@'
    if (highlightedIndex.value >= filteredCandidates.value.length) {
      highlightedIndex.value = 0;
    }
  };

  const selectCandidate = candidate => {
    if (!candidate || anchorIndex.value < 0) return;
    const value = getValue() || '';
    const caret = getCaret();
    const before = value.slice(0, anchorIndex.value);
    const after = value.slice(caret);
    let displayName;
    if (candidate.is_all) displayName = 'todos';
    else if (candidate.is_ai) displayName = 'Beatriz';
    else displayName = candidate.name;

    const insertion = `@${displayName} `;
    const next = `${before}${insertion}${after}`;
    const newCaret = (before + insertion).length;

    if (candidate.is_all) insertedAll.value = true;
    else if (candidate.is_ai) insertedAiAgentIds.value.add(candidate.id);
    else insertedUserIds.value.add(candidate.id);

    applyReplacement(next, newCaret);
    close();
  };

  // Navegação com setas (chamada de keydown handler).
  const handleKeydown = event => {
    if (!isOpen.value) return false;
    const list = filteredCandidates.value;
    if (list.length === 0) return false;

    if (event.key === 'ArrowDown') {
      event.preventDefault();
      highlightedIndex.value = (highlightedIndex.value + 1) % list.length;
      return true;
    }
    if (event.key === 'ArrowUp') {
      event.preventDefault();
      highlightedIndex.value =
        (highlightedIndex.value - 1 + list.length) % list.length;
      return true;
    }
    if (event.key === 'Enter' || event.key === 'Tab') {
      event.preventDefault();
      selectCandidate(list[highlightedIndex.value]);
      return true;
    }
    if (event.key === 'Escape') {
      event.preventDefault();
      close();
      return true;
    }
    return false;
  };

  const collectInsertedIds = () => {
    // Verifica quais IDs ainda aparecem no texto (usuário pode ter apagado).
    const value = getValue() || '';
    const userIds = new Set();
    const aiAgentIds = new Set();

    // @todos expande para todos os humanos da sala (exceto o próprio).
    if (insertedAll.value && /@todos\b/i.test(value)) {
      for (const c of candidatesRef.value || []) {
        if (!c.is_ai && !c.is_all) userIds.add(c.id);
      }
    }

    for (const c of candidatesRef.value || []) {
      if (c.is_all) continue;
      const display = c.is_ai ? 'Beatriz' : c.name;
      if (!value.includes(`@${display}`)) continue;
      if (c.is_ai && insertedAiAgentIds.value.has(c.id)) aiAgentIds.add(c.id);
      else if (!c.is_ai && insertedUserIds.value.has(c.id)) userIds.add(c.id);
    }
    return { userIds: [...userIds], aiAgentIds: [...aiAgentIds] };
  };

  const reset = () => {
    insertedUserIds.value = new Set();
    insertedAiAgentIds.value = new Set();
    insertedAll.value = false;
    close();
  };

  return {
    isOpen,
    query,
    filteredCandidates,
    highlightedIndex,
    evaluate,
    handleKeydown,
    selectCandidate,
    collectInsertedIds,
    reset,
    close,
  };
}
