# frozen_string_literal: true

begin
  require "mobility"
rescue LoadError
  # The translation library is optional, and the suite is where that claim is
  # measured: it runs once with the library and once with the library left off
  # the load path. The absence is a real one — a bundle group excluded, not a
  # flag the gem could learn to read — so it arrives here as a LoadError, and
  # the run that follows must reach every other example unchanged.
  nil
end

module Listable
  module Harness
    # The translation library, when the run has one.
    #
    # Everything the suite knows about translated attributes goes through this
    # module, so that the two worlds differ in one place instead of in every
    # file that mentions a locale.
    module Translations
      # The locales the suite translates into.
      #
      # +ja+ falls back to +en+ and +en+ falls back to nothing, which gives the
      # suite both shapes the engine has to emit: a chain of several locales
      # folded into a +COALESCE+, and a chain of one emitting a bare
      # extraction.
      LOCALES = %i[en ja].freeze

      # The fallback map handed to the backend.
      FALLBACKS = { ja: :en }.freeze

      module_function

      # Tells whether this run carries the translation library.
      #
      # ==== Returns
      #
      # +true+ when the library is loaded.
      def available?
        defined?(::Mobility).present?
      end

      # Configures the library, when there is one to configure.
      #
      # The configuration is applied before any model calls +translates+,
      # because the backend a model gets is built out of it at declaration
      # time.
      #
      # ==== Returns
      #
      # +nil+.
      def configure!
        return nil unless available?

        I18n.available_locales = LOCALES
        I18n.default_locale = LOCALES.first

        ::Mobility.configure do
          plugins do
            backend :jsonb
            active_record
            reader
            writer
            fallbacks(FALLBACKS)
          end
        end

        nil
      end

      # Runs a block with the suite's translation locale set.
      #
      # ==== Parameters
      #
      # * +locale+ - the locale to read and write translations in
      #
      # ==== Returns
      #
      # Whatever the block returns.
      def with_locale(locale, &)
        ::Mobility.with_locale(locale, &)
      end
    end
  end
end

Listable::Harness::Translations.configure!
