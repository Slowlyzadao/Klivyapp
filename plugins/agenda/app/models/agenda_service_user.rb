# == Schema Information
#
# Table name: agenda_service_users
#
#  id                :bigint           not null, primary key
#  agenda_service_id :bigint           not null
#  user_id           :bigint           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_agenda_service_users_unique  (agenda_service_id, user_id) UNIQUE
#

# 9.7 da auditoria 2026-05-14: tabela de junção que diz quais profissionais
# oferecem cada serviço. Sem nenhuma linha para um service = compat pré-9.7
# (todos profissionais da conta podem oferecer); com 1+ linhas = só os
# profissionais listados aparecem no link público do respectivo profissional.
class AgendaServiceUser < ApplicationRecord
  belongs_to :agenda_service
  belongs_to :user
end
