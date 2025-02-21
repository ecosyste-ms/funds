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
    @meta_description || app_description
  end

  def app_name
    "Funds"
  end

  def app_description
    'An open source funding solution from ecosyste.ms & Open Source Collective.'
  end

  def obfuscate_email(email)
    return unless email.present?
    local_part, domain = email.split('@')
    obfuscated_local = local_part[0] + '*' * (local_part.length - 2) + local_part[-1]
    "#{obfuscated_local}@#{domain}"
  end
end
