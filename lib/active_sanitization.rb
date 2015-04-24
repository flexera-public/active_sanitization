require "active_sanitization/version"
require_relative "tasks/rake_tasks"
require "active_record"
require "active_support"
require 'aws-sdk'

module ActiveSanitization
  class << self
    attr_accessor :configuration
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration)
  end

  class Configuration
    attr_accessor :tables_to_sanitize, :tables_to_truncate, :tables_to_ignore, :sanitization_columns, :s3_bucket, :app_name, :aws_access_key_id, :aws_secret_access_key, :env, :active_record_connection, :db_config, :custom_sanitization, :loggers, :root, :s3_bucket_region

    def initialize
      @tables_to_sanitize = {}
      @tables_to_truncate = {}
      @tables_to_ignore = {}
      @sanitization_columns = {}
      @s3_bucket = 'active_sanitization'
      @env = ENV['RACK_ENV'] || ENV['RAILS_ENV']
      @active_record_connection = ActiveRecord::Base.connection
      @root = File.dirname(File.dirname(__FILE__))
      @loggers = [Logger.new(STDOUT)]
    end
  end

  # Need to create a second ActiveRecord::Base.connection so we can
  # connect to the primary and copy DB.
  class TempDatabaseConnection < ActiveRecord::Base
    def self.abstract_class?
      true # So it gets its own connection
    end
  end

  # Returns a hash that represents the difference between two hashes.
  #
  #   hash_diff({1 => 2}, {1 => 2})         # => {}
  #   hash_diff({1 => 2}, {1 => 3})         # => {1 => 2}
  #   hash_diff({}, {1 => 2})               # => {1 => 2}
  #   hash_diff({1 => 2, 3 => 4}, {1 => 2}) # => {3 => 4}
  def self.hash_diff(hash1, hash2)
    difference1 = hash1.dup
    difference2 = hash2.dup

    difference1.delete_if do |key, value|
      hash2[key] == value
    end

    difference2.delete_if do |key, value|
      hash1.has_key?(key)
    end

    difference1.merge(difference2)
  end

  def self.log(output)
    self.configuration.loggers.each do |logger|
      logger.info(output)
    end unless self.configuration.env == 'test'
  end

  def self.pre_sanitization_checks
    db_tables = {}
    self.configuration.active_record_connection.tables.each do |table_name|
      next if self.configuration.tables_to_ignore.include?(table_name)
      db_tables[table_name] = []
      self.configuration.active_record_connection.columns(table_name).each { |c| db_tables[table_name] << c.name }
      db_tables[table_name].sort!
    end

    # diff will only work correctly if the columns are sorted the same
    tables_with_sorted_columns = {}
    self.configuration.tables_to_sanitize.merge(self.configuration.tables_to_truncate).each { |k, v| tables_with_sorted_columns[k] = v.sort }
    table_difference = hash_diff(db_tables, tables_with_sorted_columns)
    checks = {}
    if table_difference != {}
      column_difference = {}
      table_difference.collect do |table_name, table_columns|
        column_difference[table_name] = table_columns - self.configuration.tables_to_sanitize.merge(self.configuration.tables_to_truncate)[table_name].to_a
      end
      checks[:pass] = false
      checks[:error] = "The following tables or columns have been found in the #{self.configuration.env} DB but are not known to this script (#{column_difference}).\n Please update the active_sanitization config!"
    else
      checks[:pass] = true
    end
    checks
  end

  def self.duplicate_database
    temp_db = "#{self.configuration.db_config['database']}_copy"

    self.log("Deleting temp DB if exists")
    self.configuration.active_record_connection.execute("DROP DATABASE IF EXISTS #{temp_db};")
    self.log("Creating temp DB")
    self.configuration.active_record_connection.execute("CREATE DATABASE #{temp_db}")
    self.log("Copying #{self.configuration.env} DB to temp DB")
    self.log("mysqldump -h #{self.configuration.db_config['host']} -u #{self.configuration.db_config['username']} --password=#{self.configuration.db_config['password']} #{self.configuration.db_config['database']} #{self.configuration.tables_to_sanitize.keys.join(' ')} | mysql -h #{self.configuration.db_config['host']}  -u #{self.configuration.db_config['username']} --password=#{self.configuration.db_config['password']} -D #{temp_db}")
    system("mysqldump -h #{self.configuration.db_config['host']} -u #{self.configuration.db_config['username']} --password=#{self.configuration.db_config['password']} #{self.configuration.db_config['database']} #{self.configuration.tables_to_sanitize.keys.join(' ')} | mysql -h #{self.configuration.db_config['host']}  -u #{self.configuration.db_config['username']} --password=#{self.configuration.db_config['password']} -D #{temp_db}")
    if $?.exitstatus == 0
      self.log("Temp DB created and populated")
    else
      raise "Failed to load DB #{self.configuration.db_config} into temp DB #{temp_db}."
    end

    self.log("mysqldump -h #{self.configuration.db_config['host']} -u #{self.configuration.db_config['username']} --password=XXXXXXXXX --no-data #{self.configuration.db_config['database']} #{self.configuration.tables_to_truncate.keys.join(' ')} | mysql -h #{self.configuration.db_config['host']}  -u #{self.configuration.db_config['username']} --password=XXXXXXXXX -D #{temp_db}")
    system("mysqldump -h #{self.configuration.db_config['host']} -u #{self.configuration.db_config['username']} --password=#{self.configuration.db_config['password']} --no-data #{self.configuration.db_config['database']} #{self.configuration.tables_to_truncate.keys.join(' ')} | mysql -h #{self.configuration.db_config['host']}  -u #{self.configuration.db_config['username']} --password=#{self.configuration.db_config['password']} -D #{temp_db}")
    if $?.exitstatus == 0
      self.log("Temp DB created and populated")
    else
      raise "Failed to load DB #{self.configuration.db_config} into temp DB #{temp_db}."
    end

    temp_db_config = self.configuration.db_config.dup
    temp_db_config['database'] = temp_db
    TempDatabaseConnection.establish_connection(temp_db_config)
    temp_db_connection = TempDatabaseConnection.connection

    [temp_db, temp_db_connection, temp_db_config]
  end

  def self.sanitize_table(table, temp_db_connection)
    table_columns = temp_db_connection.select_values("DESCRIBE #{table};")
    self.configuration.sanitization_columns.keys.each do |column|
      if table_columns.include?(column)
        distinct_values = temp_db_connection.execute("SELECT DISTINCT(#{column}) FROM #{table};").collect { |data| data.first }
        distinct_values.each do |value|
          temp_db_connection.execute("UPDATE #{table} SET #{column}='#{self.configuration.sanitization_columns[column].sample}' WHERE #{column}=#{ActiveRecord::Base.sanitize(value)};")
        end
      end
    end

    # Run any custom sanitization for the table
    self.configuration.custom_sanitization.send("sanitize_#{table}", temp_db_connection) if self.configuration.custom_sanitization.respond_to?("sanitize_#{table}")
  end

  def self.create_files
    dump_file = "#{File.join(self.configuration.root, "tmp")}/data.dump"
    compressed_dump_file = "#{dump_file}.gz"
    File.new(dump_file,  "w+")
    File.new(compressed_dump_file,  "w+")
    [dump_file, compressed_dump_file]
  end

  def self.sanitize_tables(temp_db_connection)
    self.log("Processing TABLES_TO_TRUNCATE...")
    self.configuration.tables_to_truncate.keys.each do |table|
       self.log("Truncating #{table}")
       temp_db_connection.execute("TRUNCATE #{table};")
    end

    self.log("Processing TABLES_TO_SANITIZE...")
    self.configuration.tables_to_sanitize.keys.each do |table|
      self.log("Sanitizing #{table}")
      self.sanitize_table(table, temp_db_connection)
    end
  end

  def self.clean_up_temp_db(temp_db)
    self.log("Dropping #{temp_db}")
    self.configuration.active_record_connection.execute("DROP DATABASE #{temp_db};")
  end

  def self.gzip(dump_file)
    self.log("Gzipping #{dump_file}")
    system("gzip '#{dump_file}'")
  end

  def self.get_s3_bucket
    creds = Aws::Credentials.new(self.configuration.aws_access_key_id, self.configuration.aws_secret_access_key)
    client = Aws::S3::Client.new(credentials: creds, region: self.configuration.s3_bucket_region)
    resource = Aws::S3::Resource.new(client: client)
    resource.bucket(self.configuration.s3_bucket)
  end

  def self.upload(compressed_dump_file)
    timestamp = DateTime.now.strftime('%Y%m%d%H%M%S')
    name = "#{self.configuration.app_name}/#{self.configuration.env}/mysql/#{timestamp}/#{File.basename(compressed_dump_file)}"
    self.log("Uploading to bucket: #{self.configuration.s3_bucket}, path: #{name}")
    file = File.open(compressed_dump_file, 'r')

    bucket = get_s3_bucket
    obj = bucket.object(name)
    obj.put(body: file)

    file.close
    File.unlink(compressed_dump_file)

    obj
  end

  def self.clean_up_files(dump_file, compressed_dump_file)
    self.log("Deleting #{dump_file}")
    File.delete(dump_file) if File.exist?(dump_file)
    self.log("Deleting #{compressed_dump_file}")
    File.delete(compressed_dump_file) if File.exist?(compressed_dump_file)
  end

  def self.export_temp_db_to_file(dump_file, temp_db_config, temp_db)
    self.log("Dumping temp DB to #{dump_file}")
    system("mysqldump -h #{temp_db_config['host']} -u #{temp_db_config['username']} --password=#{temp_db_config['password']} #{temp_db} >> '#{dump_file}'")
    if $?.exitstatus == 0
      self.log("Dump created")
    else
      self.log("Failed to create dump")
      return
    end
  end

  def self.is_dev_or_integration_env?
    self.configuration.env == 'development' || self.configuration.env == 'integration'
  end

  def self.sanitize_and_export_data
    checks = self.pre_sanitization_checks
    if checks[:pass]
      dump_file, compressed_dump_file = self.create_files
      self.clean_up_files(dump_file, compressed_dump_file)

      # If in dev or integration env we don't need to sanatise the DB so we should
      # just dump it to a file and upload
      if self.is_dev_or_integration_env?
        self.export_temp_db_to_file(dump_file, self.configuration.db_config, self.configuration.db_config["database"])
      else
        temp_db, temp_db_connection, temp_db_config = self.duplicate_database

        self.sanitize_tables(temp_db_connection)

        self.export_temp_db_to_file(dump_file, temp_db_config, temp_db)

        self.clean_up_temp_db(temp_db)
      end

      self.gzip(dump_file)

      if self.configuration.s3_bucket && self.configuration.aws_access_key_id && self.configuration.aws_secret_access_key
        self.upload(compressed_dump_file)
      else
        self.clean_up_files(dump_file, compressed_dump_file)
      end

      self.log("-- DONE --")
    else
      self.log(checks[:error])
    end
  end

  def self.import_data(env = nil, timestamp = nil)
    env = "production" if env.nil?
    prefix = "#{self.configuration.app_name}/#{env}/mysql"

    bucket = get_s3_bucket
    if timestamp.nil?
      timestamp = bucket.objects(prefix: prefix).collect {|x| x.key[%r(#{prefix}\/(.*)\/), 1] }.max
    end

    # Check that there are files (as the user could have passed in an incorrect timestamp)
    if timestamp.nil?
      self.log("No mysql snapshot for timestamp #{prefix}/#{timestamp}")
      return
    end

    self.log('WARNING: this rake task will dump your MySQL DB to a file, then wipe your DB before importing a snapshot')
    local_dump_file = "#{File.join(self.configuration.root, "tmp")}/local_data.dump"

    # Make copy of local DB just in case something goes wrong
    system("mysqldump -h #{self.configuration.db_config['host']} -u #{self.configuration.db_config['username']} --password=#{self.configuration.db_config['password']} #{self.configuration.db_config['database']} > '#{local_dump_file}'")
    if $?.exitstatus == 0
      self.log("Local DB dump stored in #{local_dump_file}")
    else
      raise "Failed to create a local DB dump. If a previous local dump exists, please delete it and try again."
    end

    # get all the files in the snapshot
    objects = bucket.objects("#{prefix}/#{timestamp}")
    dump_file = "#{File.join(self.configuration.root, "tmp")}/data.dump"
    compressed_dump_file = "#{dump_file}.gz"
    self.log("Downloading file to #{compressed_dump_file}")
    url = objects.first.object.presigned_url(:get, expires_in: 600)
    system("curl -o #{compressed_dump_file} '#{url}'")

    # reset db
    self.log("Recreating your local DB")
    Rake::Task["db:drop"].invoke
    Rake::Task["db:create"].invoke

    # Import data
    self.log("Unzipping and importing data...")
    system("gunzip -c '#{compressed_dump_file}' | mysql -uroot #{self.configuration.db_config['database']}")
    if $?.exitstatus == 0
      File.delete(compressed_dump_file) if File.exist?(compressed_dump_file)
    else
      raise "Could not load #{compressed_dump_file} into DB #{self.configuration.db_config}"
    end
    self.log('-- DONE --')
  end
end
