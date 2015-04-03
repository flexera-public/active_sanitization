# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'active_sanitization/version'

Gem::Specification.new do |spec|
  spec.name          = "active_sanitization"
  spec.version       = ActiveSanitization::VERSION
  spec.authors       = ["Stephen Haley", "Callum Dryden"]
  spec.email         = ["stephen.haley@rightscale.com", "callum.dryden@rightscale.com"]

  spec.summary       = %q{Quick in-place santization for your MySql DB}
  spec.description   = %q{Active Santization provides any easy way to consistently sanitize data from a MySql DB.  With the config you can specify how to sanitize each tables and column.}
  spec.homepage      = "https://github.com/rightscale/active_sanitization"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.8.3"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.2.0"
  spec.add_development_dependency "rails", "~> 4.2.1"
  spec.add_development_dependency "pry", "~> 0.10.1"
  spec.add_development_dependency "sqlite3", "~> 1.3.10"
  spec.add_development_dependency "activerecord", "~> 4.2.1"
  spec.add_development_dependency "mysql2", "~> 0.3.18"
  spec.add_development_dependency "byebug", "~> 4.0.4"

  spec.add_runtime_dependency "aws-sdk", "~> 2.0.33"
end
