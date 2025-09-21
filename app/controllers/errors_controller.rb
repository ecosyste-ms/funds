class ErrorsController < ApplicationController
  def not_found
    respond_to do |format|
      format.html { render status: :not_found }
      format.json { render json: { error: "not found" }, status: :not_found }
      format.any { head :not_found }
    end
  end

  def unprocessable
    respond_to do |format|
      format.html { render status: :unprocessable_content }
      format.json { render json: { error: "unprocessable" }, status: :unprocessable_content }
      format.any { head :unprocessable_content }
    end
  end

  def internal
    respond_to do |format|
      format.html { render status: :internal_server_error }
      format.json { render json: { error: "internal server error" }, status: :internal_server_error }
      format.any { head :internal_server_error }
    end
  end

  def forbidden
    respond_to do |format|
      format.html { render status: :forbidden }
      format.json { render json: { error: "forbidden" }, status: :forbidden }
      format.any { head :forbidden }
    end
  end

  def unauthorized
    respond_to do |format|
      format.html { render status: :unauthorized }
      format.json { render json: { error: "unauthorized" }, status: :unauthorized }
      format.any { head :unauthorized }
    end
  end

  def bad_request
    respond_to do |format|
      format.html { render status: :bad_request }
      format.json { render json: { error: "bad request" }, status: :bad_request }
      format.any { head :bad_request }
    end
  end

  def conflict
    respond_to do |format|
      format.html { render status: :conflict }
      format.json { render json: { error: "conflict" }, status: :conflict }
      format.any { head :conflict }
    end
  end

  def service_unavailable
    respond_to do |format|
      format.html { render status: :service_unavailable }
      format.json { render json: { error: "service unavailable" }, status: :service_unavailable }
      format.any { head :service_unavailable }
    end
  end

  def too_many_requests
    respond_to do |format|
      format.html { render status: :too_many_requests }
      format.json { render json: { error: "too many requests" }, status: :too_many_requests }
      format.any { head :too_many_requests }
    end
  end
end
