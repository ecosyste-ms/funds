class WebhooksController < ApplicationController
  skip_forgery_protection

  def receive
  
    p params

    case params[:type]
    when 'collective.edited'
      fund = Fund.project_legacy_id(params[:CollectiveId]).first
      if fund.present?
        SyncFundProjectWorker.perform_async(fund.id)
      end
    else

    end
      
    

    # invite accepted (COLLECTIVE_EXPENSE_UPDATED)
    # invite rejected (COLLECTIVE_EXPENSE_REJECTED)


    render json: {status: 'ok'}
  end
end