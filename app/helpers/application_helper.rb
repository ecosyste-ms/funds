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

  def meta_title
    [@meta_title, 'Ecosyste.ms: Funds'].compact.join(' | ')
  end

  def meta_description
    @meta_description || 'An open source funding solution from ecosyste.ms & Open Source Collective.'
  end
end
