ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")

ActiveRecord::Schema.define(:version => 1) do
  create_table :foobars do |t|
    t.string :foo_id
    t.string :bar_id
    t.datetime :foo_date
    t.datetime :bar_date
  end

  create_table :barfoos do |t|
    t.string :status
    t.string :favorite_drink
    t.string :favorite_food
  end

  create_table :users do |t|
    t.string :role
  end

  # default Rails 4 beta1 scaffold generated model
  create_table :posts do |t|
    t.string :name
    t.string :title
    t.text :content

    t.timestamps
  end

  # copied default Rails 4 scaffold-generated model for comparison
  create_table :my_posts do |t|
    t.string :name
    t.string :title
    t.text :content

    t.timestamps
  end
end
