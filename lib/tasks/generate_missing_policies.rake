namespace :beclinic do
  task generate_missing_policies: :environment do
    models = [
      "TreatmentPlan", "TreatmentItem", "SessionLog", 
      "FinancialEstimate", "Transaction", "Installment",
      "ExamMedia", "Document", "ConsentRecord",
      "PatientAppointment", "PatientTimelineEvent"
    ]

    models.each do |model_name|
      policy_path = Rails.root.join("app/policies/#{model_name.underscore}_policy.rb")
      unless File.exist?(policy_path)
        content = <<-RUBY
class #{model_name}Policy < ApplicationPolicy
  def index?
    account_user.present?
  end

  def show?
    account_user.present?
  end

  def create?
    administrator_or_supervisor? || professional? || receptionist?
  end

  def update?
    administrator_or_supervisor? || professional?
  end

  def destroy?
    administrator_or_supervisor?
  end

  # Generic actions just in case
  def approve?
    update?
  end
  
  def cancel?
    update?
  end

  def pay?
    update? || receptionist?
  end

  def refund?
    administrator_or_supervisor?
  end

  private

  def administrator_or_supervisor?
    user.administrator? || user.custom_role&.name.to_s.in?(%w[supervisor])
  end

  def professional?
    user.custom_role&.name.to_s.in?(%w[professional profissional agent]) || user.role == 'agent'
  end

  def receptionist?
    user.custom_role&.name.to_s.in?(%w[receptionist recepcionista])
  end
end
        RUBY
        File.write(policy_path, content)
        puts "Criado \#{policy_path}"
      end
    end
  end
end
