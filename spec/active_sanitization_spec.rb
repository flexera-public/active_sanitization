require 'spec_helper'

describe ActiveSanitization do

  class CustomSanitization
    def self.sanitize_people(temp_db_connection)
      temp_db_connection.execute("DELETE FROM people WHERE age < 22")
    end
  end

  let(:db_name) { "active_sanitization" }

  before do
    ActiveSanitization.configure do |config|
      config.tables_to_sanitize = {
        "people" => ["address", "age", "gender", "id", "name"],
        "cars"   => ["id", "make", "model", "number_of_doors"],
      }
      config.tables_to_truncate = {
        "hotels" => ["address", "id", "name", "number_of_rooms"]
      }
      config.tables_to_ignore = {}
      config.sanitization_columns = {
        'name' => ['Tony', 'Adam', 'Claire', 'Sarah'],
        'make' => ['BMW', 'Toyota']
      }
      config.active_record_connection = ActiveRecord::Base.connection
      config.env = "test"
      config.db_config = {
       'host'     => "localhost",
       'username' => "root",
       'password' => nil,
       'database' => db_name,
       'adapter' => "mysql2",
      }
    end
  end

  describe ".pre_sanitization_checks" do
    context "extra tables" do
      before(:each) do
        ActiveRecord::Base.connection.create_table :testmodels do |t|
          t.string :name
        end
      end

      after(:each) do
        ActiveRecord::Base.connection.drop_table :testmodels
      end

      it "stops the rake task if a new table (that it doesn't know about) has been introduced" do
        expect(ActiveSanitization.pre_sanitization_checks[:pass]).to eq(false)
      end
    end

    context "extra columns" do
      before(:each) do
        ActiveRecord::Base.connection.add_column :cars, :fuel_type, :string
      end

      after(:each) do
        ActiveRecord::Base.connection.remove_column :cars, :fuel_type
      end

      it "stops the rake task if a new column (that it doesn't know about) has been introduced" do
        expect(ActiveSanitization.pre_sanitization_checks[:pass]).to eq(false)
      end
    end

    context "no new tables or columns have been added" do
      # This will fail if a new column or table has been added but the hashes haven't been updated
      it "doesn't stop" do
        expect(ActiveSanitization.pre_sanitization_checks).to eq({
          :pass => true
        })
      end
    end
  end

  describe ".duplicate_database" do
    before(:each) do
      @temp_db, @temp_db_connection, @temp_db_config = ActiveSanitization.duplicate_database
    end

    after(:each) do
     ActiveRecord::Base.connection.execute("DROP DATABASE #{@temp_db};")
    end

    it "creates a temp db" do
      expect(@temp_db_connection.current_database).to eq(@temp_db)
      expect(@temp_db_connection.current_database).to_not eq(db_name)
    end
  end

  describe ".clean_up_temp_db" do
    before(:each) do
      @temp_db, @temp_db_connection, @temp_db_config = ActiveSanitization.duplicate_database
      ActiveSanitization.clean_up_temp_db(@temp_db)
    end

    it "checks the temp db doesn't exist afterwards" do
      databases = ActiveRecord::Base.connection.execute("SHOW DATABASES").collect { |data| data.first }
      expect(databases.to_s).to match(/#{db_name}/)
      expect(databases).to_not include(@temp_db)
    end
  end

  context "sanitization checks" do
    describe ".sanitize_table" do
      before(:each) do
        @temp_db, @temp_db_connection, @temp_db_config = ActiveSanitization.duplicate_database
        ActiveSanitization.sanitize_tables(@temp_db_connection)
      end

      context "people" do
        it "performs default sanitization on the table" do
          expect(@temp_db_connection.select_values("select name from people")).to_not include(['Jim', 'Craig', 'Andrew', 'Sarah'])
        end

        it "no models have been deleted" do
          expect(@temp_db_connection.select_value("select count(*) from people")).to eq(4)
        end
      end

      context "cars" do
        it "performs default sanitization on the table" do
          expect(@temp_db_connection.select_values("select make from cars")).to_not include(["Ford"])
        end

        it "no models have been deleted" do
          expect(@temp_db_connection.select_value("select count(*) from cars")).to eq(1)
        end
      end

      context "hotels" do
        it "all models have been deleted" do
          expect(@temp_db_connection.select_value("select count(*) from hotels")).to eq(0)
        end
      end
    end

    context "custom santization" do
      before(:each) do
        ActiveSanitization.configure do |config|
          config.custom_sanitization = CustomSanitization
        end
        @temp_db, @temp_db_connection, @temp_db_config = ActiveSanitization.duplicate_database
        ActiveSanitization.sanitize_tables(@temp_db_connection)
      end

      context "performs custom sanitization on the people table" do
        it "all people who are younger than 22 get deleted" do
          expect(@temp_db_connection.select_value("select count(*) from people")).to eq(2)
          expect(@temp_db_connection.select_values("select age from people")).to eq([22, 84])
        end
      end
    end
  end

  describe "Rake task doesn't make any changes to the primary db" do
    before(:each) do
      @temp_db, @temp_db_connection, @temp_db_config = ActiveSanitization.duplicate_database
      ActiveSanitization.sanitize_tables(@temp_db_connection)
    end

    context "people" do
      it "doesn't perform sanitization on the table" do
        expect(ActiveRecord::Base.connection.select_values("select name from people")).to match(['Jim', 'Craig', 'Andrew', 'Sarah'])
      end

      it "no models have been deleted" do
        expect(ActiveRecord::Base.connection.select_value("select count(*) from people")).to eq(4)
      end
    end

    context "cars" do
      it "doesn't perform sanitization on the table" do
        expect(ActiveRecord::Base.connection.select_values("select make from cars")).to eq(["Ford"])
      end

      it "no models have been deleted" do
        expect(ActiveRecord::Base.connection.select_value("select count(*) from cars")).to eq(1)
      end
    end

    context "hotels" do
      it "no models have been deleted" do
        expect(ActiveRecord::Base.connection.select_value("select count(*) from hotels")).to eq(3)
      end
    end
  end

  describe ".clean_up_files" do
    before(:each) do
      @dump_file, @compressed_dump_file = ActiveSanitization.create_files
      ActiveSanitization.clean_up_files(@dump_file, @compressed_dump_file)
    end

    it "creates a dump file" do
      expect(File.exists?(@dump_file)).to eq(false)
      expect(File.exists?(@compressed_dump_file)).to eq(false)
    end
  end

  describe ".export_temp_db_to_file" do
    before(:each) do
      @temp_db, @temp_db_connection, @temp_db_config = ActiveSanitization.duplicate_database
      @dump_file, @compressed_dump_file = ActiveSanitization.create_files
      ActiveSanitization.export_temp_db_to_file(@dump_file, @temp_db_config, @temp_db)
    end

    after(:each) do
      ActiveSanitization.clean_up_files(@dump_file, @compressed_dump_file)
    end

    it "creates a dump file" do
      expect(File.exists?(@dump_file)).to eq(true)
    end
  end
end
