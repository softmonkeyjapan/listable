# frozen_string_literal: true

module Listable
  # Turns a field name a client sent into the expression a predicate compares.
  #
  # The resolver is the one place the declared surface is enforced, and the one
  # place a translated attribute stops being a JSON column and becomes the
  # locale extraction its reader would read. Both filtering and sorting go
  # through it, so that an attribute ordered by is the same expression a filter
  # compared against.
  class FieldResolver
    # The PostgreSQL operator that extracts a JSON object's member as text.
    #
    # The text form is the whole point. Its sibling +-&gt;+ yields JSON, and a
    # JSON value compares against a quoted JSON document rather than against
    # the string a client typed — which is how a filter on a translated name
    # comes to match nothing while every test on the relation stays green.
    JSON_TEXT = "->>"

    # The function that folds a fallback chain into one expression.
    COALESCE = "COALESCE"

    # Holds the model the fields are resolved against.
    #
    # ==== Parameters
    #
    # * +model+ - the Active Record class a relation is being narrowed on
    def initialize(model)
      @model = model
    end

    # Resolves a field name to the expression a predicate compares.
    #
    # Both refusals raise rather than return +nil+, and for the same reason:
    # the engine has no way to narrow on the field, and a relation handed back
    # unnarrowed is a listing that answers more rows than the client asked to
    # see while looking exactly like one that filtered. From HTTP neither case
    # occurs — the contract answers 422 on an undeclared field first — so
    # reaching here means an internal caller named something no whitelist
    # carries, and a raise turns that into a red test instead of a leak.
    #
    # ==== Parameters
    #
    # * +field+ - the field name as the client sent it
    #
    # ==== Returns
    #
    # A Field.
    #
    # ==== Raises
    #
    # UnknownField when the model does not declare the field, or declares it
    # and carries neither a translated attribute nor a column of that name.
    def resolve(field)
      unless model.listable_fields.include?(field)
        raise UnknownField, "#{model.name} does not declare #{field.inspect} as listable"
      end

      return translated_field(field) if translated?(field)

      column_field(field)
    end

    private

    # The Active Record class fields are resolved against.
    #
    # ==== Returns
    #
    # The model class.
    attr_reader :model

    # Builds the field of a plain column.
    #
    # ==== Parameters
    #
    # * +field+ - the declared field name
    #
    # ==== Returns
    #
    # A Field carrying the column's Arel attribute.
    #
    # ==== Raises
    #
    # UnknownField when the table carries no column of that name.
    def column_field(field)
      column = model.columns_hash[field]

      raise UnknownField, "#{model.name} carries no column named #{field.inspect}" if column.nil?

      Field.new(
        expression: model.arel_table[field],
        textual: textual?(column),
        cast_type: column.type,
      )
    end

    # Tells whether a column holds text.
    #
    # Textuality is read off the schema through Active Record's type registry,
    # never off a list of column names: a name list drifts from the table the
    # day a column is added, and the drift shows up as a +StatementInvalid+ in
    # production rather than as a failing example. The type looked up is the
    # *column's*, not the attribute's — a string column backed by an enum has
    # an +ActiveRecord::Enum::EnumType+ attribute, and reading that would deny
    # the column the pattern operators it is perfectly able to serve.
    #
    # A type the registry does not carry is treated as non-textual, because a
    # type the gem cannot recognise is a type it cannot promise PostgreSQL will
    # accept a +LIKE+ against.
    #
    # ==== Parameters
    #
    # * +column+ - the Active Record column definition
    #
    # ==== Returns
    #
    # +true+ when the column's type resolves to a string type.
    def textual?(column)
      adapter = ActiveRecord::Type.adapter_name_from(model)

      ActiveRecord::Type.lookup(column.type, adapter: adapter).is_a?(ActiveModel::Type::String)
    rescue ArgumentError
      false
    end

    # Tells whether the model treats the field as a translated attribute.
    #
    # The translation library is an optional dependency: it is in no gemspec,
    # and its presence is established by asking the model whether it answers
    # the library's interface rather than by testing for a constant. An
    # application with no translated attribute installs nothing and takes this
    # branch never.
    #
    # ==== Parameters
    #
    # * +field+ - the declared field name
    #
    # ==== Returns
    #
    # +true+ when the field is a translated attribute of the model.
    def translated?(field)
      model.respond_to?(:mobility_attribute?) && model.mobility_attribute?(field)
    end

    # Builds the field of a translated attribute.
    #
    # The expression is never the column. The column holds a JSON document
    # keyed by locale, so comparing it compares the whole document and matches
    # nothing a client would ever type. A translated attribute is always
    # textual because its extraction yields text by construction, and it
    # carries no cast type because the value a client sends is compared against
    # that text and not against the JSON storage.
    #
    # ==== Parameters
    #
    # * +field+ - the declared translated attribute name
    #
    # ==== Returns
    #
    # A Field carrying the locale extraction.
    def translated_field(field)
      backend = model.mobility_backend_class(field)

      Field.new(expression: extraction(backend, field), textual: true, cast_type: nil)
    end

    # Builds the expression a reader of the attribute would read.
    #
    # The chain is folded into a single +COALESCE+ so that one predicate covers
    # the current locale and its fallbacks — which is what makes a filter agree
    # with the value the client sees. A chain of one locale emits the bare
    # extraction: a +COALESCE+ of a single argument says the same thing in more
    # SQL, and the bare form keeps a plain single-locale application reading
    # the way it is.
    #
    # ==== Parameters
    #
    # * +backend+ - the attribute's backend class
    # * +field+ - the declared translated attribute name
    #
    # ==== Returns
    #
    # An Arel node yielding the attribute's text.
    def extraction(backend, field)
      column = model.arel_table[column_name(backend, field)]
      nodes = fallback_chain(backend).map { |locale| locale_extraction(column, locale) }

      nodes.one? ? nodes.first : Arel::Nodes::NamedFunction.new(COALESCE, nodes)
    end

    # Extracts one locale's value out of the JSON document, as text.
    #
    # ==== Parameters
    #
    # * +column+ - the Arel attribute of the JSON column
    # * +locale+ - the locale to read
    #
    # ==== Returns
    #
    # An Arel node yielding that locale's text.
    def locale_extraction(column, locale)
      Arel::Nodes::InfixOperation.new(JSON_TEXT, column, Arel::Nodes.build_quoted(locale))
    end

    # Reads the locales a reader of the attribute would try, in order.
    #
    # The chain is asked of the backend rather than held in a constant here, so
    # that it follows whatever the host configured — a constant would make the
    # filter disagree with the reader the first time an application changed its
    # fallbacks. A backend with fallbacks switched off answers nothing, and the
    # current locale alone is then the whole chain.
    #
    # ==== Parameters
    #
    # * +backend+ - the attribute's backend class
    #
    # ==== Returns
    #
    # An array of locale names, current locale first.
    def fallback_chain(backend)
      locale = Mobility.locale
      chain = backend.respond_to?(:fallbacks) ? Array(backend.fallbacks[locale]) : []
      chain = [locale] if chain.empty?

      chain.map(&:to_s).uniq
    end

    # Reads the name of the column the attribute is stored in.
    #
    # The backend owns the naming: an application that stores its translations
    # in +name_i18n+ configures a prefix or a suffix on the backend, and asking
    # it keeps the engine right without a second place to configure.
    #
    # ==== Parameters
    #
    # * +backend+ - the attribute's backend class
    # * +field+ - the declared translated attribute name
    #
    # ==== Returns
    #
    # The column name as a string.
    def column_name(backend, field)
      backend.respond_to?(:column_affix) ? format(backend.column_affix, field) : field
    end
  end
end
