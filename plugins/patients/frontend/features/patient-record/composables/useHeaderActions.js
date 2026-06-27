import { useRouter, useRoute } from 'vue-router';
import ContactAPI from 'dashboard/api/contacts';

export function useHeaderActions({ patient, activeTab }) {
  const router = useRouter();
  const route = useRoute();

  const handleHeaderSchedule = () => {
    router.push({
      name: 'agenda_dashboard_index',
      params: { accountId: route.params.accountId },
      query: {
        newEvent: '1',
        contactId: patient.value.contact_id || '',
        patientName: patient.value.name || '',
        patientPhone: patient.value.phone || '',
      },
    });
  };

  const handleHeaderCharge = () => {
    activeTab.value = 'financial';
  };

  const handleHeaderStartService = async () => {
    if (!patient.value.contact_id) {
      router.push({
        name: 'home',
        params: { accountId: route.params.accountId },
      });
      return;
    }
    try {
      const response = await ContactAPI.getConversations(
        patient.value.contact_id
      );
      const conversations = response.data?.payload || [];
      if (conversations.length > 0) {
        const sorted = [...conversations].sort((a, b) => b.id - a.id);
        router.push({
          name: 'inbox_conversation',
          params: {
            accountId: route.params.accountId,
            conversation_id: sorted[0].id,
          },
        });
      } else {
        router.push({
          name: 'home',
          params: { accountId: route.params.accountId },
        });
      }
    } catch (e) {
      router.push({
        name: 'home',
        params: { accountId: route.params.accountId },
      });
    }
  };

  return {
    handleHeaderSchedule,
    handleHeaderCharge,
    handleHeaderStartService,
  };
}
