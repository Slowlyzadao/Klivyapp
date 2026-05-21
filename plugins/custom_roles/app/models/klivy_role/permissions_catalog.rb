# Snapshot do catálogo de módulos/perms do Klivy em Ruby — espelho de
# `plugins/custom_roles/frontend/shared/modules.js`. Usado para SANITIZAR o
# JSONB `klivy_roles.permissions` antes de persistir (auditoria C-2):
#
#   - Drop silencioso de módulos/keys que NÃO estão no catálogo (defesa contra
#     payload arbitrário).
#   - Migração de keys legadas (`settings.manage_users` → `users_view`,
#     `_invite`, `_edit`, `_remove`) — mesma lógica do `LEGACY_KEY_MIGRATIONS`
#     do `modules.js`, preserva semantics de roles antigas em prod.
#   - Validação de `scope` ∈ {all, own}.
#
# IMPORTANTE: este catálogo precisa ser mantido em sync com `modules.js`. Se
# adicionar/remover perm no front, espelhar AQUI. Idealmente futura iteração
# move pra um único arquivo .json fonte que ambos consomem.
class KlivyRole < ApplicationRecord
  module PermissionsCatalog
    # Hash plano módulo → set de perms válidas (após achatar grupos do
    # `modules.js`). Não incluímos labels/descrições — só as keys.
    CATALOG = {
      'inbox' => %w[view mark_read].freeze,

      'chat' => %w[
        view_all view_unassigned view_mentions reply assign_conversation
        delete_message send_broadcast
        view_conversation_actions use_macros view_conversation_info
        view_contact_attributes view_contact_notes view_previous_conversations
        view_participants
        view_patient_record create_appointment edit_contact merge_contact
        manage_waiting_list view_contact_profile delete_contact
      ].freeze,

      'captain' => %w[
        view manage_faqs manage_documents manage_scenarios use_playground
        manage_inboxes manage_tools manage_settings
      ].freeze,

      'agenda' => %w[
        is_provider
        view create_event edit_event cancel_event drag_and_drop manage_blocks
        view_settings manage_schedules manage_online_booking manage_services
        view_notifications manage_notifications
        manage_custom_attributes
      ].freeze,

      'patients' => %w[
        view create edit delete
        view_anamnesis manage_anamnesis
        view_clinical_notes create_clinical_notes sign_clinical_notes delete_clinical_notes
        view_treatment_plans manage_treatment_plans
        view_consents manage_consents
        view_documents manage_documents
        view_exams manage_exams
        view_audit view_timeline
        view_financial manage_financial
      ].freeze,

      'financial' => %w[
        view_dashboard view_cashflow view_receivables view_payables view_dre
        view_reports view_cash_register
        create_transaction edit_transaction delete_transaction
        manage_estimates approve_estimate export_data manage_settings
      ].freeze,

      'contacts' => %w[
        view_all view_active create edit delete
        manage_segments manage_tags import_export
      ].freeze,

      'reports' => %w[
        view_overview view_conversation view_agent view_label view_inbox
        view_team view_csat view_sla view_bot view_agenda
      ].freeze,

      'campaigns' => %w[
        view manage_live_chat manage_sms manage_whatsapp
      ].freeze,

      'help_center' => %w[
        view manage_articles manage_categories manage_portals
      ].freeze,

      'settings' => %w[
        account_view account_manage
        users_view users_invite users_edit users_remove
        teams_view teams_create teams_edit teams_delete
        inboxes_view inboxes_create inboxes_edit inboxes_delete inboxes_manage_agents
        labels_view labels_create labels_edit labels_delete
        custom_attributes_view custom_attributes_create custom_attributes_edit custom_attributes_delete
        automation_view automation_create automation_edit automation_delete
        agent_bots_view agent_bots_manage
        macros_view macros_create macros_edit macros_delete
        canned_view canned_create canned_edit canned_delete
        integrations_view integrations_manage
        audit_view
        roles_view roles_create roles_edit roles_delete
        sla_view sla_create sla_edit sla_delete
        workflow_view workflow_manage
        security_view security_manage
        billing_view billing_manage
      ].freeze,

      'help' => %w[view].freeze
    }.freeze

    MODULE_KEYS = CATALOG.keys.freeze

    # Para lookup rápido — `Set` em vez de Array.
    PERMISSIONS_BY_MODULE = CATALOG.transform_values { |perms| perms.to_set }.freeze

    VALID_SCOPES = %w[all own].freeze

    # Espelha `LEGACY_KEY_MIGRATIONS` do `modules.js`. Quando uma key antiga
    # estava `true`, todas as keys novas correspondentes recebem `true`. Roda
    # ANTES da filtragem pelo catálogo atual.
    LEGACY_KEY_MIGRATIONS = {
      'settings' => {
        'manage_users' => %w[users_view users_invite users_edit users_remove],
        'manage_roles' => %w[roles_view roles_create roles_edit roles_delete],
        'manage_inboxes' => %w[
          inboxes_view inboxes_create inboxes_edit inboxes_delete inboxes_manage_agents
        ],
        'manage_integrations' => %w[
          integrations_view integrations_manage agent_bots_view agent_bots_manage
        ],
        'manage_automation' => %w[
          automation_view automation_create automation_edit automation_delete
          workflow_view workflow_manage
        ],
        'manage_canned' => %w[canned_view canned_create canned_edit canned_delete],
        'manage_labels' => %w[labels_view labels_create labels_edit labels_delete],
        'manage_macros' => %w[macros_view macros_create macros_edit macros_delete],
        'manage_billing' => %w[
          billing_view billing_manage account_view account_manage
          security_view security_manage
        ],
        'view_audit' => %w[audit_view]
      }
    }.freeze

    def self.valid_module?(module_key)
      MODULE_KEYS.include?(module_key.to_s)
    end

    def self.valid_permission?(module_key, permission_key)
      PERMISSIONS_BY_MODULE[module_key.to_s]&.include?(permission_key.to_s) || false
    end

    # Sanitiza e migra um hash de permissions arbitrário. Sempre retorna
    # um hash válido (pode ser `{}`). Não levanta exception — keys
    # desconhecidas são silenciosamente removidas; keys legadas são
    # convertidas para as novas. Idempotente.
    #
    # Aceita keys symbol ou string (normaliza para string no output).
    # Aceita Hash, ActionController::Parameters ou qualquer objeto que
    # responda a `to_unsafe_h` (caller no controller passa
    # `role_params[:permissions]` que é Parameters, NÃO Hash — sem este
    # cast a sanitização retornaria sempre `{}` e o `enforce_delegation_limit!`
    # nunca bloquearia nada — bug encontrado durante validação C-2).
    def self.sanitize_and_migrate(input)
      input = input.to_unsafe_h if input.respond_to?(:to_unsafe_h)
      input = input.to_h if !input.is_a?(Hash) && input.respond_to?(:to_h)
      return {} unless input.is_a?(Hash)

      sanitized = {}

      input.each do |raw_mod_key, raw_mod_perms|
        mod_key = raw_mod_key.to_s
        next unless valid_module?(mod_key)
        next unless raw_mod_perms.is_a?(Hash)

        # Step 1: build map de "perm_key (string) => bool" aplicando legacy
        # migrations: se chave legada estava true, marca todas as novas como true.
        expanded = {}
        legacy_migrations = LEGACY_KEY_MIGRATIONS[mod_key] || {}

        raw_mod_perms.each do |raw_perm_key, raw_perm_value|
          perm_key = raw_perm_key.to_s

          if perm_key == 'scope'
            scope_value = raw_perm_value.to_s
            expanded['scope'] = scope_value if VALID_SCOPES.include?(scope_value)
            next
          end

          # Migração legacy: keys antigas se expandem para várias novas.
          if legacy_migrations.key?(perm_key)
            next unless raw_perm_value == true

            legacy_migrations[perm_key].each do |new_key|
              expanded[new_key] = true if valid_permission?(mod_key, new_key)
            end
            next
          end

          # Key atual conhecida: aceita boolean true; demais valores viram false.
          if valid_permission?(mod_key, perm_key)
            expanded[perm_key] = raw_perm_value == true
          end
          # Else: key desconhecida — drop silencioso.
        end

        sanitized[mod_key] = expanded unless expanded.empty?
      end

      sanitized
    end
  end
end
