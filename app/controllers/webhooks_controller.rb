class WebhooksController < ApplicationController
  skip_forgery_protection

  def receive
  
    p params

    case params[:type]
    when 'collective.edited'
      fund = Fund.project_legacy_id(params[:CollectiveId]).first
      if fund.present?
        fund.sync_opencollective_project_async
      end
    when 'collective.expense.updated'
      invitation = Invitation.find_by(member_invitation_id: params[:expense][:id])
      if invitation.present?
        invitation.sync_async
      end
    end

    render json: {status: 'ok'}
  end
end