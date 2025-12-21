# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require_relative "konsol/version"

module Konsol
  extend T::Sig

  class Error < StandardError; end
end

require_relative "konsol/util/case_transform"
require_relative "konsol/framing/reader"
require_relative "konsol/framing/writer"
require_relative "konsol/protocol/error_codes"
require_relative "konsol/protocol/methods"
require_relative "konsol/protocol/message"

# Request types
require_relative "konsol/protocol/requests/initialize"
require_relative "konsol/protocol/requests/shutdown"
require_relative "konsol/protocol/requests/cancel"
require_relative "konsol/protocol/requests/session_create"
require_relative "konsol/protocol/requests/eval"
require_relative "konsol/protocol/requests/interrupt"

# Response types
require_relative "konsol/protocol/responses/initialize"
require_relative "konsol/protocol/responses/session_create"
require_relative "konsol/protocol/responses/eval"
require_relative "konsol/protocol/responses/interrupt"

# Notification types
require_relative "konsol/protocol/notifications/exit"
require_relative "konsol/protocol/notifications/stdout"
require_relative "konsol/protocol/notifications/stderr"
require_relative "konsol/protocol/notifications/status"

# Session management
require_relative "konsol/session/session"
require_relative "konsol/session/manager"
require_relative "konsol/session/evaluator"

# Handlers
require_relative "konsol/handlers/lifecycle"
require_relative "konsol/handlers/konsol"

# Server
require_relative "konsol/server"
