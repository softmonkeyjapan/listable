# frozen_string_literal: true

require "bigdecimal"
require "time"
require "active_support/core_ext/time/zones"

module Listable
  # Interprets a filter value according to the type of the column it is
  # compared against.
  #
  # The rules are deliberately strict where Active Record's own casts are
  # forgiving: +ActiveModel::Type::Integer+ turns <tt>"abc"</tt> into +0+ and
  # would hand a client the rows whose quantity is zero in answer to a typo.
  # Every conversion here either produces the value the column's type expects
  # or raises Failure, which the engine reads as "drop this one condition" —
  # the only treatment that neither invents rows nor turns a client mistake
  # into a replayable server error.
  module Casting
    # Raised when a value cannot be interpreted as the column's type.
    #
    # It is a distinct class rather than the conversion's own +ArgumentError+
    # so that the engine can rescue exactly the failure of a cast around the
    # narrowest possible expression. A bare +rescue StandardError+ at the call
    # site would swallow a bug in predicate building just as quietly as it
    # swallows a malformed date.
    class Failure < StandardError; end

    # Active Record's boolean type, instantiated once.
    #
    # Booleans are the one cast the specification hands to Active Record rather
    # than to Ruby, because the set of strings a client may send for false —
    # <tt>"0"</tt>, <tt>"f"</tt>, <tt>"false"</tt>, <tt>"off"</tt> — is Active
    # Record's to define, and reimplementing it here would drift from what the
    # same value means when it reaches the adapter.
    BOOLEAN = ActiveModel::Type::Boolean.new

    # The conversion each column type is read through.
    #
    # The map is a table rather than a case statement so that the list of types
    # the gem claims to interpret can be read in one glance and compared with
    # the schema — a type that silently fell out of a long branch would leave
    # its values uninterpreted and its filters comparing a string to a number.
    CASTS = {
      date: :date,
      datetime: :time,
      timestamp: :time,
      integer: :integer,
      bigint: :integer,
      decimal: :decimal,
      float: :float,
      boolean: :boolean,
    }.freeze

    class << self
      # Casts a filter value according to the column's declared type.
      #
      # An unknown type — and a translated attribute, which carries no column
      # type at all — leaves the value untouched, because the engine has no
      # ground to reinterpret a value whose storage it does not recognise, and
      # guessing would be a silent rewrite of what the client asked for.
      #
      # ==== Parameters
      #
      # * +value+ - the raw value as received from the client
      # * +type+ - the Active Record type symbol of the column, or +nil+
      #
      # ==== Returns
      #
      # The cast value, or the untouched value when the type is unknown.
      #
      # ==== Raises
      #
      # Failure when the value cannot be interpreted as the type.
      def call(value, type)
        conversion = CASTS[type]

        return value if conversion.nil?

        send(conversion, value)
      rescue StandardError => error
        raise Failure, "#{value.inspect} is not a valid #{type}: #{error.message}"
      end

      private

      # Reads a value as a fixed-precision number.
      #
      # The value goes through +to_s+ because +BigDecimal+ refuses a Float
      # without a precision, and a client's number arrives as a string anyway.
      #
      # ==== Parameters
      #
      # * +value+ - the raw value as received from the client
      #
      # ==== Returns
      #
      # A +BigDecimal+.
      def decimal(value)
        BigDecimal(value.to_s)
      end

      # Reads a value as a floating-point number.
      #
      # ==== Parameters
      #
      # * +value+ - the raw value as received from the client
      #
      # ==== Returns
      #
      # A +Float+.
      def float(value)
        Float(value)
      end

      # Reads a value as a boolean, through Active Record's own type.
      #
      # ==== Parameters
      #
      # * +value+ - the raw value as received from the client
      #
      # ==== Returns
      #
      # +true+, +false+ or +nil+.
      def boolean(value)
        BOOLEAN.cast(value)
      end

      # Reads a value as a date.
      #
      # A +Date+ is handed back as it is: +Date.parse+ takes a string, and
      # round-tripping a date object through +to_s+ only adds a way to fail.
      #
      # ==== Parameters
      #
      # * +value+ - the raw value as received from the client
      #
      # ==== Returns
      #
      # A +Date+.
      def date(value)
        value.is_a?(Date) ? value : Date.parse(value.to_s)
      end

      # Reads a value as a point in time.
      #
      # Parsing goes through +Time.zone+ when the host has configured one, so
      # that a client's <tt>"2026-01-10 08:00"</tt> means the same instant here
      # as it does everywhere else in the application. The nil check is not
      # defensive padding: +Time.parse+ raises on a value it cannot read, but
      # +ActiveSupport::TimeZone#parse+ answers +nil+, and an unchecked +nil+
      # would become a comparison against NULL that matches no row and reports
      # nothing.
      #
      # ==== Parameters
      #
      # * +value+ - the raw value as received from the client
      #
      # ==== Returns
      #
      # A +Time+ or an +ActiveSupport::TimeWithZone+.
      def time(value)
        return value if value.is_a?(Time) || value.is_a?(DateTime)

        parsed = Time.zone ? Time.zone.parse(value.to_s) : Time.parse(value.to_s)
        raise ArgumentError, "no time could be read" if parsed.nil?

        parsed
      end

      # Reads a value as an integer.
      #
      # The base is forced to ten for strings, because +Integer("08")+ reads a
      # leading zero as an octal prefix and raises on a zero-padded number a
      # client is entitled to send. The base is passed only for strings:
      # +Integer+ refuses a base alongside a value that is already numeric.
      #
      # ==== Parameters
      #
      # * +value+ - the raw value as received from the client
      #
      # ==== Returns
      #
      # An +Integer+.
      def integer(value)
        value.is_a?(String) ? Integer(value, 10) : Integer(value)
      end
    end
  end
end
