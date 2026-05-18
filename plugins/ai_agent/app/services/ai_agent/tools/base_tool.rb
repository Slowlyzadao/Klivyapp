module AiAgent
  module Tools
    # Common parent for all Bea tools. Tools are RubyLLM::Tool subclasses
    # so the agent can pick them via function calling. The base swallows
    # the per-conversation context (account, contact, state) every tool
    # needs but isn't part of the LLM-visible signature.
    class BaseTool < ::RubyLLM::Tool
      attr_reader :context

      # context is an AiAgent::Tools::Context struct; see chat_service.rb.
      def initialize(context)
        @context = context
        super()
      end

      # Use the short class name (snake_case) as the LLM-facing tool name.
      # RubyLLM's default would produce names like
      # "ai_agent--tools--clinic_info" with double dashes, which Gemini's
      # function-calling chokes on (LLM emits a different name and the
      # lookup `tools[name.to_sym]` returns nil → NoMethodError on call).
      # We force a clean name like `clinic_info`, `book_appointment`, etc.
      def name
        klass = self.class.name.to_s.split('::').last.to_s
        klass.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
             .gsub(/([a-z\d])([A-Z])/, '\1_\2')
             .downcase
             .delete_suffix('_tool')
      end

      private

      def account
        context.account
      end

      def conversation_state
        context.conversation_state
      end

      def patient_memory
        context.patient_memory
      end

      def contact_id
        context.contact_id
      end

      # Resolve the Patient row linked to the active Chatwoot contact.
      # Returns nil when no contact is bound or no Patient model exists yet.
      def current_patient
        return nil if contact_id.blank?
        return nil unless defined?(::Patient)

        ::Patient.active.find_by(account_id: account.id, contact_id: contact_id)
      end
    end
  end
end
