<script setup>
/**
 * SessionFormModal — modal completo de cadastro/edição de sessão de evolução.
 *
 * Reúne todos os campos do modal "Novo" (queixa, avaliação, área, procedimento,
 * produto/lote/validade, intercorrências, resultado, próxima consulta, retorno,
 * observação, profissional). Substitui o antigo SessionFormCard inline.
 */
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import { blankSession } from '@plugins/patients/frontend/constants/evolution';

const props = defineProps({
  open: { type: Boolean, default: false },
  initialSession: { type: Object, default: null },
  editingId: { type: [Number, String], default: null },
  pendingItemOptions: { type: Array, default: () => [] },
  professionalOptions: { type: Array, default: () => [] },
  isSaving: { type: Boolean, default: false },
  canSign: { type: Boolean, default: false },
});

const emit = defineEmits([
  'close',
  'save',
  'select-treatment-item',
]);

const { t } = useI18n();
const formData = ref(blankSession());

watch(
  () => props.open,
  isOpen => {
    if (isOpen) {
      formData.value = props.initialSession
        ? { ...blankSession(), ...props.initialSession }
        : blankSession();
    }
  },
  { immediate: true }
);

const isEditing = computed(() => props.editingId !== null);

const onTreatmentItemSelected = itemId => {
  formData.value.treatment_item_id = itemId || null;
  emit('select-treatment-item', itemId);
};

const handleSubmit = sign => {
  emit('save', { payload: { ...formData.value }, sign });
};

