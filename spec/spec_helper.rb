# frozen_string_literal: true

require "listable"

require_relative "support/database"
require_relative "support/schema"
require_relative "support/translations"
require_relative "support/models"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # The schema is thrown away and rebuilt once per run: the suite owns its
  # database, so a run must never depend on what the previous one left behind.
  config.before(:suite) do
    Listable::Harness::Database.connect!
    Listable::Harness::Schema.load!
  end

  # The translated-attribute examples are the one part of the suite that needs
  # a dependency the gem does not declare. They are skipped rather than
  # deleted when the library is absent, so that the run without it exercises
  # every other example instead of a shortened suite that could stay green
  # while the gem quietly stopped working without translations.
  config.before(:each, :translated) do
    skip("the translation library is not loaded") unless Listable::Harness::Translations.available?
  end

  # Each example runs inside a transaction that is rolled back afterwards.
  # Records are created with plain Active Record calls, so nothing else would
  # undo them, and a test asserting on which rows come back cannot afford to
  # see the rows of the example that ran before it.
  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run

      raise ActiveRecord::Rollback
    end
  end
end
