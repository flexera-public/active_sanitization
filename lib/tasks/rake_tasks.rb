require 'rake'

module ActiveSanitization
  class RakeTasks
    include Rake::DSL if defined? Rake::DSL

    def install_tasks
      namespace:active_sanitization do
        desc "Sanitises MySQL database. If S3 creds are provided then the sanitized snapshot will be uploaded to S3"
        task :sanitize_and_export_data => :environment do
          ActiveSanitization.sanitize_and_export_data
        end

        desc "Import sanitized data from S3 into MySQL.  Optional arguments are `env` and `timestamp`.  These will default to 'production' and the latest snapshot if they are not provided"
        task :import_data_from_s3, [:env, :timestamp] => [:environment] do |t, args|
          ActiveSanitization.import_data(args[:env], args[:timestamp])
        end
      end
    end
  end
end

ActiveSanitization::RakeTasks.new.install_tasks
