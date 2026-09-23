# frozen_string_literal: true

require "rack"

module Listable
  module Harness
    # Reads the README as the source of the examples the suite runs.
    #
    # Nothing here is a copy of what the README says, and that is the whole
    # point of the module. A spec that retyped the query strings would drift
    # from the document at the first correction and would afterwards prove only
    # that the spec agrees with itself — while the examples a consumer actually
    # copies rot unmeasured. Reading the file means a README example that stops
    # being true stops the suite, and an example added to the README is run
    # without anybody remembering to add it here.
    module Readme
      # The document the examples are read out of.
      PATH = File.expand_path("../../README.md", __dir__)

      # The fence an executable query-string example is written in.
      #
      # The tag is what separates an example from a shape sketch: the format's
      # skeleton and the payload a programmatic caller passes are written in
      # other fences, and neither is a query string a client could send.
      FENCE = /^```http\n(.*?)^```/m

      # The header that opens the operator table.
      TABLE_HEADER = "| Operator "

      # The line that pins an installation to a version.
      INSTALL_TAG = /tag:\s*['"]([^'"]+)['"]/

      module_function

      # Reads the document once.
      #
      # ==== Returns
      #
      # The README as a string.
      def source
        @source ||= File.read(PATH)
      end

      # Reads every query-string example the README offers a client.
      #
      # A block's lines are joined with the separator a query string uses, so
      # that an example may be wrapped one condition per line — which is the
      # only way the two-condition range reads as two conditions — and still be
      # the single string a client sends.
      #
      # ==== Returns
      #
      # An array of query strings.
      def query_strings
        source.scan(FENCE).map do |(block)|
          block.lines.map(&:strip).reject(&:empty?).join("&")
        end
      end

      # Reads the operators the README's table claims the gem understands.
      #
      # ==== Returns
      #
      # An array of operator strings, in the order the table lists them.
      def operators
        table_rows.map { |row| row.split("|")[1].delete("`").strip }
      end

      # Reads the version tag the README's installation snippet pins.
      #
      # ==== Returns
      #
      # The tag as a string, or +nil+ when the snippet pins none.
      def install_tag
        source[INSTALL_TAG, 1]
      end

      # Reads the body rows of the operator table.
      #
      # The two lines after the header are the header itself and the alignment
      # row, so the body starts two lines down and runs until the table stops.
      #
      # ==== Returns
      #
      # An array of the table's body lines.
      def table_rows
        lines = source.lines.map(&:chomp)
        header = lines.index { |line| line.start_with?(TABLE_HEADER) }

        lines[(header + 2)..].take_while { |line| line.start_with?("|") }
      end
    end
  end
end
