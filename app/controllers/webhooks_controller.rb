class WebhooksController < ApplicationController
  skip_forgery_protection

  def receive
  
    p params

    case params[:type]
    when 'collective.edited' # project updated
      fund = Fund.project_legacy_id(params[:CollectiveId]).first
      if fund.present?
        fund.sync_opencollective_project_async
      end
    when 'collective.expense.updated' # expense invite updated
      invitation = Invitation.find_by(member_invitation_id: params[:expense][:id])
      if invitation.present?
        invitation.sync_async
      end
    when 'collective.member.created' # donation recieved
      fund = Fund.project_legacy_id(params[:CollectiveId]).first
      if fund.present?
        fund.sync_opencollective_project_async
      end
    end

    render json: {status: 'ok'}
  end
end