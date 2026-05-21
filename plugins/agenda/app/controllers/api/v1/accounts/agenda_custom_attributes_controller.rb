class Api::V1::Accounts::AgendaCustomAttributesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :find_attribute, only: [:show, :update, :destroy]

  def index
    @attributes = Current.account.agenda_custom_attributes.ordered
    render json: @attributes.map { |a| attribute_payload(a) }
  end

  def show
    render json: attribute_payload(@attribute)
  end

  def create
    @attribute = Current.account.agenda_custom_attributes.create!(attribute_params)
    render json: attribute_payload(@attribute), status: :created
  end

  def update
    @attribute.update!(attribute_params)
    render json: attribute_payload(@attribute)
  end

  def destroy
    @attribute.destroy!
    head :ok
  end

  def reorder
    ids = params[:ids]
    return head :unprocessable_entity unless ids.is_a?(Array)

    ActiveRecord::Base.transaction do
      ids.each_with_index do |id, index|
        Current.account.agenda_custom_attributes.where(id: id).update_all(position: index)
      end
    end
    head :ok
  end

  private

  def find_attribute
    @attribute = Current.account.agenda_custom_attributes.find(params[:id])
  end

  def attribute_params
    params.require(:agenda_custom_attribute).permit(:name, :field_type, :required, :validate_cpf, :options, :position)
  end

  def attribute_payload(attr)
    {
      id: attr.id,
      name: attr.name,
      type: attr.field_type,
      required: attr.required,
      validate_cpf: attr.validate_cpf,
      options: attr.options || '',
      position: attr.position
    }
  end
end
