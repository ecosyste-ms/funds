class SyncInviteWorker
  include Sidekiq::Worker
  include Sidekiq::Status::Worker

  sidekiq_options queue: :invites

  def perform(invitation_id)
    Invitation.find_by_id(invitation_id).try(:sync)
  end
end