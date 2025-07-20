class CreateExcelFiles < ActiveRecord::Migration[8.0]
  def change
    create_table :excel_files do |t|
      t.references :user, null: false, foreign_key: true
      t.string :original_name, null: false
      t.string :file_path, null: false
      t.bigint :file_size, null: false
      t.string :content_hash
      t.integer :status, default: 0, null: false
      t.json :metadata
      t.integer :sheet_count
      t.integer :row_count
      t.integer :column_count
      t.string :file_format

      t.timestamps
    end

    add_index :excel_files, :status
    add_index :excel_files, :content_hash
    add_index :excel_files, :created_at
  end
end
