# frozen_string_literal: true

module Listable
  # Everything the suite needs to exercise the gem against a real database.
  #
  # The harness replaces an example application: there is no dummy Rails app to
  # boot, no generated schema and no factory library. It is nested under
  # +Listable+ for the same reason the gem itself is — the suite must not be
  # able to teach anyone that a root-level constant is acceptable here.
  module Harness
    # Opens the suite's connection to PostgreSQL.
    #
    # The settings come from the environment so that continuous integration can
    # point the suite at its own service container, and they default to a local
    # PostgreSQL with a trusted +postgres+ role so that a fresh checkout runs
    # green with no setup step to read about first.
    module Database
      # The database every PostgreSQL cluster carries. The suite connects to it
      # only to find out whether its own database exists yet.
      MAINTENANCE_DATABASE = "postgres"

      module_function

      # Makes the suite's database exist and connects Active Record to it.
      #
      # ==== Returns
      #
      # The connection pool Active Record established.
      def connect!
        create_database_unless_exists!

        ActiveRecord::Base.establish_connection(configuration)
      end

      # Builds the connection settings for the suite's database.
      #
      # Every value is overridable through the environment, and every default
      # describes a stock local PostgreSQL. A missing password is passed as
      # +nil+ rather than as an empty string, which the adapter would send as an
      # actual empty password and a +trust+ role would then refuse.
      #
      # ==== Returns
      #
      # A connection configuration hash.
      def configuration
        {
          adapter: "postgresql",
          encoding: "unicode",
          host: ENV.fetch("LISTABLE_DATABASE_HOST", "localhost"),
          port: Integer(ENV.fetch("LISTABLE_DATABASE_PORT", "5432")),
          username: ENV.fetch("LISTABLE_DATABASE_USERNAME", "postgres"),
          password: ENV.fetch("LISTABLE_DATABASE_PASSWORD", nil),
          database: ENV.fetch("LISTABLE_DATABASE_NAME", "listable_test"),
        }
      end

      # Creates the suite's database when the cluster does not carry it yet.
      #
      # The suite owns its database entirely — the schema is thrown away and
      # rebuilt on every run — so a first run must not fail on a connection
      # error the reader has to diagnose. The check runs from the maintenance
      # database because +CREATE DATABASE+ cannot run from the database it
      # creates, and the pool is disconnected afterwards so the suite does not
      # keep a second connection open for the rest of the run.
      #
      # ==== Returns
      #
      # +nil+.
      def create_database_unless_exists!
        name = configuration.fetch(:database)

        ActiveRecord::Base.establish_connection(configuration.merge(database: MAINTENANCE_DATABASE))
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          next if database_exists?(connection, name)

          connection.create_database(name, encoding: "unicode")
        end

        ActiveRecord::Base.connection_pool.disconnect!
        nil
      end

      # Tells whether the cluster already carries a database of that name.
      #
      # ==== Parameters
      #
      # * +connection+ - a connection to the maintenance database
      # * +name+ - the database name to look for
      #
      # ==== Returns
      #
      # +true+ when the database exists, +false+ otherwise.
      def database_exists?(connection, name)
        query = "SELECT 1 FROM pg_database WHERE datname = #{connection.quote(name)}"

        connection.select_value(query).present?
      end
    end
  end
end
