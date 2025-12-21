# frozen_string_literal: true

require_relative "lib/konsol/version"

Gem::Specification.new do |spec|
  spec.name = "konsol"
  spec.version = Konsol::VERSION
  spec.authors = ["Andrew Kodkod"]
  spec.email = ["678665+akodkod@users.noreply.github.com"]

  spec.summary = "JSON-RPC server for Rails console over stdio"
  spec.description = "A JSON-RPC 2.0 server providing a GUI-friendly Rails console backend " \
                     "with LSP-style framing over STDIN/STDOUT."
  spec.homepage = "https://github.com/akodkod/konsol"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/akodkod/konsol"
  spec.metadata["changelog_uri"] = "https://github.com/akodkod/konsol/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(["git", "ls-files", "-z"], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?("bin/", "Gemfile", ".gitignore", ".rspec", "spec/", ".github/", ".rubocop.yml")
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "sorbet-runtime", "~> 0.5"
end
