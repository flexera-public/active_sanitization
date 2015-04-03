require 'active_record'

module Db
  class Connect
    def self.init
      ActiveRecord::Base.establish_connection(
        :adapter => "mysql2",
        :username => "root",
        :password => nil,
        :host => "localhost"
      )
      ActiveRecord::Base.connection.execute("CREATE DATABASE IF NOT EXISTS active_sanitization")
      ActiveRecord::Base.establish_connection(
        :adapter => "mysql2",
        :database => "active_sanitization",
        :username => "root",
        :password => nil,
        :host => "localhost"
      )

      require_relative 'schema'
    end

    def self.seed
      require_relative 'seed'
    end
  end
end
