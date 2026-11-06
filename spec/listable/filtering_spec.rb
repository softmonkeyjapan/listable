# frozen_string_literal: true

RSpec.describe Listable, ".filtering" do
  let(:model) { Listable::Harness::Widget }

  before do
    model.create!(
      name: "Spindle", description: "a long spindle", quantity: 3, reference: 10_000_000_001,
      price: "10.50", ratio: 1.5, active: true, released_on: "2026-01-10",
      published_at: "2026-01-10 08:00:00", status: "draft"
    )
    model.create!(
      name: "Gasket", description: "a round gasket", quantity: 7, reference: 10_000_000_002,
      price: "20.25", ratio: 2.5, active: false, released_on: "2026-02-20",
      published_at: "2026-02-20 09:00:00", status: "published"
    )
    model.create!(name: "bolt", quantity: 11, reference: 10_000_000_003, price: "30.00",
                  ratio: 3.5, status: "archived")
  end

  # Enumerates the narrowed relation and reports the rows it answers.
  #
  # Every assertion in this file goes through it on purpose: the relation is
  # lazy, and a predicate PostgreSQL refuses fails where the rows are read and
  # nowhere else. An expectation on the relation itself would pass on exactly
  # the bugs the gem exists to prevent.
  #
  # ==== Parameters
  #
  # * +field+ - the field the condition names
  # * +operator+ - the operator the condition names
  # * +value+ - the value the condition carries
  #
  # ==== Returns
  #
  # The names of the rows the relation answers.
  def names_for(field, operator, value)
    model.filtering([{ field: field, operator: operator, value: value }]).map(&:name)
  end

  describe "the comparison operators" do
    it "selects an exact value" do
      expect(names_for("quantity", "=", "7")).to eq(["Gasket"])
    end

    it "excludes a value" do
      expect(names_for("quantity", "!=", "7")).to contain_exactly("Spindle", "bolt")
    end

    it "reads a strict lower bound" do
      expect(names_for("quantity", ">", "7")).to eq(["bolt"])
    end

    it "reads an inclusive lower bound" do
      expect(names_for("quantity", ">=", "7")).to contain_exactly("Gasket", "bolt")
    end

    it "reads a strict upper bound" do
      expect(names_for("quantity", "<", "7")).to eq(["Spindle"])
    end

    it "reads an inclusive upper bound" do
      expect(names_for("quantity", "<=", "7")).to contain_exactly("Spindle", "Gasket")
    end
  end

  describe "the list operators" do
    it "accepts a real array" do
      expect(names_for("quantity", "in", %w[3 11])).to contain_exactly("Spindle", "bolt")
    end

    it "accepts a comma-separated string and strips each element" do
      expect(names_for("quantity", "in", " 3 , 11 ")).to contain_exactly("Spindle", "bolt")
    end

    it "excludes the members of a comma-separated list" do
      expect(names_for("quantity", "not_in", "3, 11")).to eq(["Gasket"])
    end
  end

  describe "the pattern operators" do
    it "matches a case-sensitive pattern" do
      expect(names_for("name", "like", "%olt%")).to eq(["bolt"])
    end

    it "answers nothing when the case does not match a case-sensitive pattern" do
      expect(names_for("name", "like", "%Olt%")).to eq([])
    end

    it "matches a case-insensitive pattern" do
      expect(names_for("name", "ilike", "%Olt%")).to eq(["bolt"])
    end

    it "matches a pattern against a text column" do
      expect(names_for("description", "ilike", "%ROUND%")).to eq(["Gasket"])
    end

    # An enum is an attribute-level decoration over a column that stays a
    # string. Reading textuality off the attribute would deny this column the
    # pattern operators it is perfectly able to serve.
    it "matches a pattern against the enum-backed string column" do
      expect(names_for("status", "ilike", "%RAF%")).to eq(["Spindle"])
    end

    # The relation is lazy: a LIKE against an integer is refused by PostgreSQL
    # when the rows are read, far downstream of where the predicate was built
    # and outside every rescue. The assertion enumerates for that reason — a
    # test that only built the relation would pass on the bug.
    it "builds no predicate against a non-textual column" do
      expect { names_for("quantity", "like", "%3%") }.not_to raise_error
    end

    it "leaves the relation unnarrowed when the column is non-textual" do
      expect(names_for("quantity", "ilike", "%3%")).to contain_exactly("Spindle", "Gasket", "bolt")
    end
  end

  describe "the null/true/false operator" do
    it "tests for the absence of a value" do
      expect(names_for("released_on", "is", "null")).to eq(["bolt"])
    end

    it "reads its three words whatever their case and padding" do
      expect(names_for("active", "is", "  TRUE  ")).to eq(["Spindle"])
      expect(names_for("active", "is", "False")).to eq(["Gasket"])
      expect(names_for("released_on", "is", " NULL ")).to eq(["bolt"])
    end

    # The value is never cast, so a word outside the three is compared as it
    # arrived rather than dropped for failing to become a number.
    it "falls back to plain equality on any other word" do
      expect(names_for("status", "is", "draft")).to eq(["Spindle"])
    end
  end

  describe "the casts" do
    it "coerces an integer" do
      expect(names_for("quantity", "=", "7")).to eq(["Gasket"])
    end

    it "coerces a wide integer" do
      expect(names_for("reference", "=", "10000000002")).to eq(["Gasket"])
    end

    it "converts a decimal" do
      expect(names_for("price", "=", "20.25")).to eq(["Gasket"])
    end

    it "converts a float" do
      expect(names_for("ratio", "=", "2.5")).to eq(["Gasket"])
    end

    it "reads a boolean through Active Record's boolean type" do
      expect(names_for("active", "=", "false")).to eq(["Gasket"])
    end

    it "parses a date" do
      expect(names_for("released_on", "=", "2026-02-20")).to eq(["Gasket"])
    end

    it "parses a datetime" do
      expect(names_for("published_at", ">=", "2026-02-01")).to eq(["Gasket"])
    end

    it "leaves a string untouched" do
      expect(names_for("name", "=", "Gasket")).to eq(["Gasket"])
    end

    it "leaves the value of a text column untouched" do
      expect(names_for("description", "=", "a round gasket")).to eq(["Gasket"])
    end

    it "leaves a zero-padded number readable" do
      expect(names_for("quantity", "=", "07")).to eq(["Gasket"])
    end
  end

  describe "a cast that cannot succeed" do
    it "drops a condition whose number cannot be read" do
      expect(names_for("quantity", "=", "seven")).to contain_exactly("Spindle", "Gasket", "bolt")
    end

    it "drops a condition whose date cannot be read" do
      expect(names_for("released_on", "<", "not-a-date"))
        .to contain_exactly("Spindle", "Gasket", "bolt")
    end

    it "drops a condition whose time cannot be read" do
      expect(names_for("published_at", ">", "not-a-time"))
        .to contain_exactly("Spindle", "Gasket", "bolt")
    end

    # The relation must stay narrowed by everything else: a client's mistake
    # costs that client its one condition, not the whole request.
    it "leaves the other conditions applied" do
      conditions = [
        { field: "quantity", operator: "=", value: "seven" },
        { field: "name", operator: "=", value: "Gasket" },
      ]

      expect(model.filtering(conditions).map(&:name)).to eq(["Gasket"])
    end
  end

  # Active Record answers an empty result when a select fails to serialise a
  # value, so a raise is not the only symptom to pin: the same defect loses the
  # in-range elements of a list and empties a +!=+ with no error at all. Every
  # example asserts on the rows, and the last group asserts on the SQL, which
  # is where the failure stays loud for +to_sql+, +update_all+ and +delete_all+.
  describe "a value outside the column's range" do
    let(:above) { "99999999999" }
    let(:below) { "-99999999999" }

    before { model.create!(name: "hollow", quantity: nil) }

    describe "the list operators" do
      it "leaves an out-of-range element out of an in" do
        expect(names_for("quantity", "in", "3,#{above}")).to eq(["Spindle"])
      end

      it "leaves an out-of-range integer out of a real array" do
        expect(names_for("quantity", "in", [3, above.to_i])).to eq(["Spindle"])
      end

      it "selects nobody when an in has only out-of-range elements" do
        expect(names_for("quantity", "in", "#{above},#{below}")).to eq([])
      end

      it "leaves an out-of-range element out of a not_in" do
        expect(names_for("quantity", "not_in", "3,#{above}")).to contain_exactly("Gasket", "bolt")
      end

      it "excludes nobody when a not_in has only out-of-range elements" do
        expect(names_for("quantity", "not_in", above))
          .to contain_exactly("Spindle", "Gasket", "bolt", "hollow")
      end

      it "keeps a non-numeric element in the list, where it matches nothing" do
        expect(names_for("quantity", "in", "abc,3")).to eq(["Spindle"])
      end
    end

    describe "the equality operators" do
      it "selects nobody on =" do
        expect(names_for("quantity", "=", above)).to eq([])
      end

      it "excludes nobody on !=" do
        expect(names_for("quantity", "!=", above))
          .to contain_exactly("Spindle", "Gasket", "bolt", "hollow")
      end

      it "selects nobody on is" do
        expect(names_for("quantity", "is", above)).to eq([])
      end

      it "still reads null on is" do
        expect(names_for("quantity", "is", "null")).to eq(["hollow"])
      end
    end

    # A NULL row holds no value to compare: the column's bound would not select
    # it, so neither does a comparison every held value satisfies.
    describe "the order comparisons" do
      it "selects nobody above a value over the bound" do
        expect(names_for("quantity", ">", above)).to eq([])
        expect(names_for("quantity", ">=", above)).to eq([])
      end

      it "selects every held value below a value over the bound" do
        expect(names_for("quantity", "<", above)).to contain_exactly("Spindle", "Gasket", "bolt")
        expect(names_for("quantity", "<=", above)).to contain_exactly("Spindle", "Gasket", "bolt")
      end

      it "selects every held value above a value under the bound" do
        expect(names_for("quantity", ">", below)).to contain_exactly("Spindle", "Gasket", "bolt")
        expect(names_for("quantity", ">=", below)).to contain_exactly("Spindle", "Gasket", "bolt")
      end

      it "selects nobody below a value under the bound" do
        expect(names_for("quantity", "<", below)).to eq([])
        expect(names_for("quantity", "<=", below)).to eq([])
      end
    end

    describe "the edges of the range" do
      before do
        model.create!(name: "top", quantity: 2_147_483_647)
        model.create!(name: "floor", quantity: -2_147_483_648)
      end

      it "matches the highest value the column holds" do
        expect(names_for("quantity", "=", "2147483647")).to eq(["top"])
      end

      it "matches the lowest value the column holds" do
        expect(names_for("quantity", "in", "-2147483648")).to eq(["floor"])
      end

      it "reads the first value past the highest as out of range" do
        expect(names_for("quantity", "=", "2147483648")).to eq([])
        expect(names_for("quantity", "<", "2147483648")).to include("top", "floor")
      end

      it "reads the first value past the lowest as out of range" do
        expect(names_for("quantity", "=", "-2147483649")).to eq([])
        expect(names_for("quantity", ">", "-2147483649")).to include("top", "floor")
      end
    end

    describe "a bigint column" do
      it "accepts a value above the range of a 4-byte column" do
        expect(names_for("reference", "in", "10000000001,99999999999")).to eq(["Spindle"])
        expect(names_for("reference", "=", "10000000002")).to eq(["Gasket"])
      end

      it "reads its own range rather than a constant" do
        beyond = (2**63).to_s

        expect(names_for("reference", "in", "10000000001,#{beyond}")).to eq(["Spindle"])
        expect(names_for("reference", "=", beyond)).to eq([])
        expect(names_for("reference", "<", beyond)).to contain_exactly("Spindle", "Gasket", "bolt")
      end
    end

    it "leaves the other conditions applied" do
      conditions = [
        { field: "quantity", operator: "!=", value: above },
        { field: "name", operator: "=", value: "Gasket" },
      ]

      expect(model.filtering(conditions).map(&:name)).to eq(["Gasket"])
    end

    describe "the SQL it builds" do
      %w[= != > >= < <= is in not_in].each do |operator|
        it "serialises #{operator} without raising" do
          conditions = [{ field: "quantity", operator: operator, value: above }]

          expect { model.filtering(conditions).to_sql }.not_to raise_error
        end
      end

      it "updates through the narrowed relation without raising" do
        conditions = [{ field: "quantity", operator: "in", value: "3,#{above}" }]

        expect(model.filtering(conditions).update_all(name: "renamed")).to eq(1)
      end
    end
  end

  describe "combining conditions" do
    it "combines them with AND" do
      conditions = [
        { field: "quantity", operator: ">=", value: "3" },
        { field: "active", operator: "is", value: "true" },
      ]

      expect(model.filtering(conditions).map(&:name)).to eq(["Spindle"])
    end

    it "lets two conditions on the same field both narrow" do
      conditions = [
        { field: "quantity", operator: ">=", value: "3" },
        { field: "quantity", operator: "<=", value: "7" },
      ]

      expect(model.filtering(conditions).map(&:name)).to contain_exactly("Spindle", "Gasket")
    end

    it "narrows on top of the scope it is chained onto" do
      relation = model.where(status: "archived")
      conditions = [{ field: "quantity", operator: ">=", value: "3" }]

      expect(relation.filtering(conditions).map(&:name)).to eq(["bolt"])
    end

    it "reads string keys as readily as symbol keys" do
      conditions = [{ "field" => "quantity", "operator" => "=", "value" => "7" }]

      expect(model.filtering(conditions).map(&:name)).to eq(["Gasket"])
    end
  end

  describe "a condition the vocabulary does not define" do
    it "drops a condition naming a blank field" do
      expect(names_for("", "=", "7")).to contain_exactly("Spindle", "Gasket", "bolt")
    end

    it "drops a condition naming a blank operator" do
      expect(names_for("quantity", "", "7")).to contain_exactly("Spindle", "Gasket", "bolt")
    end

    it "drops a condition naming an operator outside the vocabulary" do
      expect(names_for("quantity", "~", "7")).to contain_exactly("Spindle", "Gasket", "bolt")
    end

    # Normalising the payload belongs to the caller. A padded operator that
    # reached the engine is a normalisation that did not happen, and repairing
    # it here would hide that.
    it "drops a condition whose operator arrived padded" do
      expect(names_for("quantity", " = ", "7")).to contain_exactly("Spindle", "Gasket", "bolt")
    end

    it "drops a condition that is not an object" do
      expect(model.filtering(["quantity"]).map(&:name))
        .to contain_exactly("Spindle", "Gasket", "bolt")
    end

    it "answers the whole relation when there is no condition at all" do
      expect(model.filtering(nil).map(&:name)).to contain_exactly("Spindle", "Gasket", "bolt")
    end
  end

  describe "the declared surface" do
    it "refuses every field of a model that declares nothing" do
      conditions = [{ field: "name", operator: "=", value: "Spindle" }]

      expect { Listable::Harness::SealedWidget.filtering(conditions) }
        .to raise_error(Listable::UnknownField, /does not declare/)
    end

    it "raises on a field the model does not declare" do
      conditions = [{ field: "secret", operator: "=", value: "1" }]

      expect { model.filtering(conditions) }
        .to raise_error(Listable::UnknownField, /does not declare/)
    end

    # A surface may name something the table does not carry — a listing serves
    # such a field through a custom filter. Reaching the column resolution with
    # it means no filter claimed it, and handing the relation back unnarrowed
    # would answer every row to a client who believes it filtered.
    it "refuses a declared field the table carries no column for" do
      conditions = [{ field: "owner", operator: "=", value: "Ada" }]

      expect { Listable::Harness::ComputedWidget.filtering(conditions) }
        .to raise_error(Listable::UnknownField, /no column/)
    end

    it "narrows a subclass on a field only its parent declared" do
      conditions = [{ field: "quantity", operator: "=", value: "7" }]

      expect(Listable::Harness::SpecialWidget.filtering(conditions).map(&:name)).to eq(["Gasket"])
    end

    it "narrows on a field a computed surface names" do
      conditions = [{ field: "name", operator: "=", value: "Gasket" }]

      expect(Listable::Harness::ComputedWidget.filtering(conditions).map(&:name)).to eq(["Gasket"])
    end
  end
end
