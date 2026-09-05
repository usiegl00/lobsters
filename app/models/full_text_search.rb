require "active_support/concern"

module FullTextSearch
  def self.sqlite?
    ActiveRecord::Base.connection.adapter_name.downcase.include?("sqlite")
  end

  def self.postgresql?
    ActiveRecord::Base.connection.adapter_name.downcase.start_with?("postgresql")
  end

  def self.postgresql_search(relation, table_name, columns, query)
    quoted_table = relation.connection.quote_table_name(table_name)
    search_columns = if query.to_s.start_with?("title: ") && columns.include?(:title)
      [:title]
    else
      columns
    end
    phrases = query.to_s.scan(/"((?:[^"]|"")*)"/).flatten.map { |phrase|
      phrase.gsub('""', '"')
    }
    return relation.none if phrases.empty?

    document = search_columns.map { |column|
      "coalesce(#{quoted_table}.#{relation.connection.quote_column_name(column)}, '')"
    }.join(" || ' ' || ")
    tsqueries = (["phraseto_tsquery('simple', ?)"] * phrases.length).join(" && ")

    relation.where("to_tsvector('simple', #{document}) @@ (#{tsqueries})", *phrases)
  end

  def self.[](*cols)
    Module.new do
      extend ActiveSupport::Concern

      included do
        after_create do |record|
          next unless FullTextSearch.sqlite?

          table_name = "#{record.class.table_name}_fts"
          column_list = cols.join(", ")
          value_list = (["?"] * cols.length).join(", ")
          values = cols.map { |c| record.public_send(c) }

          ActiveRecord::Base.connection.exec_insert("INSERT INTO #{table_name} (rowid, #{column_list}) values (?, #{value_list})", nil, [record.id] + values)
        end

        after_update do |record|
          next unless FullTextSearch.sqlite?

          any_changes = cols.map { |c| record.saved_change_to_attribute(c) }.any?

          if any_changes
            # contentless-delete tables in sqlite require all the columns when updating them, see for more info:
            # https://www.sqlite.org/fts5.html#contentless_delete_tables

            table_name = "#{record.class.table_name}_fts"
            column_list = cols.map { |c| "#{c} = ?" }.join(", ")
            values = cols.map { |c| record.public_send(c) }

            ActiveRecord::Base.connection.exec_update("UPDATE #{table_name} set #{column_list} where rowid = ?", nil, values + [record.id])
          end
        end

        after_destroy do |record|
          next unless FullTextSearch.sqlite?

          table_name = "#{record.class.table_name}_fts"

          ActiveRecord::Base.connection.exec_delete("DELETE FROM #{table_name} where rowid = ?", nil, [record.id])
        end
      end
    end
  end
end
