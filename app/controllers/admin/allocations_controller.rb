class Admin::AllocationsController < Admin::ApplicationController
  skip_before_action :require_basic_auth, only: [:github_sponsors, :github_sponsors_history]
  
  def github_sponsors
    if params[:date].blank?
      redirect_to github_sponsors_dated_admin_allocations_path(date: Date.today.iso8601, format: :csv)
      return
    end

    date = begin
      Date.iso8601(params[:date])
    rescue Date::Error
      raise ActiveRecord::RecordNotFound
    end

    csv_string = Allocation.github_sponsors_csv_export(Allocation.not_completed_as_of(date.end_of_day))
    send_data csv_string, filename: "github_sponsors-#{date.iso8601}.csv", type: "text/csv"
  end

  def github_sponsors_history
    csv_string = Allocation.github_sponsors_csv_export_history
    send_data csv_string, filename: "github_sponsors_history.csv", type: "text/csv"
  end
end