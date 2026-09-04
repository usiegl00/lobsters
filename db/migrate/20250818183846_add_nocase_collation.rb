class AddNocaseCollation < ActiveRecord::Migration[8.0]
  def up
    if connection.adapter_name == "PostgreSQL"
      execute("CREATE COLLATION IF NOT EXISTS \"NOCASE\" (provider = icu, locale = 'und-u-ks-level2', deterministic = false);")
    end
  end

  def down
    if connection.adapter_name == "PostgreSQL"
      execute("DROP COLLATION IF EXISTS \"NOCASE\";")
    end
  end
end
