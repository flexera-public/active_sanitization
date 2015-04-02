$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'active_record'
require 'byebug'
require_relative 'db/connect'
Db::Connect.init
Dir[File.dirname(__FILE__) + '/test_models/**/*.rb'].each { |file| require file }
Db::Connect.seed

require 'active_sanitization'
