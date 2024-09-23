module ApplicationHelper
  include Pagy::Frontend
  
  def obfustcate_email(email)
    return unless email.present?
    
    email.split('@').map do |part|
      if part.length > 2
        part.tap { |p| p[1...-1] = "****" }
      else
        part
      end
    end.join('@')
  end
end
