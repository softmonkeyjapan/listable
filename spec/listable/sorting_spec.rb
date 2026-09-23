# frozen_string_literal: true

RSpec.describe Listable, ".sorting" do
  let(:model) { Listable::Harness::Widget }

  # Reports the ids of the rows a sort answers, in the order they come back.
  #
  # Every example asserts on rows rather than on the relation: an order that
  # only looks right in the query it builds is the exact failure this engine
  # exists to prevent, and it shows up nowhere but in the rows PostgreSQL
  # actually hands back.
  #
  # ==== Parameters
  #
  # * +sort+ - the sort parameter as a client would send it
  #
  # ==== Returns
  #
  # The ids of the rows the relation answers, in order.
  def ids_for(sort)
    model.sorting(sort).map(&:id)
  end

  # The same include carries filtering and sorting, so a host never has to
  # remember which of two modules brought which half of the behaviour.
  it "is carried by the include that carries filtering" do
    expect(model).to respond_to(:filtering, :sorting)
  end

  describe "the default order" do
    it "reads the creation timestamp descending" do
      oldest = model.create!(created_at: Time.utc(2026, 1, 1))
      newest = model.create!(created_at: Time.utc(2026, 3, 1))
      middle = model.create!(created_at: Time.utc(2026, 2, 1))

      expect(ids_for(nil)).to eq([newest.id, middle.id, oldest.id])
    end

    # Rows created in the same request share a timestamp to the microsecond,
    # and without the primary key behind it the default order would leave them
    # for the query plan to arrange.
    it "breaks equal creation timestamps on the primary key descending" do
      stamp = Time.utc(2026, 1, 1)
      first = model.create!(created_at: stamp)
      second = model.create!(created_at: stamp)
      third = model.create!(created_at: stamp)

      expect(ids_for(nil)).to eq([third.id, second.id, first.id])
    end

    # The gem carries the ordering of its consumers' listings, not a timestamp
    # convention they must adopt to be ordered at all. The table behind this
    # example genuinely has no creation timestamp.
    it "falls back to the primary key alone on a table with no creation timestamp" do
      gadgets = Array.new(3) { |position| Listable::Harness::Gadget.create!(position: position) }

      expect(Listable::Harness::Gadget.sorting(nil).map(&:id)).to eq(gadgets.map(&:id).reverse)
    end

    # A sort that names no key at all leaves the default order standing rather
    # than answering an unordered listing: a separator and a bare descending
    # marker name nothing, and there is no key in them to refuse.
    [nil, "", "   ", ",", ",,", " , , ", "-", "- ", "-,-", " - , - "].each do |sort|
      it "stands when the sort names nothing, as in #{sort.inspect}" do
        stamp = Time.utc(2026, 1, 1)
        first = model.create!(created_at: stamp)
        second = model.create!(created_at: stamp)

        expect(ids_for(sort)).to eq([second.id, first.id])
      end
    end
  end

  describe "the keys a client sends" do
    it "orders ascending on a single key" do
      gamma = model.create!(name: "gamma")
      alpha = model.create!(name: "alpha")
      beta = model.create!(name: "beta")

      expect(ids_for("name")).to eq([alpha.id, beta.id, gamma.id])
    end

    it "orders descending on a key carrying the descending marker" do
      gamma = model.create!(name: "gamma")
      alpha = model.create!(name: "alpha")
      beta = model.create!(name: "beta")

      expect(ids_for("-name")).to eq([gamma.id, beta.id, alpha.id])
    end

    # The keys break each other's ties the way the client arranged them, so the
    # two arrangements of the same two keys answer two different listings.
    it "applies several keys in the order they were sent" do
      draft_two = model.create!(status: "draft", quantity: 2)
      draft_one = model.create!(status: "draft", quantity: 1)
      archived = model.create!(status: "archived", quantity: 3)

      expect(ids_for("status,quantity")).to eq([archived.id, draft_one.id, draft_two.id])
      expect(ids_for("quantity,status")).to eq([draft_one.id, draft_two.id, archived.id])
    end

    it "reads a term with the whitespace around it" do
      draft_two = model.create!(status: "draft", quantity: 2)
      draft_one = model.create!(status: "draft", quantity: 1)
      archived = model.create!(status: "archived", quantity: 3)

      expect(ids_for(" -status , quantity ")).to eq([draft_one.id, draft_two.id, archived.id])
    end

    # A client that named a key means that key to decide the listing. Were the
    # default order kept in front of it, the newest row would come first and
    # the key the client sent would only break its ties.
    it "replaces the default order rather than appending to it" do
      newest = model.create!(name: "zulu", created_at: Time.utc(2026, 3, 1))
      oldest = model.create!(name: "alpha", created_at: Time.utc(2026, 1, 1))

      expect(ids_for("name")).to eq([oldest.id, newest.id])
    end
  end

  describe "the primary key appended behind the client's keys" do
    it "decides the rows the client's keys leave tied" do
      first = model.create!(name: "same")
      second = model.create!(name: "same")
      third = model.create!(name: "same")

      expect(ids_for("name")).to eq([third.id, second.id, first.id])
    end

    # The one claim in this file that no set of rows can carry: appending the
    # primary key to an order that already reads it answers exactly the rows
    # the order without it answers. What is asserted is therefore that the
    # engine built one ordering and not two — the noise it would be is
    # measurable nowhere else.
    it "is not appended again when the client already ordered on it" do
      first = model.create!
      second = model.create!

      expect(model.sorting("id").order_values.length).to eq(1)
      expect(ids_for("id")).to eq([first.id, second.id])
    end
  end

  describe "a key no whitelist carries" do
    it "raises the unknown-key error" do
      expect { model.sorting("secret") }.to raise_error(Listable::UnknownKey, /secret/)
    end

    # A model that declares nothing sorts on nothing. Answering the listing
    # unordered instead would serve a client who believes it sorted.
    it "raises on a model that declares nothing" do
      expect { Listable::Harness::SealedWidget.sorting("name") }
        .to raise_error(Listable::UnknownKey)
    end

    # A declared name the table carries no column for is a field a listing
    # serves through a custom filter. There is no such thing for an order, so
    # the engine refuses rather than dropping the key.
    it "raises on a declared name that is no column" do
      expect { Listable::Harness::ComputedWidget.sorting("owner") }
        .to raise_error(Listable::UnknownKey)
    end

    # The two surfaces are different — a listing may accept a filter on a field
    # it cannot order by — so a caller rescuing one of the two refusals must
    # not catch the other by inheritance.
    it "is an error distinct from the one an undeclared filter field raises" do
      expect(Listable::UnknownKey.ancestors).not_to include(Listable::UnknownField)
    end
  end

  describe "paging through a listing ordered on a low-cardinality key" do
    # The proof that the appended primary key is not decoration. Every row
    # here shares the sort value, so the order the client asked for decides
    # nothing at all, and PostgreSQL arranges the tied rows however the plan it
    # chose emits them — the plan of the first page not being the plan of the
    # second. Delete the tie-breaker and this example goes red: one row is
    # served twice and another is never served.
    it "neither repeats nor skips a row between two consecutive pages" do
      100.times { model.create!(status: "draft") }
      size = 10

      first = model.sorting("status").limit(size).offset(0).map(&:id)
      second = model.sorting("status").limit(size).offset(size).map(&:id)

      expect(first & second).to be_empty
      expect((first + second).uniq.length).to eq(2 * size)
      expect(first + second).to eq(model.sorting("status").limit(2 * size).map(&:id))
    end
  end
end
