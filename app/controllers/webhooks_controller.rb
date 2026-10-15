class WebhooksController < ApplicationController
  skip_forgery_protection

  EXPENSE_STATUS_EVENTS = %w[
    collective.expense.updated
    collective.expense.approved
    collective.expense.unapproved
    collective.expense.rejected
    collective.expense.paid
    collective.expense.unpaid
    collective.expense.processing
    collective.expense.scheduledForPayment
    collective.expense.reApprovalRequested
    collective.expense.error
    collective.expense.invite.declined
  ].freeze

  def receive
    case params[:type]
    when 'collective.edited' # project updated
      fund = Fund.project_legacy_id(params[:CollectiveId]).first
      if fund.present?
        fund.sync_opencollective_project_async
      end
    when *EXPENSE_STATUS_EVENTS
      expense_id = params.dig(:data, :expense, :id)
      Invitation.find_by(member_invitation_id: expense_id)&.sync_async if expense_id.present?
    when 'collective.member.created' # donation recieved
      fund = Fund.project_legacy_id(params[:CollectiveId]).first
      if fund.present?
        fund.sync_opencollective_project_async
      end
    end

    render json: {status: 'ok'}
  end
end
