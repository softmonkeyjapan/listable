# frozen_string_literal: true

RSpec.describe Listable do
  # Everything below is read out of README.md and run against the harness. The
  # group is named for the document rather than for a method because the claim
  # under test belongs to the document: the examples a consumer copies are the
  # ones that execute here.
  describe "the README" do
    # The model the README's examples are written against.
    #
    # Its declared surface carries every field the document names, which is what
    # lets an example be run exactly as it is printed rather than translated into
    # the suite's vocabulary first.
    let(:model) { Listable::Harness::Widget }

    # Three rows arranged so that every example in the README discriminates.
    #
    # An example that matched all three would pass the assertions below while
    # saying nothing: a condition the engine silently dropped answers the whole
    # listing, and that is the exact failure — a listing wider than the client
    # asked for that looks like a filtered one — the examples have to rule out.
    before do
      model.create!(name: "Spindle", quantity: 3, price: "10.50", status: "published",
                    published_at: Time.utc(2026, 1, 15, 8), created_at: Time.utc(2026, 1, 15))
      model.create!(name: "Gasket", quantity: 7, price: "20.25", status: "draft",
                    published_at: Time.utc(2026, 2, 10, 9), created_at: Time.utc(2026, 2, 10))
      model.create!(name: "bolt", quantity: 11, price: "30.00", status: "archived",
                    created_at: Time.utc(2026, 3, 5))
    end

    # Parses a query string the way a web server hands it to a controller.
    #
    # ==== Parameters
    #
    # * +query+ - a query string read out of the README
    #
    # ==== Returns
    #
    # The parameters as a nested hash with string keys.
    def params_for(query)
      Rack::Utils.parse_nested_query(query)
    end

    # Validates a set of parameters against the model's declared surface.
    #
    # ==== Parameters
    #
    # * +params+ - the parameters an example parsed into
    #
    # ==== Returns
    #
    # The errors as a hash, empty when the example is a request the contract
    # would let through.
    def refusals(params)
      Listable::Contract.new(
        filterable_fields: model.listable_fields,
        sortable_fields: model.listable_fields,
      ).call(params).errors.to_h
    end

    # Normalises the filters an example carries.
    #
    # ==== Parameters
    #
    # * +params+ - the parameters an example parsed into
    #
    # ==== Returns
    #
    # The positional list of conditions the engine reads.
    def conditions_for(params)
      Listable::Conditions.new(params["filters"]).to_a
    end

    # Runs an example against the harness and reads the rows back.
    #
    # The relation is materialised here rather than returned lazily, because a
    # predicate PostgreSQL refuses fails where the rows are read and nowhere
    # else: an assertion on the relation would pass on an example that answers a
    # 500 to the first client who copies it.
    #
    # ==== Parameters
    #
    # * +params+ - the parameters an example parsed into
    #
    # ==== Returns
    #
    # The rows the example answers, in the order they come back.
    def rows_for(params)
      relation = model.all
      relation = relation.filtering(conditions_for(params)) if params.key?("filters")
      relation = relation.sorting(params["sort"]) if params.key?("sort")

      relation.to_a
    end

    # Tells whether rows came back in the order a sort parameter asks for.
    #
    # The expectation is computed from the sort string the README printed rather
    # than from a list of ids written here, so the check follows the document
    # instead of pinning it.
    #
    # ==== Parameters
    #
    # * +rows+ - the rows the example answered, in order
    # * +sort+ - the sort parameter the example carried
    #
    # ==== Returns
    #
    # +true+ when every consecutive pair is in the order the keys name.
    def ordered?(rows, sort)
      terms = terms_of(sort)

      rows.each_cons(2).all? { |former, latter| in_order?(former, latter, terms) }
    end

    # Reads the keys a sort parameter names, with the direction each asks for.
    #
    # ==== Parameters
    #
    # * +sort+ - the sort parameter the example carried
    #
    # ==== Returns
    #
    # An array of <tt>[key, descending]</tt> pairs.
    def terms_of(sort)
      sort.split(",").map(&:strip).reject(&:empty?).map do |term|
        [term.delete_prefix("-").strip, term.start_with?("-")]
      end
    end

    # Tells whether two consecutive rows are in the order the keys name.
    #
    # The fall-through is the tie-breaker the gem appends: two rows equal on
    # every key the client sent must still come back primary key descending, or
    # a paginated listing repeats one of them and skips the other.
    #
    # ==== Parameters
    #
    # * +former+ - the row that came back first
    # * +latter+ - the row that came back next
    # * +terms+ - the <tt>[key, descending]</tt> pairs the sort named
    #
    # ==== Returns
    #
    # +true+ when the pair is ordered as asked.
    def in_order?(former, latter, terms)
      terms.each do |key, descending|
        first = former.public_send(key)
        second = latter.public_send(key)
        next if first == second

        return descending ? first > second : first < second
      end

      former.id > latter.id
    end

    Listable::Harness::Readme.query_strings.each do |query|
      describe "the example #{query.inspect}" do
        let(:params) { params_for(query) }

        it "is a request the contract lets through" do
          expect(refusals(params)).to be_empty
        end

        if query.include?("filters[")
          it "carries every condition through normalisation" do
            expect(conditions_for(params).size).to eq(params.fetch("filters").size)
          end

          # A dropped condition and a satisfied one are told apart here and
          # nowhere else: both answer rows, and only the strict subset proves the
          # predicate reached the database.
          it "narrows the listing to a strict, non-empty subset" do
            rows = rows_for(params)

            expect(rows).not_to be_empty
            expect(rows.size).to be < model.count
          end
        end

        if query.include?("sort=")
          it "answers the rows in the order it names" do
            expect(ordered?(rows_for(params), params.fetch("sort"))).to be(true)
          end
        end
      end
    end

    describe "the operator table" do
      # The table is what a host documents its own API from, so a vocabulary it
      # under-reports is a client told an operator does not exist, and one it
      # over-reports is a client whose condition the engine drops in silence.
      it "lists the vocabulary, whole and in order" do
        expect(Listable::Harness::Readme.operators).to eq(Listable::OPERATORS)
      end
    end

    describe "the installation snippet" do
      # The gem is installed from git by tag and never from a registry, so the
      # snippet is the version a consumer ends up running.
      it "pins the version the gem carries" do
        expect(Listable::Harness::Readme.install_tag).to eq("v#{Listable::VERSION}")
      end
    end
  end
end
