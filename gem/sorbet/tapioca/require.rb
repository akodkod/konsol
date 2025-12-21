# typed: true
# frozen_string_literal: true

require "active_model/railtie"
require "active_record/railtie"
require "bundler/setup"
require "json"
require "open3"
require "rails"
require "securerandom"
require "sorbet-runtime"
require "stringio"
require "timeout"
