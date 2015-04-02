ActiveRecord::Schema.define do
  create_table :people, :force => true do |table|
    table.string :name
    table.integer :age
    table.text :address
    table.boolean :gender
  end

  create_table :hotels, :force => true do |table|
    table.string :name
    table.text :address
    table.integer :number_of_rooms
  end

  create_table :cars, :force => true do |table|
    table.string :make
    table.string :model
    table.integer :number_of_doors
  end
end
