module Financial
  module Concerns
    # Auto-popula created_by_id / updated_by_id a partir de Current.user.
    # Funciona junto com Current::Attributes definido pelo Rails.
    module Stamped
      extend ActiveSupport::Concern

      included do
        before_create  :stamp_creator
        before_update  :stamp_updater
      end

      private

      def stamp_creator
        return unless self.class.column_names.include?('created_by_id')
        return if created_by_id.present?

        user_id = Financial::CurrentUser.id
        self.created_by_id = user_id if user_id
        self.updated_by_id = user_id if user_id && self.class.column_names.include?('updated_by_id')
      end

      def stamp_updater
        return unless self.class.column_names.include?('updated_by_id')

        user_id = Financial::CurrentUser.id
        self.updated_by_id = user_id if user_id
      end
    end
  end
end
