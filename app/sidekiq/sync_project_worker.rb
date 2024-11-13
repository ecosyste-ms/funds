class SyncProjectWorker
  include Sidekiq::Worker
  include Sidekiq::Status::Worker

  sidekiq_options queue: :projects, unique: :until_executed

  def perform(project_id)
    Project.find_by_id(project_id).try(:sync)
  end
end