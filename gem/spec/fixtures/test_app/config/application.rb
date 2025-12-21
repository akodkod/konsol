# frozen_string_literal: true

require "rails"
require "active_model/railtie"
require "active_record/railtie"

module TestApp
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.logger = Logger.new(nil)
    # legacy_connection_handling was removed in Rails 7.1
    if Rails::VERSION::MAJOR < 7 || (Rails::VERSION::MAJOR == 7 && Rails::VERSION::MINOR < 1)
      config.active_record.legacy_connection_handling = false
    end

    # Disable unnecessary middleware for testing
    config.api_only = true
  end
end
