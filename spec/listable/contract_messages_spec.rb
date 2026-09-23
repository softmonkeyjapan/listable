# frozen_string_literal: true

require "tmpdir"

RSpec.describe Listable::Contract do
  # A contract, built for its messages rather than for its refusals.
  #
  # ==== Returns
  #
  # A contract bound to a small surface.
  def contract
    described_class.new(filterable_fields: %w[id name], sortable_fields: %w[id name])
  end

  # Reads one of the gem's messages the way a host's i18n resolves it.
  #
  # ==== Parameters
  #
  # * +key+ - the message key
  # * +tokens+ - the locale and the interpolations the message takes
  #
  # ==== Returns
  #
  # The message as a client would read it.
  def message(key, **tokens)
    I18n.t("listable.errors.#{key}", **tokens)
  end

  # The locales the gem ships, read off the files it ships.
  #
  # Deriving the list rather than spelling it out is what makes a language
  # added as a file a language this suite checks: a locale file added to the
  # gem and forgotten here would otherwise ship untested.
  #
  # ==== Returns
  #
  # An array of locale symbols.
  def shipped_locales
    described_class::MESSAGE_PATHS.map { |path| File.basename(path, ".yml").to_sym }
  end

  # The gem's load path, handed to a child process that loads it fresh.
  #
  # ==== Returns
  #
  # The absolute path of the gem's +lib+ directory.
  def lib_path
    File.expand_path("../../lib", __dir__)
  end

  # The messages are stored into the i18n backend when a contract is first
  # built, so every example here needs one to have been built.
  before { contract }

  # The harness narrows +I18n.available_locales+ when the translation library
  # is present, and the locales the gem ships are not necessarily the ones the
  # harness declared. The examples widen the list for their own duration rather
  # than leaving the harness's configuration changed behind them.
  around do |example|
    available = I18n.available_locales
    I18n.available_locales = available | shipped_locales
    example.run
  ensure
    I18n.available_locales = available
  end

  describe "the closed vocabulary" do
    it "ships fifteen keys in English, French and Japanese" do
      expect(described_class::MESSAGE_KEYS.size).to eq(15)
      expect(shipped_locales).to contain_exactly(:en, :fr, :ja)
    end

    # A key added to a rule and forgotten in a locale file reaches a host's
    # production as a +translation missing+ string served to its client, which
    # is why the vocabulary is enumerated in the contract and checked here
    # against every file the gem ships rather than against the one locale the
    # suite happens to run in.
    it "resolves every declared key in every shipped locale" do
      missing = shipped_locales.flat_map do |locale|
        described_class::MESSAGE_KEYS
          .reject { |key| I18n.exists?("listable.errors.#{key}", locale) }
          .map { |key| "#{locale}.#{key}" }
      end

      expect(missing).to be_empty
    end

    it "renders every declared key in every shipped locale" do
      rendered = shipped_locales.flat_map do |locale|
        described_class::MESSAGE_KEYS.map do |key|
          message(key, locale: locale, cap: 20, fields: "id, name")
        end
      end

      expect(rendered).to all(be_present)
      expect(rendered.grep(/%\{/)).to be_empty
      expect(rendered.grep(/translation missing/i)).to be_empty
    end

    it "renders the cap and the allowed field list in every shipped locale" do
      shipped_locales.each do |locale|
        expect(message(:too_many, locale: locale, cap: 20)).to include("20")
        expect(message(:field_unknown, locale: locale, fields: "id, name")).to include("id, name")
        expect(message(:sort_unknown, locale: locale, fields: "id, name")).to include("id, name")
      end
    end

    # No default locale is configured on the contract, so a refusal comes back
    # in the locale the request is being served in rather than in one the gem
    # chose for its host.
    it "answers a refusal in the locale the request is served in" do
      answered = shipped_locales.map do |locale|
        I18n.with_locale(locale) { contract.call(sort: "secret").errors.to_h.fetch(:sort).first }
      end
      expected = shipped_locales.map do |locale|
        message(:sort_unknown, locale: locale, fields: "id, name")
      end

      expect(answered).to eq(expected)
    end
  end

  describe "an interpolated message read end to end" do
    # Builds the two interpolating refusals the way a client receives them.
    #
    # The surface is handed to the contract as the array of names a host
    # declares, and the message is read back off the contract's own answer
    # rather than out of +I18n.t+ with a string prepared here. That is the
    # whole point of these examples: the token is given a list, and it is the
    # rendering of that list — +id, name+ and not <tt>["id", "name"]</tt> —
    # that a client reads inside a complete sentence. A test that handed the
    # token an already-joined string would render correctly whatever the
    # contract does and would measure nothing.
    #
    # ==== Parameters
    #
    # * +locale+ - the locale the request is served in
    #
    # ==== Returns
    #
    # A hash of message key to the sentence the client reads.
    def interpolated_refusals(locale)
      I18n.with_locale(locale) do
        errors = contract.call(
          filters: [{ field: "secret", operator: "=", value: "x" }],
          sort: "secret",
        ).errors.to_h

        { field_unknown: errors.dig(:filters, 0).first, sort_unknown: errors.fetch(:sort).first }
      end
    end

    # Builds the refusal a payload past the cap earns, as the client reads it.
    #
    # ==== Parameters
    #
    # * +locale+ - the locale the request is served in
    #
    # ==== Returns
    #
    # The sentence the client reads.
    def cap_refusal(locale)
      payload = Array.new(described_class::MAX_CONDITIONS + 1) do
        { field: "id", operator: "=", value: "1" }
      end

      I18n.with_locale(locale) { contract.call(filters: payload).errors.to_h.fetch(:filters).first }
    end

    it "spells out the English sentences a client reads" do
      expect(interpolated_refusals(:en)).to eq(
        field_unknown: "The field cannot be filtered on. Allowed fields: id, name.",
        sort_unknown: "The listing cannot be sorted on this field. Allowed fields: id, name.",
      )
      expect(cap_refusal(:en)).to eq("Too many filters: 20 at most.")
    end

    # The space before each colon is an ordinary U+0020, spelled as its code
    # point here because the two spaces are indistinguishable on screen: an
    # example that displayed one while asserting the other would read as
    # correct to everyone who checked it.
    #
    # French typography would set a non-breaking space there. These sentences
    # do not, and that is what this example pins. They reproduce the strings a
    # listing API already answers its clients, character for character, and a
    # client reads a response body rather than a typeset page. One character of
    # drift is a visible change to a published contract, so improving the
    # punctuation here is a regression, not a fix.
    it "spells out the French sentences, ordinary spaces included" do
      expect(interpolated_refusals(:fr)).to eq(
        field_unknown: "Le champ ne peut pas être filtré. Champs autorisés\u0020: id, name.",
        sort_unknown: "Le tri ne peut pas porter sur ce champ. Champs autorisés\u0020: id, name.",
      )
      expect(cap_refusal(:fr)).to eq("Trop de filtres\u0020: 20 au maximum.")
    end

    it "spells out the Japanese sentences a client reads" do
      expect(interpolated_refusals(:ja)).to eq(
        field_unknown: "このフィールドでは絞り込めません。使用できるフィールド: id, name。",
        sort_unknown: "このフィールドでは並び替えできません。使用できるフィールド: id, name。",
      )
      expect(cap_refusal(:ja)).to eq("フィルターが多すぎます。最大20件です。")
    end
  end

  describe "the i18n namespace" do
    it "resolves its messages under the gem's own top-level namespace" do
      expect(described_class.config.messages.top_namespace).to eq("listable")
      expect(I18n.exists?("listable.errors.sort_scalar", :en)).to be(true)
    end
  end

  describe "the message backend" do
    # A contract written the way a host writes its own, sharing nothing with
    # the gem's but the library underneath it.
    let(:unrelated_contract) do
      Class.new(Dry::Validation::Contract) { params { optional(:anything) } }
    end

    it "is configured on the contract itself" do
      expect(described_class.config.messages.backend).to be(:i18n)
    end

    # Installing a gem must not change how an application's own contracts
    # resolve their messages, which is what configuring the backend globally
    # would have done.
    it "leaves an unrelated contract's configuration untouched" do
      config = unrelated_contract.config.messages

      expect(config.backend).to be(:yaml)
      expect(config.top_namespace).to eq("dry_validation")
      expect(config.load_paths).not_to include(*described_class::MESSAGE_PATHS)
    end
  end

  describe "a host overriding one message" do
    # The override runs in a child process because it reloads i18n, and a
    # reload is global: performed here it would throw away the translations
    # every other example of this suite reads, and the example that ran next
    # would be measuring the residue of this one.
    #
    # The sequence is the one a Rails boot performs — the gem's messages
    # stored when the contract is first built, the locale files gathered on the
    # load path with the host's own last, and a reload — and it carries both
    # halves of the claim: the gem's messages survive the reload because the
    # railtie put its files on the load path, and the one message the host
    # named wins while the fourteen others stay the gem's.
    it "overrides the message it names and leaves the others standing" do
      Dir.mktmpdir do |directory|
        override = File.join(directory, "host.en.yml")
        File.write(override, <<~YAML)
          en:
            listable:
              errors:
                sort_unknown: "HOST OVERRIDE"
        YAML

        expect(overridden(override)).to eq("HOST OVERRIDE|#{message(:sort_scalar, locale: :en)}")
      end
    end
  end

  # Loads the gem in a child process, overrides one message and reports what
  # two refusals came back as.
  #
  # ==== Parameters
  #
  # * +override+ - the path of the host's own locale file
  #
  # ==== Returns
  #
  # The overridden message and an untouched one, separated by a pipe.
  def overridden(override)
    script = <<~RUBY
      require "listable"

      contract = Listable::Contract.new(filterable_fields: [], sortable_fields: ["id"])

      I18n.load_path.concat(Listable::Contract::MESSAGE_PATHS)
      I18n.load_path << #{override.inspect}
      I18n.reload!

      messages = [
        contract.call(sort: "secret").errors.to_h.fetch(:sort).first,
        contract.call(sort: []).errors.to_h.fetch(:sort).first,
      ]

      print messages.join("|")
    RUBY

    IO.popen([RbConfig.ruby, "-I", lib_path, "-e", script], err: %i[child out], &:read)
  end
end
