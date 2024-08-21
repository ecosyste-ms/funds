source "https://rubygems.org"

ruby file: ".ruby-version"

gem "rails", "~> 7.2.0"
gem "sprockets-rails"
gem "pg", "~> 1.5"
gem "puma", "~> 6.3"
gem "jbuilder"

gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri mingw x64_mingw ]
end

group :development do
  gem "web-console"
end

group :test do
  gem "shoulda-matchers"
  gem "shoulda-context"
  gem "webmock"
  gem "mocha"
  gem "rails-controller-testing"
end
