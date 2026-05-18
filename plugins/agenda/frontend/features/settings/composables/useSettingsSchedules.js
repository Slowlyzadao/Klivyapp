import { ref } from 'vue';

export function useSettingsSchedules(props, emit) {
  // Funções Puras de UI (formatadores, metadados)
  const getDayStatus = (day) => {
    if (!day.enabled) return { label: 'Fechado', cls: 'closed' };
    return { label: 'Aberto', cls: 'open' };
  };

  const getExceptionMeta = (type) => {
    const meta = {
      'Congresso / Eventos / Reunião': { icon: 'i-lucide-users', color: 'blue' },
      'Folga / Outros': { icon: 'i-lucide-sun', color: 'yellow' },
      'Férias': { icon: 'i-lucide-palmtree', color: 'green' },
      'Manutenção': { icon: 'i-lucide-wrench', color: 'purple' },
    };
    return meta[type] || { icon: 'i-lucide-calendar', color: 'slate' };
  };

  // Dropdown Management for Exception Categories
  const openDropdownIndex = ref(null);
  const dropdownPos = ref(null);

  const exceptionCategories = [
    'Congresso / Eventos / Reunião',
    'Folga / Outros',
    'Férias',
    'Manutenção',
  ];

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

  const selectCategory = (ex, cat) => {
    ex.type = cat;
    openDropdownIndex.value = null;
    dropdownPos.value = null;
  };

  // Locale configuration for DatePicker (if needed locally)
  const ptBrLang = {
    formatLocale: {
      months: ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'],
      monthsShort: ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'],
      weekdays: ['Domingo', 'Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira', 'Sexta-feira', 'Sábado'],
      weekdaysShort: ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'],
      weekdaysMin: ['Do', 'Se', 'Te', 'Qu', 'Qu', 'Se', 'Sá'],
      firstDayOfWeek: 0,
      firstWeekContainsDate: 1,
    },
    monthBeforeYear: false,
  };

  const toggleHolidayStatus = (hol) => {
    hol.status = hol.status === 'open' ? 'closed' : 'open';
  };

  const addException = () => {
    emit('add-exception');
  };

  const removeException = (index) => {
    emit('remove-exception', index);
  };

  const saveChanges = () => {
    emit('save-changes');
  };

  return {
    getDayStatus,
    getExceptionMeta,
    exceptionCategories,
    openDropdownIndex,
    dropdownPos,
    toggleDropdown,
    selectCategory,
    ptBrLang,
    toggleHolidayStatus,
    addException,
    removeException,
    saveChanges
  };
}
