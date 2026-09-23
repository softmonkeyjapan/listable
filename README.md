# Listable

Listable carries the query engine of a JSON API listing endpoint: the filter vocabulary, the
sort vocabulary, the whitelist that guards both, and the validation contract that turns a bad
query string into a 422 naming what to fix.

It is not a listing framework. It does not paginate, does not render, does not touch
controllers and never sees an HTTP request. It answers one question — what rows come back, in
what order — and it answers it entirely.

## PostgreSQL only

Listable targets PostgreSQL and nothing else. Its operators, its casts and its expressions are
written against PostgreSQL semantics:

- `ilike` is PostgreSQL's `ILIKE`. No other engine spells case-insensitive matching that way.
- Translated attributes are read through the `->>` JSON text extraction operator.
- The sort tie-breaker exists because PostgreSQL guarantees no row order without a total
  `ORDER BY`.

There is no branch, no shim and no fallback for another engine, and no operator is weakened so
that it also means something elsewhere. On MySQL or SQLite this gem is not slower or less
featureful — it is wrong, quietly, in whichever direction the engine happens to disagree.

## Requirements

- Ruby 3.4 or later
- Active Record 8.1 or later
- dry-validation 1.11 or later
- PostgreSQL

## Installation

Listable is distributed from git and is **never published to a package registry**. Pin a tag:

```ruby
gem 'listable', github: 'softmonkeyjapan/listable', tag: 'v0.2.0'
```

## Quickstart

Include the module, declare the surface, filter, sort:

```ruby
class Widget < ApplicationRecord
  include Listable

  listable_fields %w[id name status quantity price published_at created_at]
end

Widget.filtering(Listable::Conditions.new(params[:filters]).to_a).sorting(params[:sort])
```

`filtering` and `sorting` are ordinary relation calls: they compose with whatever scoping and
authorization narrowing the host applied first.

```ruby
Widget.where(account: current_account).filtering(conditions).sorting(sort).page(params[:page])
```

## Fail closed

**Nothing is filterable and nothing is sortable until a model declares it.** The default
declared surface is the empty list.

A model that includes `Listable` and declares nothing refuses every filter and every sort, and
discloses no column by omission. The surface is never derived from the model's columns, from
its attributes, or from anything else — a whitelist that defaults to "every column" exposes a
secret column the day a new model forgets to override it, with no test failing.

```ruby
class Secret < ApplicationRecord
  include Listable
end

Secret.listable_fields # => []
```

The declaration is inherited, so single-table inheritance keeps the surface. It is also
overridable as a class method when the surface has to be computed:

```ruby
class Widget < ApplicationRecord
  include Listable

  def self.listable_fields
    %w[name quantity owner]
  end
end
```

A field that reaches the query builder without being declared raises `Listable::UnknownField`;
an undeclared sort key raises `Listable::UnknownKey`. From HTTP neither happens, the contract
having answered 422 first. Reaching them means an internal caller named a field no whitelist
carries, and raising turns a whitelist regression into a red test rather than into an
unfiltered listing served to a client who believes it filtered.

## Query string format

Filters are a **positional list**. Each condition carries exactly three keys — `field`,
`operator` and `value` — and is addressed by its index:

```
filters[<index>][field]=<field>&filters[<index>][operator]=<operator>&filters[<index>][value]=<value>
```

Conditions combine with **AND** and nothing else. There is no OR and no nesting.

A single condition:

```http
filters[0][field]=status&filters[0][operator]==&filters[0][value]=published
```

### Why positional

Because a range is two conditions on the same field, and a map keyed by field name cannot
carry two conditions on the same field:

```http
filters[0][field]=created_at&filters[0][operator]=>=&filters[0][value]=2026-01-01
filters[1][field]=created_at&filters[1][operator]=<=&filters[1][value]=2026-02-01
```

A payload keyed by field name — the format this one replaces — normalises to the empty list
and is refused by the contract, rather than half-read.

### More examples

Several conditions and a sort in one request:

```http
filters[0][field]=quantity&filters[0][operator]=in&filters[0][value]=3,11
filters[1][field]=name&filters[1][operator]=ilike&filters[1][value]=%25spindle%25
sort=-created_at,name
```

A pattern match that respects capitalisation:

```http
filters[0][field]=name&filters[0][operator]=like&filters[0][value]=%25bolt%25
```

Rows whose column holds no value:

```http
filters[0][field]=published_at&filters[0][operator]=is&filters[0][value]=null
```

Exclusion by list, and a bound on a number:

```http
filters[0][field]=status&filters[0][operator]=not_in&filters[0][value]=draft,archived
```

```http
filters[0][field]=price&filters[0][operator]=>&filters[0][value]=15
```

Sorting alone, newest first then by name:

```http
sort=-created_at,name
```

Two notes on the wire, both visible in the examples above:

- The `%` wildcard of `like` and `ilike` is percent-encoded as `%25`. A bare `%` is the start
  of an escape sequence and makes the whole query string unparseable.
- The operators `=`, `!=`, `>`, `>=`, `<` and `<=` are shown literally for readability. They
  may equally be percent-encoded — `%3D`, `%3E%3D` — and most HTTP clients will do it for you.

