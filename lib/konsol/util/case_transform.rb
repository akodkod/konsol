# typed: strict
# frozen_string_literal: true

module Konsol
  module Util
    module CaseTransform
      extend T::Sig

      # Converts a hash with snake_case keys to camelCase keys
      sig { params(value: T.untyped).returns(T.untyped) }
      def self.to_camel_case(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, val), result|
            camel_key = snake_to_camel(key.to_s)
            result[camel_key] = to_camel_case(val)
          end
        when Array
          value.map { |item| to_camel_case(item) }
        else
          value
        end
      end

      # Converts a hash with camelCase keys to snake_case keys
      sig { params(value: T.untyped).returns(T.untyped) }
      def self.to_snake_case(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, val), result|
            snake_key = camel_to_snake(key.to_s)
            result[snake_key] = to_snake_case(val)
          end
        when Array
          value.map { |item| to_snake_case(item) }
        else
          value
        end
      end

      # Converts snake_case string to camelCase
      sig { params(str: String).returns(String) }
      def self.snake_to_camel(str)
        str.gsub(/_([a-z])/) { ::Regexp.last_match(1)&.upcase }
      end

      # Converts camelCase string to snake_case
      sig { params(str: String).returns(String) }
      def self.camel_to_snake(str)
        str.gsub(/([A-Z])/) { "_#{::Regexp.last_match(1)&.downcase}" }.sub(/^_/, "")
      end
    end
  end
end
