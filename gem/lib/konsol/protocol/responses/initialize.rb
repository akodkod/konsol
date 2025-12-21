# typed: strict
# frozen_string_literal: true

module Konsol
  module Protocol
    module Responses
      class ServerInfo < T::Struct
        const :name, String
        const :version, String
      end

      class Capabilities < T::Struct
        const :supports_interrupt, T::Boolean, default: false
      end

      class InitializeResult < T::Struct
        extend T::Sig

        const :server_info, ServerInfo
        const :capabilities, Capabilities

        sig { returns(T::Hash[String, T.untyped]) }
        def to_h
          {
            "serverInfo" => {
              "name" => server_info.name,
              "version" => server_info.version,
            },
            "capabilities" => {
              "supportsInterrupt" => capabilities.supports_interrupt,
            },
          }
        end

        sig { returns(InitializeResult) }
        def self.default
          new(
            server_info: ServerInfo.new(name: "konsol", version: Konsol::VERSION),
            capabilities: Capabilities.new,
          )
        end
      end
    end
  end
end
