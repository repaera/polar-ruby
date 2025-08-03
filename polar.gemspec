# frozen_string_literal: true

require_relative "lib/polar/version"

Gem::Specification.new do |spec|
  spec.name = "polar"
  spec.version = Polar::VERSION
  spec.authors = ["Handy Wardhana"]
  spec.email = ["handy@repaera.com"]

  spec.summary = "API wrapper for Polar.sh in Ruby"
  spec.description = "Polar(polar.sh) api wrapper, vibe-coded in Ruby. This will help common rails app to accept payments for various business model, start from $0 to $1,000,000+."
  spec.homepage = "https://github.com/repaera/polar-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/repaera/polar-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/repaera/polar-ruby/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "httparty", "~> 0.21"
  spec.add_dependency "activesupport", ">= 6.0"
  
  spec.add_development_dependency "mocha", "~> 1.0"
  spec.add_development_dependency "webmock", "~> 3.0"
  spec.add_development_dependency "rack", "~> 3.0"
end