const handleReturnInDaysInput = e => {
  const v = e.target.value;
  formData.value.return_in_days = v === '' ? null : Number(v);
  formData.value.return_needed = !!formData.value.return_in_days;
};
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md"
    @click.self="emit('close')"
  >
    <div class="evo-form-modal">
      <div class="evo-modal-header">
        <div class="flex items-center gap-3">
          <div class="evo-modal-icon">
            <i class="i-lucide-syringe w-4 h-4" />
          </div>
          <div>
            <h4 class="text-base font-semibold text-slate-100">
              {{
                isEditing
                  ? t('PATIENT_EVOLUTION.MODAL.TITLE_EDIT')
                  : t('PATIENT_EVOLUTION.MODAL.TITLE_NEW')
              }}
            </h4>
          </div>
        </div>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          @click="emit('close')"
        />
      </div>

      <div class="evo-modal-body">
        <!-- Seção 1: Informações básicas -->
        <section class="evo-modal-section">
          <h5 class="evo-modal-section-title">
            {{ t('PATIENT_EVOLUTION.MODAL.SECTION_BASIC') }}
          </h5>
          <div class="reg-field-grid-2">
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_EVOLUTION.MODAL.DATE_LABEL') }}
                <span class="reg-required">*</span>
              </label>
              <DatePickerBR v-model="formData.performed_at" />
            </div>
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_EVOLUTION.MODAL.PROFESSIONAL_LABEL') }}
              </label>
              <FormSelect
                v-model="formData.professional_id"
                :options="professionalOptions"
                :placeholder="t('PATIENT_EVOLUTION.MODAL.PROFESSIONAL_PLACEHOLDER')"
                clearable
                auto-searchable
              />
            </div>
          </div>

          <div v-if="pendingItemOptions.length > 0" class="form-group">
            <label class="form-label">
              <i class="i-lucide-link-2 w-3.5 h-3.5 inline-block mr-1 align-text-bottom" />
              {{ t('PATIENT_EVOLUTION.MODAL.PLAN_LINK_LABEL') }}
            </label>
            <FormSelect
              :model-value="formData.treatment_item_id"
              :options="pendingItemOptions"
              :placeholder="t('PATIENT_EVOLUTION.MODAL.PLAN_LINK_PLACEHOLDER')"
              clearable
              auto-searchable
              @update:model-value="onTreatmentItemSelected"
            />
            <p class="evo-form-hint">
              {{ t('PATIENT_EVOLUTION.MODAL.PLAN_LINK_HINT') }}
            </p>
          </div>
        </section>

        <!-- Seção 2: Avaliação clínica -->
        <section class="evo-modal-section">
          <h5 class="evo-modal-section-title">
            {{ t('PATIENT_EVOLUTION.MODAL.SECTION_CLINICAL') }}
          </h5>
          <div class="form-group">
            <label class="form-label">
              {{ t('PATIENT_EVOLUTION.MODAL.COMPLAINT_LABEL') }}
            </label>
            <textarea
              v-model="formData.complaint_of_day"
              class="form-input form-textarea"
              rows="2"
              :placeholder="t('PATIENT_EVOLUTION.MODAL.COMPLAINT_PLACEHOLDER')"
            />
          </div>
          <div class="form-group">
            <label class="form-label">
              {{ t('PATIENT_EVOLUTION.MODAL.ASSESSMENT_LABEL') }}
            </label>
            <textarea
              v-model="formData.assessment"
              class="form-input form-textarea"
              rows="3"
              :placeholder="t('PATIENT_EVOLUTION.MODAL.ASSESSMENT_PLACEHOLDER')"
            />
          </div>
        </section>

        <!-- Seção 3: Procedimento e produto -->
        <section class="evo-modal-section">
          <h5 class="evo-modal-section-title">
            {{ t('PATIENT_EVOLUTION.MODAL.SECTION_PROCEDURE') }}
          </h5>
          <div class="reg-field-grid-2">
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_EVOLUTION.MODAL.PROCEDURE_LABEL') }}
                <span class="reg-required">*</span>
              </label>
              <input
                v-model="formData.procedure_name"
                type="text"
                class="form-input"
                :placeholder="t('PATIENT_EVOLUTION.MODAL.PROCEDURE_PLACEHOLDER')"
              />
            </div>
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_EVOLUTION.MODAL.AREA_LABEL') }}
              </label>
              <input
                v-model="formData.area_treated"
                type="text"
                class="form-input"
                :placeholder="t('PATIENT_EVOLUTION.MODAL.AREA_PLACEHOLDER')"
              />
            </div>
          </div>

          <div class="reg-field-grid-3">
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_EVOLUTION.MODAL.PRODUCT_LABEL') }}
              </label>
              <input
                v-model="formData.product_name"
                type="text"
                class="form-input"
                :placeholder="t('PATIENT_EVOLUTION.MODAL.PRODUCT_PLACEHOLDER')"
              />
            </div>
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_EVOLUTION.MODAL.QUANTITY_LABEL') }}
              </label>
              <input
                v-model="formData.quantity"
                type="text"
                class="form-input"
                :placeholder="t('PATIENT_EVOLUTION.MODAL.QUANTITY_PLACEHOLDER')"
              />
            </div>
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_EVOLUTION.MODAL.UNIT_LABEL') }}
              </label>
              <input
                v-model="formData.unit"
                type="text"
                class="form-input"
              />
            </div>
          </div>

          <div class="reg-field-grid-2">
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_EVOLUTION.MODAL.BATCH_LABEL') }}
              </label>
              <input
                v-model="formData.batch"
                type="text"
                class="form-input"
                :placeholder="t('PATIENT_EVOLUTION.MODAL.BATCH_PLACEHOLDER')"
              />
            </div>
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_EVOLUTION.MODAL.EXPIRES_LABEL') }}
              </label>
              <DatePickerBR v-model="formData.product_expires_at" />
            </div>
          </div>

          <div class="reg-field-grid-2">
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_EVOLUTION.MODAL.COMPLICATIONS_LABEL') }}
              </label>
              <textarea
                v-model="formData.complications"
                class="form-input form-textarea"
                rows="3"
                :placeholder="t('PATIENT_EVOLUTION.MODAL.COMPLICATIONS_PLACEHOLDER')"
              />
            </div>
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_EVOLUTION.MODAL.RESULT_LABEL') }}
              </label>
              <textarea
                v-model="formData.result_observed"
                class="form-input form-textarea"
                rows="3"
                :placeholder="t('PATIENT_EVOLUTION.MODAL.RESULT_PLACEHOLDER')"
              />
            </div>
          </div>
        </section>

        <!-- Seção 4: Acompanhamento -->
        <section class="evo-modal-section">
          <h5 class="evo-modal-section-title">
            {{ t('PATIENT_EVOLUTION.MODAL.SECTION_FOLLOWUP') }}
          </h5>
          <div class="form-group">
            <label class="form-label">
              {{ t('PATIENT_EVOLUTION.MODAL.NEXT_CONSULT_LABEL') }}
            </label>
            <textarea
              v-model="formData.next_consultation_details"
              class="form-input form-textarea"
              rows="2"
              :placeholder="t('PATIENT_EVOLUTION.MODAL.NEXT_CONSULT_PLACEHOLDER')"
            />
          </div>
          <div class="reg-field-grid-2">
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_EVOLUTION.MODAL.RETURN_LABEL') }}
              </label>
              <input
                :value="formData.return_in_days || ''"
                type="number"
                min="1"
                class="form-input"
                :placeholder="t('PATIENT_EVOLUTION.MODAL.RETURN_PLACEHOLDER')"
                @input="handleReturnInDaysInput"
              />
            </div>
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_EVOLUTION.MODAL.OBSERVATION_LABEL') }}
              </label>
              <textarea
                v-model="formData.observation"
                class="form-input form-textarea"
                rows="2"
                :placeholder="t('PATIENT_EVOLUTION.MODAL.OBSERVATION_PLACEHOLDER')"
              />
            </div>
          </div>
        </section>
      </div>

      <div class="evo-modal-footer">
        <BeclinicButton
          variant="ghost"
          color="slate"
          :label="t('PATIENT_EVOLUTION.MODAL.CANCEL')"
          @click="emit('close')"
        />
        <BeclinicButton
          variant="faded"
          color="slate"
          icon="i-lucide-save"
          :label="
            isSaving
              ? t('PATIENT_EVOLUTION.MODAL.SAVING')
              : t('PATIENT_EVOLUTION.MODAL.SAVE_DRAFT')
          "
          :is-loading="isSaving"
          :disabled="isSaving"
          @click="handleSubmit(false)"
        />
        <BeclinicButton
          v-if="canSign && !isEditing"
          variant="solid"
          color="blue"
          icon="i-lucide-pen-tool"
          :label="t('PATIENT_EVOLUTION.MODAL.SAVE_AND_SIGN')"
          :is-loading="isSaving"
          :disabled="isSaving"
          @click="handleSubmit(true)"
        />
      </div>
    </div>
  </div>
</template>
