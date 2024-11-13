class SyncInviteWorker
  include Sidekiq::Worker
  include Sidekiq::Status::Worker

  sidekiq_options queue: :invites, unique: :until_executed

  def perform(invitation_id)
    Invitation.find_by_id(invitation_id).try(:sync)
  end
end