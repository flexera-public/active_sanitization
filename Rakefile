require "bundler/gem_tasks"
require 'rspec/core/rake_task'

require 'active_sanitization'

RSpec::Core::RakeTask.new('spec')
Dir[File.dirname(__FILE__) + '/lib/tasks/**/*.rake'].each { |file| import file }

task :default => :spec

desc "console"
task :console do
  require 'pry'
  binding.pry
end
