Premailer::Rails.config.merge!(
  remove_ids: true, # Removes unnecessary `id` attributes
  preserve_styles: true, # Keeps styles in both the head and inline
  strategies: [:css, :html]
)