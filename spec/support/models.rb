# frozen_string_literal: true

module Listable
  module Harness
    # The base class of every model the suite defines.
    #
    # The models are written here rather than generated so that a test reads
    # against a class whose whole definition fits on a screen. The class is
    # abstract so that it holds the connection without claiming a table, and
    # each subclass names its table explicitly because the harness namespace
    # must not leak into the table names of a throwaway schema.
    class Record < ActiveRecord::Base
      self.abstract_class = true
    end

    # A row carrying one column of every castable type.
    class Widget < Record
      self.table_name = "widgets"

      include Listable

      listable_fields %w[
        id name description quantity reference price ratio active released_on published_at
        status created_at
      ]

      # Backs a plain string column with an enum. The column stays a string in
      # the schema, which is what the pattern operators read when they decide
      # whether an expression is textual.
      enum :status, { draft: "draft", published: "published", archived: "archived" }
    end

    # A widget that declares nothing of its own.
    #
    # It exists to hold the inheritance claim upright: the whitelist a parent
    # declares must survive being subclassed, because single-table inheritance
    # would otherwise drop the surface without a single test noticing.
    class SpecialWidget < Widget
    end

    # A model that includes the gem and declares nothing at all.
    #
    # The fail-closed default has to be measured on a model that looks exactly
    # like one whose author forgot the declaration, which is why this class
    # carries a real table with real columns and still exposes none of them.
    class SealedWidget < Record
      self.table_name = "widgets"

      include Listable
    end

    # A model whose surface is computed rather than declared.
    #
    # The macro is a convenience, not a ceiling: a surface that has to be built
    # at call time is expressed by overriding the class method. The computed
    # list deliberately carries a name the table has no column for, the way a
    # surface derived from a serializer's exposed attributes would — a listing
    # serves such a field through a custom filter, and the engine must refuse
    # to build a predicate for it on its own rather than hand back every row.
    class ComputedWidget < Record
      self.table_name = "widgets"

      include Listable

      # Builds the listable surface at call time.
      #
      # ==== Returns
      #
      # The field names a client may name on this model.
      def self.listable_fields
        %w[name quantity owner]
      end
    end

    # A row on a table with no creation timestamp.
    class Gadget < Record
      self.table_name = "gadgets"

      include Listable

      listable_fields %w[id name position]
    end

    # A row whose +name+ is a JSON document keyed by locale.
    #
    # The attribute is declared translated only when the run carries the
    # translation library. With the library absent the class stays an ordinary
    # model over a JSON column, which is exactly what an application that
    # translates nothing installs.
    class Document < Record
      self.table_name = "documents"

      include Listable

      listable_fields %w[id name created_at]

      if Translations.available?
        extend Mobility

        translates :name
      end
    end
  end
end
