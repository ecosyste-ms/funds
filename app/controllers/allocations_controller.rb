require 'csv'

class AllocationsController < ApplicationController
  def show
    @fund = Fund.find_by(slug: params[:fund_id])
    @allocation = @fund.allocations.find(params[:id])
    @project_allocations = @allocation.project_allocations.includes(:project, :funding_source).order('amount_cents desc').where('amount_cents >= 1')
  end

  def export
    @fund = Fund.find_by(slug: params[:fund_id])
    @allocation = @fund.allocations.find(params[:id])
    @platform = params[:platform]
    @host = params[:host]

    @project_allocations = @allocation.project_allocations.platform(@platform).includes(:project, :funding_source).order('amount_cents desc').where('amount_cents >= 1')
    @project_allocations = @project_allocations.select{|pa| pa.funding_source.host == @host } if @platform == 'opencollective.com' && @host.present?

    raise ActiveRecord::RecordNotFound if @project_allocations.empty?

    filename = "#{@fund}-#{@allocation}-#{@platform}"
    filename += "-#{@host}" if @host.present?

    csv_data = CSV.generate(headers: true) do |csv|
      csv << ['Account', 'URL', 'Amount (cents)']

      @project_allocations.group_by(&:funding_source).each do |funding_source, project_allocations|
        csv << [funding_source.name, funding_source.url, project_allocations.sum(&:amount_cents)]
      end
    end

    send_data csv_data, filename: "#{filename}.csv", type: 'text/csv'

  end

  def export_github_sponsors
    @fund = Fund.find_by(slug: params[:fund_id])
    @allocation = @fund.allocations.find(params[:id])

    csv_data = @allocation.github_sponsors_csv_export

    filename = "#{@fund}-#{@allocation}-github-sponsors"

    send_data csv_data, filename: "#{filename}.csv", type: 'text/csv'
  end
end
