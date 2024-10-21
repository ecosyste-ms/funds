class WebhooksController < ApplicationController
  skip_forgery_protection

  def receive
    
    # TODO handle various events
    p params

    # invite accepted (COLLECTIVE_EXPENSE_UPDATED)
    # invite rejected (COLLECTIVE_EXPENSE_REJECTED)
    # collective updated (COLLECTIVE_EDITED)

    render json: {status: 'ok'}
  end
end