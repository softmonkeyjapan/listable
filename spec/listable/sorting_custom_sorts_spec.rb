# frozen_string_literal: true

RSpec.describe Listable, ".sorting" do
  let(:model) { Listable::Harness::Widget }

  # The custom sort the feature exists for: each widget ordered by its earliest
  # occurrence, an aggregate over an associated table that no declared column
  # can express. +NULLS LAST+ holds in both directions, so a widget with no
  # occurrence at all closes the listing whichever way the client asked —
  # PostgreSQL's own default would put it first in descending order.
  #
  # ==== Returns
  #
  # A class answering +ordering+.
  def next_occurrence
    Class.new do
      # Builds the ordering on the earliest occurrence of each row.
      #
      # ==== Parameters
      #
      # * +relation+ - the relation being ordered
      # * +descending+ - whether the client asked for descending order
      #
      # ==== Returns
      #
      # An Arel ordering node.
      def self.ordering(relation, descending)
        occurrences = Listable::Harness::Occurrence.arel_table
        earliest = occurrences
                   .project(occurrences[:start_at].minimum)
                   .where(occurrences[:widget_id].eq(relation.arel_table[:id]))
        expression = Arel::Nodes::Grouping.new(earliest.ast)

        (descending ? expression.desc : expression.asc).nulls_last
      end
    end
  end

  # A sort that orders on a column other than the key it claims.
  #
  # The mismatch is the assertion, as it is for custom filters: a sort that
  # reproduced what the column of the same name would have done could not tell
  # the two apart.
  #
  # ==== Returns
  #
  # A class answering +ordering+.
  def by_quantity
    Class.new do
      # Orders the relation on its quantity, whatever key claimed this sort.
      #
      # ==== Parameters
      #
      # * +relation+ - the relation being ordered
      # * +descending+ - whether the client asked for descending order
      #
      # ==== Returns
      #
      # An Arel ordering node.
      def self.ordering(relation, descending)
        quantity = relation.arel_table[:quantity]

        descending ? quantity.desc : quantity.asc
      end
    end
  end

  # A sort that fails the way a host's own code would.
  #
  # ==== Returns
  #
  # A class answering +ordering+.
  def broken
    Class.new do
      # Fails, so that the absence of a rescue around a custom sort shows.
      #
      # ==== Parameters
      #
      # * +_relation+ - the relation being ordered
      # * +_descending+ - whether the client asked for descending order
      #
      # ==== Returns
      #
      # Nothing: it always raises.
      def self.ordering(_relation, _descending)
        raise "the host's sort failed"
      end
    end
  end

  # Creates a widget and the occurrences it starts at.
  #
  # ==== Parameters
  #
  # * +name+ - the widget's name
  # * +starts+ - the start times of its occurrences, possibly none
  #
  # ==== Returns
  #
  # The widget.
  def widget_starting(name, *starts)
    model.create!(name: name).tap do |widget|
      starts.each { |start| Listable::Harness::Occurrence.create!(widget_id: widget.id, start_at: start) }
    end
  end

  # Reports the ids of the rows a sort answers, in the order they come back.
  #
  # ==== Parameters
  #
  # * +sort+ - the sort parameter as a client would send it
  # * +custom_sorts+ - the custom sorts the host registered
  #
  # ==== Returns
  #
  # The ids of the rows the relation answers, in order.
  def ids_for(sort, custom_sorts)
    model.sorting(sort, custom_sorts).map(&:id)
  end

  describe "a custom sort over an aggregate subquery" do
    let(:sorts) { { "next_occurrence.start_at" => next_occurrence } }
    let!(:later) { widget_starting("later", Time.utc(2026, 5, 1), Time.utc(2026, 3, 1)) }
    let!(:sooner) { widget_starting("sooner", Time.utc(2026, 2, 1)) }
    let!(:never) { widget_starting("never") }

    it "orders ascending with the rows it has no value for last" do
      expect(ids_for("next_occurrence.start_at", sorts)).to eq([sooner.id, later.id, never.id])
    end

    # PostgreSQL puts +NULL+ first in a descending order unless told otherwise,
    # so this is the example that proves the sort, and not the gem, owns the
    # ordering node.
    it "orders descending with the rows it has no value for still last" do
      expect(ids_for("-next_occurrence.start_at", sorts)).to eq([later.id, sooner.id, never.id])
    end
  end

  describe "a custom sort among the client's other keys" do
    let(:sorts) { { "next_occurrence.start_at" => next_occurrence } }
    let!(:beta) { widget_starting("beta", Time.utc(2026, 4, 1)) }
    let!(:early_alpha) { widget_starting("alpha", Time.utc(2026, 2, 1)) }
    let!(:late_alpha) { widget_starting("alpha", Time.utc(2026, 3, 1)) }

    # The two arrangements of the same two keys answer two different listings,
    # which is what proves the custom term kept the position the client gave it.
    it "keeps the position the client gave it" do
      expect(ids_for("name,-next_occurrence.start_at", sorts))
        .to eq([late_alpha.id, early_alpha.id, beta.id])
      expect(ids_for("-next_occurrence.start_at,name", sorts))
        .to eq([beta.id, late_alpha.id, early_alpha.id])
    end
  end

  describe "the primary key appended behind a custom sort" do
    let(:sorts) { { "next_occurrence.start_at" => next_occurrence } }

    it "decides the rows the custom sort leaves tied" do
      first = widget_starting("first", Time.utc(2026, 2, 1))
      second = widget_starting("second", Time.utc(2026, 2, 1))
      third = widget_starting("third", Time.utc(2026, 2, 1))

      expect(ids_for("next_occurrence.start_at", sorts)).to eq([third.id, second.id, first.id])
      expect(model.sorting("next_occurrence.start_at", sorts).order_values.last.to_sql)
        .to eq(model.arel_table[:id].desc.to_sql)
    end

    # The tie-breaker is skipped only when the order already reads the primary
    # key. A custom sort claiming the key +id+ orders on whatever it chose, so
    # the primary key still has to close the ordering behind it.
    it "is still appended when a custom sort claims the primary key's name" do
      orderings = model.sorting("id", "id" => by_quantity).order_values

      expect(orderings.map(&:to_sql))
        .to eq([model.arel_table[:quantity].asc.to_sql, model.arel_table[:id].desc.to_sql])
    end
  end

  describe "the lookup" do
    # A sort that records what it was handed and orders on the quantity.
    let(:recorder) do
      Class.new do
        # The calls this sort has received, oldest first.
        #
        # ==== Returns
        #
        # An array of relation and direction pairs.
        def self.calls
          @calls ||= []
        end

        # Records the call and orders on the quantity ascending.
        #
        # ==== Parameters
        #
        # * +relation+ - the relation being ordered
        # * +descending+ - whether the client asked for descending order
        #
        # ==== Returns
        #
        # An Arel ordering node.
        def self.ordering(relation, descending)
          calls << [relation, descending]
          relation.arel_table[:quantity].asc
        end
      end
    end

    let!(:few) { model.create!(name: "zulu", quantity: 3) }
    let!(:many) { model.create!(name: "alpha", quantity: 7) }

    # The lookup runs before the key is treated as a column, so a sort takes
    # the key even when a column of that name exists and would have answered.
    it "claims a key ahead of the column of the same name" do
      expect(ids_for("name", "name" => by_quantity)).to eq([few.id, many.id])
    end

    # The same lookup runs before the declared surface is consulted, the way a
    # custom filter's does: registering the sort is what makes the key known to
    # the engine, and the contract's sortable surface is what lets a client name
    # it at all.
    it "claims a key the model does not declare" do
      expect(ids_for("-owner", "owner" => by_quantity)).to eq([many.id, few.id])
    end

    it "is found under a symbol key as readily as under a string one" do
      expect(ids_for("owner", owner: by_quantity)).to eq([few.id, many.id])
    end

    it "receives the relation and whether the client asked for descending order" do
      model.sorting("-owner", "owner" => recorder).to_a

      expect(recorder.calls.length).to eq(1)
      expect(recorder.calls.first[0]).to be_a(ActiveRecord::Relation)
      expect(recorder.calls.first[1]).to be(true)
    end

    # The gem wraps no rescue around a custom sort, for the reason it wraps
    # none around a custom filter: swallowing an error raised inside the host's
    # code would answer a listing ordered by something nobody asked for.
    it "lets an error raised inside it propagate" do
      expect { model.sorting("name", "name" => broken) }
        .to raise_error(RuntimeError, "the host's sort failed")
    end
  end

  describe "a dotted key no custom sort carries" do
    # A dot is no syntax of its own: a dotted key that nobody registered is an
    # undeclared key like any other, and it fails closed exactly as one.
    it "raises the unknown-key error" do
      expect { model.sorting("next_occurrence.start_at") }
        .to raise_error(Listable::UnknownKey, /next_occurrence\.start_at/)
    end

    it "raises even when other custom sorts are registered" do
      expect { model.sorting("-next_occurrence.start_at", "owner" => by_quantity) }
        .to raise_error(Listable::UnknownKey, /next_occurrence\.start_at/)
    end
  end
end
