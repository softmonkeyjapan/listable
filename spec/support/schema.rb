# frozen_string_literal: true

module Listable
  module Harness
    # The throwaway schema the suite runs against.
    #
    # It is defined in code rather than loaded from a dumped +schema.rb+ so that
    # the tables a reader must know about are readable next to the tests that
    # use them, and it is rebuilt from scratch on every run so that a suite
    # interrupted halfway leaves nothing behind to repair by hand.
    module Schema
      module_function

      # (Re)builds every table the suite needs.
      #
      # ==== Returns
      #
      # +nil+.
      def load!
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          create_widgets(connection)
          create_gadgets(connection)
          create_documents(connection)
        end

        nil
      end

      # Creates the table carrying one column per castable type.
      #
      # The casting rules name string, text, integer, bigint, decimal, float,
      # boolean, date and datetime, and each of them needs a column of its own
      # so that a cast — and the failing cast that must drop its condition
      # silently — has something real to run against. +status+ is a plain string
      # column backed by an Active Record enum: textuality is read off the
      # column's type and not off the attribute's, so the enum must not make the
      # column stop being a string. +created_at+ is here because the default
      # order is +created_at+ descending.
      #
      # ==== Parameters
      #
      # * +connection+ - the connection to build the table through
      #
      # ==== Returns
      #
      # +nil+.
      def create_widgets(connection)
        connection.create_table(:widgets, force: :cascade) do |t|
          t.string :name
          t.text :description
          t.integer :quantity
          t.bigint :reference
          t.decimal :price, precision: 12, scale: 2
          t.float :ratio
          t.boolean :active
          t.date :released_on
          t.datetime :published_at
          t.string :status
          t.datetime :created_at, null: false
        end

        nil
      end

      # Creates the table that carries no creation timestamp.
      #
      # The gem must not impose a timestamp convention on its consumers: a model
      # whose table has no +created_at+ falls back to ordering on the primary
      # key alone. That fallback needs a table where the column is genuinely
      # absent, which is the only reason this table exists.
      #
      # ==== Parameters
      #
      # * +connection+ - the connection to build the table through
      #
      # ==== Returns
      #
      # +nil+.
      def create_gadgets(connection)
        connection.create_table(:gadgets, force: :cascade) do |t|
          t.string :name
          t.integer :position
        end

        nil
      end

      # Creates the table whose textual column is a JSON document.
      #
      # A translated attribute is stored as a JSON document keyed by locale, so
      # +name+ is +jsonb+ rather than a string. Comparing that column compares
      # the whole document and matches nothing, which is precisely the trap the
      # gem's locale extraction exists to avoid — the table gives the tests a
      # real document to run the extraction against.
      #
      # ==== Parameters
      #
      # * +connection+ - the connection to build the table through
      #
      # ==== Returns
      #
      # +nil+.
      def create_documents(connection)
        connection.create_table(:documents, force: :cascade) do |t|
          t.jsonb :name, default: {}, null: false
          t.datetime :created_at, null: false
        end

        nil
      end
    end
  end
end
