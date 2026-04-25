# frozen_string_literal: true

# Serves PDF downloads for all financial reports.
# Each action generates a Prawn PDF in-memory and streams it as a download.
class Api::V1::Accounts::FinancialPdfsController < Api::V1::Accounts::BaseController
  # GET /api/v1/accounts/:account_id/financial/pdfs/cash_flow
  # Params: start_date, end_date
  def cash_flow
    authorize :financial_dashboard, :show?

    start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : Time.zone.today.beginning_of_month
    end_date   = params[:end_date].present?   ? Date.parse(params[:end_date])   : Time.zone.today.end_of_month

    pdf_data = Financial::Pdf::CashFlowPdf.new(
      account: Current.account,
      start_date: start_date,
      end_date: end_date
    ).call

    send_pdf(pdf_data, "fluxo_caixa_#{start_date}_#{end_date}")
  end

  # GET /api/v1/accounts/:account_id/financial/pdfs/receivables
  # Params: pages, start_date, end_date
  def receivables
    authorize :financial_dashboard, :show?

    pdf_data = Financial::Pdf::ReceivablesPdf.new(
      account: Current.account,
      pages: params[:pages],
      start_date: params[:start_date],
      end_date: params[:end_date]
    ).call

    send_pdf(pdf_data, "a_receber_#{Date.today}")
  end

  # GET /api/v1/accounts/:account_id/financial/pdfs/payables
  # Params: pages, start_date, end_date
  def payables
    authorize :financial_dashboard, :show?

    pdf_data = Financial::Pdf::PayablesPdf.new(
      account: Current.account,
      pages: params[:pages],
      start_date: params[:start_date],
      end_date: params[:end_date]
    ).call

    send_pdf(pdf_data, "a_pagar_#{Date.today}")
  end

  # GET /api/v1/accounts/:account_id/financial/pdfs/dre
  # Params: period (YYYY-MM), regime (competencia|caixa)
  def dre
    authorize :financial_dashboard, :show?

    pdf_data = Financial::Pdf::DrePdf.new(
      account: Current.account,
      period: params[:period],
      regime: params[:regime] || 'competencia'
    ).call

    send_pdf(pdf_data, "dre_#{params[:period] || Date.today.strftime('%Y-%m')}")
  end

  # GET /api/v1/accounts/:account_id/financial/pdfs/commissions
  # Params: professional_id, period (month|quarter|year|custom), date, start_date, end_date
  def commissions
    authorize :financial_dashboard, :show?

    professional = Current.account.users.find(params.require(:professional_id))
    period       = resolve_period

    pdf_data = Financial::Pdf::CommissionsPdf.new(
      account: Current.account,
      professional: professional,
      period: period
    ).call

    send_pdf(pdf_data, "comissoes_#{professional.name.parameterize}_#{period.first}")
  end

  # GET /api/v1/accounts/:account_id/financial/pdfs/expenses_by_category
  # Params: period (YYYY-MM)
  def expenses_by_category
    authorize :financial_dashboard, :show?

    pdf_data = Financial::Pdf::ExpensesByCategoryPdf.new(
      account: Current.account,
      period: params[:period]
    ).call

    send_pdf(pdf_data, "despesas_categoria_#{params[:period] || Date.today.strftime('%Y-%m')}")
  end

  # GET /api/v1/accounts/:account_id/financial/pdfs/insurance
  # Params: period params
  def insurance
    authorize :financial_dashboard, :show?
    period = resolve_period

    pdf_data = Financial::Pdf::InsurancePdf.new(
      account: Current.account,
      period: period
    ).call

    send_pdf(pdf_data, "faturamento_convenio_#{period.first}")
  end

  # GET /api/v1/accounts/:account_id/financial/pdfs/average_ticket
  # Params: group_by (professional|month), period params
  def average_ticket
    authorize :financial_dashboard, :show?
    period = resolve_period

    pdf_data = Financial::Pdf::AverageTicketPdf.new(
      account: Current.account,
      period: period,
      group_by: params.fetch(:group_by, 'professional')
    ).call

    send_pdf(pdf_data, "ticket_medio_#{period.first}")
  end

  private

  def resolve_period
    case params[:period]
    when 'quarter'
      anchor = params[:date].present? ? Date.parse("#{params[:date]}-01") : Time.zone.today
      anchor.all_quarter
    when 'year'
      anchor = params[:date].present? ? Date.parse("#{params[:date]}-01-01") : Time.zone.today
      anchor.all_year
    when 'custom'
      Date.parse(params[:start_date])..Date.parse(params[:end_date])
    else
      anchor = params[:date].present? ? Date.parse("#{params[:date]}-01") : Time.zone.today
      anchor.all_month
    end
  end

  def send_pdf(data, name)
    send_data data,
              filename: "#{name}.pdf",
              type: 'application/pdf',
              disposition: 'attachment'
  end
end
