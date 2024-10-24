class SyncInviteWorker
  include Sidekiq::Worker
  include Sidekiq::Status::Worker

  def perform(invitation_id)
    Invitation.find_by_id(invitation_id).try(:sync)
  end
end