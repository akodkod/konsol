# typed: strict
# frozen_string_literal: true

# Minimal Rails shim for Konsol
# Only includes the methods we actually use

module Rails
  class << self
    sig { returns(T.nilable(Rails::Application)) }
    def application; end
  end

  class Application
    sig { returns(T.untyped) }
    def executor; end

    sig { returns(T.untyped) }
    def reloader; end

    sig { void }
    def load_console; end
  end

  module ConsoleMethods
  end
end
