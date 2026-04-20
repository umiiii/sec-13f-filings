class CreateStockPrices < ActiveRecord::Migration[6.1]
  def change
    create_table :stock_prices do |t|
      t.text :symbol, null: false
      t.date :date, null: false
      t.decimal :close, precision: 15, scale: 4
      t.timestamps
    end

    add_index :stock_prices, [:symbol, :date], unique: true
  end
end
