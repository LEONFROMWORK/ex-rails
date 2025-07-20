class CreateAnalyses < ActiveRecord::Migration[8.0]
  def change
    create_table :analyses do |t|
      t.references :excel_file, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.json :detected_errors
      t.json :ai_analysis
      t.json :corrections
      t.integer :ai_tier_used, default: 0, null: false
      t.decimal :confidence_score, precision: 3, scale: 2
      t.integer :credits_used, default: 0, null: false
      t.decimal :cost, precision: 10, scale: 6
      t.integer :status, default: 0, null: false
      t.integer :error_count, default: 0
      t.integer :fixed_count, default: 0
      t.text :analysis_summary

      t.timestamps
    end

    add_index :analyses, :status
    add_index :analyses, :ai_tier_used
    add_index :analyses, :confidence_score
    add_index :analyses, :created_at
  end
end