### Indices

Indices are positions, not identifiers. They need not be contiguous: a client that drops one
condition out of a form leaves a hole rather than renumbering. Duplicates are preserved in the
order they arrived.

A programmatic caller passes a real array instead, and means the same list:

```ruby
Listable::Conditions.new(
  [
    { field: "created_at", operator: ">=", value: "2026-01-01" },
    { field: "created_at", operator: "<=", value: "2026-02-01" },
  ],
).to_a
```

## Operators

Eleven operators, and no more. The vocabulary is readable at `Listable::OPERATORS`, so a host
can document its own API from it.

| Operator | Meaning |
| --- | --- |
| `=` | equality |
| `!=` | inequality |
| `>` | strictly greater than |
| `>=` | greater than or equal to |
| `<` | strictly less than |
| `<=` | less than or equal to |
| `in` | membership in a list |
| `not_in` | absence from a list |
| `like` | case-sensitive pattern match, `%` as the wildcard |
| `ilike` | case-insensitive pattern match, `%` as the wildcard |
| `is` | null, true or false test |

### Values

- `in` and `not_in` accept a real array, or a comma-separated string whose elements are
  stripped: `3, 11` selects two identifiers, not one identifier and one space-padded miss.
- `is` reads its value stripped and downcased. `null` becomes an `IS NULL` test, `true` and
  `false` become boolean equality, and anything else falls back to plain equality. Its value is
  never cast.
- `like` and `ilike` coerce their value to a string and never cast it: casting `%10%` to a
  number would destroy the pattern.
- Every other operator casts its value according to the column's type — date, datetime and
  timestamp are parsed, integer and bigint coerced, decimal and float converted, boolean read
  through Active Record's boolean type. An unknown column type leaves the value untouched.

### What the engine drops in silence

These are client mistakes the contract either refused already or deliberately left alone.
Raising on them would hand a client a replayable 500, so the engine drops the one condition and
leaves the relation narrowed by every other one:

- A value that cannot be cast — a malformed date, a word where a number is expected.
- `like` or `ilike` aimed at a non-textual expression. PostgreSQL refuses `LIKE` against an
  integer, and because the relation is lazy that refusal would surface while the rows are
  enumerated, downstream of every rescue the host wrapped around building the listing.
- A condition naming a blank field, a blank operator, or an operator outside the vocabulary.

Textuality is read off the schema through Active Record's type registry, so a string column
backed by an enum is textual and a translated attribute always is.

## Sorting

The sort parameter is a single string: keys separated by commas, a leading `-` asking for
descending order.

```http
sort=-created_at,name
```

- Keys are applied in the order they were sent, so a client breaks its own ties deliberately.
- A client sort **replaces** the default order rather than queueing behind it.
- The order is always **total**: the primary key is appended descending, unless the client
  already sorted on it. Without this, a paginated listing sorted on a low-cardinality field
  repeats a row between two pages and skips another, because PostgreSQL orders rows sharing a
  sort value however the plan it chose happens to emit them — and the plan of `LIMIT 10` is not
  the plan of `LIMIT 10 OFFSET 10`.
- The default order, used when the sort parameter names nothing, is `created_at` descending
  then primary key descending. A table with no `created_at` falls back to the primary key
  alone: the gem carries the ordering of its consumers' listings, not a timestamp convention
  they have to adopt.

## Custom filters

`filtering` takes an optional map of field name to filter object. The contract between the gem
and your code is **one method and no inheritance**: any object answering
`apply(relation, operator, value)` and returning a relation.

```ruby
class OwnerFilter
  def self.apply(relation, operator, value)
    owned = relation.joins(:owner).where(owners: { email: value })

    operator == "!=" ? relation.where.not(id: owned) : owned
  end
end

Widget.filtering(conditions, "owner" => OwnerFilter)
```

The lookup runs **before** the field is treated as a column and before the declared surface is
consulted, so a custom filter claims its field whether or not a column of that name exists.
This is how a listing filters on an association or a computed perimeter without that name ever
entering the model's whitelist.

The gem wraps no rescue around the call: errors raised inside your filter are yours to handle.

## Validating the request

`Listable::Contract` refuses a bad request before a single predicate is built.

```ruby
result = Listable::Contract.new(
  filterable_fields: Widget.listable_fields + %w[owner],
  sortable_fields: Widget.listable_fields,
).call(filters: params[:filters], sort: params[:sort])

return render(json: { errors: result.errors.to_h }, status: :unprocessable_entity) if result.failure?

Widget.filtering(Listable::Conditions.new(params[:filters]).to_a, "owner" => OwnerFilter)
      .sorting(params[:sort])
```

Both options are **required** and have no default. A contract that does not know the surface
cannot guard it, and a default would be a bypass nobody would notice: every request would pass.

### Why two surfaces

They are two genuinely different lists, and the example above shows why: `owner` is filterable
because a custom filter serves it, and it is not sortable because it is not a column — there is
no expression to order by. A listing may filter on something it cannot sort on, and a single
list could not say so.

