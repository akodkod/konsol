# typed: strict
# frozen_string_literal: true

module Konsol
  module Session
    class Manager
      extend T::Sig

      sig { void }
      def initialize
        @sessions = T.let({}, T::Hash[String, Session])
        @rails_booted = T.let(false, T::Boolean)
      end

      sig { returns(Session) }
      def create_session
        boot_rails! unless @rails_booted
        session = Session.new
        @sessions[session.id] = session
        session
      end

      sig { params(id: String).returns(T.nilable(Session)) }
      def get_session(id)
        @sessions[id]
      end

      sig { params(id: String).returns(Session) }
      def get_session!(id)
        session = @sessions[id]
        raise SessionNotFoundError, "Session not found: #{id}" if session.nil?

        session
      end

      sig { void }
      def invalidate_all
        @sessions.clear
      end

      sig { returns(Integer) }
      def session_count
        @sessions.size
      end

      sig { returns(T::Boolean) }
      def rails_booted?
        @rails_booted
      end

      private

      sig { void }
      def boot_rails!
        return if @rails_booted

        require_rails_environment
        load_console_helpers
        @rails_booted = true
      rescue StandardError => e
        raise RailsBootError, "Failed to boot Rails: #{e.message}"
      end

      sig { void }
      def require_rails_environment
        # Require config/environment.rb from current working directory
        environment_path = File.join(Dir.pwd, "config", "environment.rb")

        raise RailsBootError, "config/environment.rb not found in #{Dir.pwd}" unless File.exist?(environment_path)

        require environment_path
      end

      sig { void }
      def load_console_helpers
        return unless defined?(Rails) && Rails.application.respond_to?(:load_console)

        Rails.application.load_console
      end
    end

    class SessionNotFoundError < Konsol::Error; end
    class RailsBootError < Konsol::Error; end
  end
end
