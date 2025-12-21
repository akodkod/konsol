# typed: strict
# frozen_string_literal: true

module Konsol
  module Protocol
    module Requests
      class ClientInfo < T::Struct
        const :name, String
        const :version, T.nilable(String), default: nil
      end

      class InitializeParams < T::Struct
        extend T::Sig

        const :process_id, T.nilable(Integer), default: nil
        const :client_info, T.nilable(ClientInfo), default: nil

        sig { params(params: T.nilable(T::Hash[String, T.untyped])).returns(InitializeParams) }
        def self.from_hash(params)
          return new if params.nil?

          client_info = if params["clientInfo"]
                          ClientInfo.new(
                            name: params["clientInfo"]["name"],
                            version: params["clientInfo"]["version"],
                          )
                        end

          new(
            process_id: params["processId"],
            client_info: client_info,
          )
        end
      end
    end
  end
end