The model's own `listable_fields` governs both; the two surfaces diverge at the call site,
where the host adds what its custom filters serve.

### What the contract refuses

- A payload that is not a positional list, and a payload carrying more than twenty conditions.
  Both land on the `filters` parameter and stop there: a payload that is not a list has no
  conditions to attribute anything to.
- Per condition, in a fixed order and at most **one message per condition**: an unknown key,
  then the field (container, blank, undeclared), then the operator (container, blank, outside
  the vocabulary), then the value (missing key, then shape). The message is attributed to the
  index the client sent, holes included, so a client maps every message back to the condition
  that caused it.
- A sort that is not a string, and a sort naming an undeclared key. The failure lands on `sort`
  and never under `filters`, and it is produced **once** for the whole parameter: the message
  enumerates the allowed keys, so repeating it per key would say the same thing twice.

The value check enforces the **operator's arity**, not the field's type. `filters[0][value][]=1`
against `=` is refused here, because otherwise it reaches Arel and — the relation being lazy —
raises while the rows are enumerated, outside every rescue, answering a 500 to a client that
only sent a bad query string.

Deliberately **not** validated: whether an operator suits a field's type, and whether a value
can be cast. Those stay the engine's business to drop in silence.

## Translated attributes

Listable supports translated attributes stored as a JSON document keyed by locale, as
[Mobility](https://github.com/shioyama/mobility) stores them.

The translation library is an **optional dependency**. It is declared in no gemspec, and the
gem establishes its presence by asking the model whether it answers the library's interface. An
application that translates nothing installs nothing extra and never takes that branch.

```ruby
class Document < ApplicationRecord
  include Listable
  extend Mobility

  translates :name

  listable_fields %w[id name created_at]
end
```

A filter on `name` then compares — and a sort on `name` orders by — the value the *reader*
would read: the current locale's extraction, falling back down the backend's own fallback
chain, folded into a single `COALESCE`. It is never the column, because the column holds the
whole JSON document and comparing it matches nothing a client would ever type.

The fallback chain is read off the backend rather than out of a constant, so it follows the
host's configuration. A chain of one locale emits a bare extraction with no `COALESCE`. A
translated attribute is always textual, so every pattern operator applies to it.

## Messages

Fifteen message keys ship in English, French and Japanese, under the gem's own `listable` i18n
namespace so they cannot collide with the messages a host writes for its own contracts.

The contract configures its message backend **on itself**, not globally: installing this gem
does not change how a host's other contracts resolve their messages, and a host that configured
nothing still reads real messages rather than keys.

### Overriding one message

In a Rails application the gem's locale files are on the i18n load path, and i18n merges what
is loaded later over what came before. Name the single key you want to change in a file of your
own:

```yaml
# config/locales/listable.en.yml
en:
  listable:
    errors:
      field_unknown: "This catalogue cannot be filtered on that field. Allowed fields: %{fields}."
```

The other fourteen messages are inherited untouched.

Each shipped message is a complete sentence, because a client reads it on its own in a
response body with no key beside it to complete. An override is worth writing in the same
shape.

Three keys interpolate: `too_many` takes `%{cap}`, and `field_unknown` and `sort_unknown` take
`%{fields}`.

## Public surface

Committed and versioned:

- `Listable` — the module a model includes. It carries filtering and sorting together; there is
  no way to include one without the other.
- `Listable::OPERATORS` — the operator vocabulary.
- `Listable::Conditions` — normalises a raw filters payload into a positional list.
- `Listable::Contract` — the dry-validation contract guarding listing query parameters.
- `Listable::UnknownField`, `Listable::UnknownKey` — raised when an undeclared field or sort key
  reaches the query builder.
- The custom-filter protocol: any object answering `apply(relation, operator, value)` and
  returning a relation.

`Listable` is the only top-level constant the gem defines. Everything else — the field
resolver, the index-key pattern, the casting mechanics — is internal and may change without
ceremony. Changes to the list above, to the request format or to a message key bump the minor
version and are recorded in [CHANGELOG.md](CHANGELOG.md).

## Out of scope

Pagination, rendering, controllers, HTTP, database engines other than PostgreSQL, OR and nested
boolean logic in filters, per-field operator whitelists, and publishing to RubyGems.

## Development

```sh
bundle install
bundle exec rspec
BUNDLE_WITHOUT=translations bundle exec rspec
bundle exec rubocop
```

The suite runs real queries against a real PostgreSQL and asserts on the rows that come back —
most of the traps this gem exists to avoid are invisible in the relation it builds. It connects
with `LISTABLE_DATABASE_HOST`, `LISTABLE_DATABASE_PORT`, `LISTABLE_DATABASE_USERNAME`,
`LISTABLE_DATABASE_PASSWORD` and `LISTABLE_DATABASE_NAME`, each defaulting to a stock local
PostgreSQL, and it creates and rebuilds its own database.

The second run is the one that measures the optional dependency: it excludes the bundler group
the translation library lives in, so the library is genuinely off the load path and the
examples that need it skip while every other one runs unchanged.

## License

MIT. See [LICENSE](LICENSE).
