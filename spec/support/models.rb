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

      # Backs a plain string column with an enum. The column stays a string in
      # the schema, which is what the pattern operators read when they decide
      # whether an expression is textual.
      enum :status, { draft: "draft", published: "published", archived: "archived" }
    end

    # A row on a table with no creation timestamp.
    class Gadget < Record
      self.table_name = "gadgets"
    end

    # A row whose +name+ is a JSON document keyed by locale.
    class Document < Record
      self.table_name = "documents"
    end
  end
end
