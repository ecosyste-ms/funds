class Admin::AllocationsController < Admin::ApplicationController
  skip_before_action :require_basic_auth, only: [:github_sponsors]
  
  def github_sponsors
    csv_string = Allocation.github_sponsors_csv_export(Allocation.not_completed.all) 
    send_data csv_string, filename: "github_sponsors.csv", type: "text/csv"
  end
end