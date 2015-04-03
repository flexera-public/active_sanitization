# Active Sanitization

Active Sanitization provides an easy way to sanitize your mysql database.  By using the configuration options you are able customize what gets sanitized, truncated and ignored.  You can also provide S3 creds, that will allow the sanitized snapshot to be uploaded.  This makes it easy for everyone to get access to this snapshot without having to go through production access gatekeeper.

## Features
### How it works
Active Sanitization works by copying your current database into a temporary one.  Once this is done it allows a series of santizations to be performed.
Before any of this happens it checks that the database doesn't contain any extra tables or columns that it doesn't know about.  This means that there is no way an extra column can be added without the correct sanitization being added. (Please see the Sanitization tests section for more details).

Once all the pre_sanitization checks have been performed and passed, then the sanitization process can begin.  Active Sanitization will copy the content of all tables that require sanitizationand all tables that should be truncated (without data) to a temporary database.  The sanitization process is relatively simple.  It will loop through all tables, and if that table has any columns that require sanitization then it will do that.  It does that by swapping all distinct values for each column that requires sanitization with a random value from the allowed sanitized substitutes.  Once it has done this it will call through to a Custom Santization class that you provide. (Please see usage for how this works).

After all tables have been sanitized then the the temporary table will be exported to a tmp directory, before being dropped.

### S3 Upload

There is an option to upload the sanitized snapshot to S3, and fetch it again.  To do this simply provide the following values in the ActiveSantization config
```
s3_bucket
s3_bucket_region
aws_access_key_id
aws_secret_access_key
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'active_sanitization'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install active_sanitization

## Usage

To use Active Sanitization add the following to your Rakefile
```
require 'active_sanitization'
```

Next you will need to configure the gem.  This should be done in an initializer:
```ruby
# After going through a tables standard sanitization ActiveSanitization can call out to a custom bit of code.
# This allows you to provide varies custom sanitizations that require a bit more in depth knowledge of the data involved.
# To do this you should provide a class, that contains the custom sanitization code.  ActiveSantization will call any function named
# `santize_TABLE_NAME`, and will pass is an ActiveRecord::Base.connection to the temporary database (that contains data that is being sanitized)
# The example bellow removes all rows from the `people` table who have an age less than 22.
class CustomSanitization
  def self.sanitize_person(temp_db_connection)
    temp_db_connection.execute("DELETE FROM people WHERE age < 22")
  end
end

ActiveSanitization.configure do |config|
  # Tables that need to be sanitized
  # This is a hash, where the key is each table name, and the value being an array of
  #    of all the columns in that table
  config.tables_to_sanitize = {
    "people" => ["address", "age", "gender", "id", "name"],
    "cars"   => ["id", "make", "model", "number_of_doors"],
  }

  # Tables that need to be truncated
  # This is a hash, where the key is each table name, and the value being an array of
  #    of all the columns in that table
  # After the sanitization process these tables will exist in the database dump, but they will be empty
  config.tables_to_truncate = {
    "hotels" => ["address", "id", "name", "number_of_rooms"]
  }

  # This is an array of all the other tables in the database that will be ignored.
  # These will not be exported or have any sanitization applied to them
  config.tables_to_ignore = []

  # This is a hash of standard sanitizations that are applied to all columns with the same name as the key
  #   This is a hash where the key is the name of the column that needs to be sanitized, and the values what
  #   the values in the column are going to be replaced with.
  # For example every column called `name` will have the values replaced randomly as on the following values `['Tony', 'Adam', 'Claire', 'Sarah']`
  config.sanitization_columns = {
    'name' => ['Tony', 'Adam', 'Claire', 'Sarah'],
    'make' => ['BMW', 'Toyota']
  }

  # This is the active_record_connection to the mysql database.  The connection to the correct database should already be established
  config.active_record_connection = ActiveRecord::Base.connection

  # The current environment that your application is running in
  config.env = "test"

  # This is the database config, that ActiveRecord used to connect to the database.
  #   This is needed so we can establish a second connection to a temporary database (where we perform the sanitization)
  config.db_config = {
   'host'     => "localhost",
   'username' => "root",
   'password' => nil,
   'database' => "active_sanitization",
   'adapter' => "mysql2",
  }

  # The name of your app
  config.app_name = 'super_secret_app'

  # The logger that the gem should use.
  #  This will default to STOUT if non is provided
  config.logger = Rails.logger

  # The path to the root of your project
  #  This is required so the database dump can be put in a tmp folder
  config.root = File.dirname(File.dirname(__FILE__))

  # This is a class that you provide to do custom sanitization
  config.custom_sanitization = CustomSanitization

  # Upload to S3.
  # There is an option to upload the sanitized database dump
  config.s3_bucket = S3_BUCKET
  config.s3_bucket_region = 'us-east-1'
  config.aws_access_key_id = AWS_ACCESS_KEY_ID
  config.aws_secret_access_key = AWS_SECRET_ACCESS_KEY
end
```
### Sanitization tests

Active Sanitization provides an easy way to add a test that will fail if the config is not updated to include all tables and columns.
This can be done like:
```
require 'spec_helper'

describe ActiveSanitization do
  context ".pre_sanitization_checks" do
    context "no new tables or columns have been added" do
      # This will fail if a new column or table has been added but the hashes haven't been updated
      it "doesn't stop" do
        expect(ActiveSanitization.pre_sanitization_checks).to eq({
          :pass => true
        })
      end
    end
  end
end
```

It is also good to add tests for any custom sanitizations that you add.  Once you have loaded your data into the database, you can call:
```
@temp_db, @temp_db_connection, @temp_db_config = ActiveSanitization.duplicate_database
ActiveSanitization.sanitize_tables(@temp_db_connection)
```
This will duplicate the database and call the sanitization code.  After this has run you should assert that your custom sanitization has performed as expected.

## Actually using the gem

This can be done using two rake tasks that ActiveSanitization provides.
```
rake active_sanitization:import_data_from_s3[env,timestamp]
    Import sanitized data from S3 into MySQL.  Optional arguments are `env` and `timestamp`.  These will default to 'production' and the latest snapshot if they are not provided

rake active_sanitization:sanitize_and_export_data
    Sanitises MySQL database. If S3 creds are provided then the sanitized snapshot will be uploaded to S3
```

## Running the specs

This is the default rake task so you can run the specs in any of the following ways:

```bash
bundle exec rake
bundle exec rake spec
```

## Getting a console

The project is currently using pry. In order to get a console in the context of the project just run the pry.rb file in ruby.

```bash
bundle exec rake console
```

## Contributing

1. Fork it ( https://github.com/[my-github-username]/active_sanitization/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Maintained by

- [Stephen Haley](https://github.com/shaley91)
