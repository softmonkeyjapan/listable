# Changelog

What this file records, and why it is not a log of every commit: the request format and the
message keys are the API surface of every application that installs this gem. A change to
either one is a change a consumer has to make in its own controllers, its own clients and its
own documentation, so it is flagged here under **Breaking** and it bumps the minor version.

Everything else — the field resolver, the index-key pattern, the casting mechanics — is
internal and changes without ceremony or an entry.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions stay in
the `0.x` range while the public surface is still allowed to move.

## [0.1.0] — 2026-09-23

First release.

### Added

- `Listable`, the single module a model includes: it carries filtering and sorting together.
- `listable_fields`, the declaration of the surface a client may name. The default is the
  empty list: a model that declares nothing refuses every filter and every sort. The
  declaration is inherited by subclasses and overridable as a class method.
- `filtering`, which narrows a relation by a positional list of conditions combined with AND,
  and accepts a map of custom filters — any object answering
  `apply(relation, operator, value)` and returning a relation.
- `sorting`, which orders a relation by the keys a client named and keeps the order total by
  appending the primary key. The default order is `created_at` descending, falling back to the
  primary key alone on a table that carries no creation timestamp.
- `Listable::OPERATORS`, the closed vocabulary of eleven operators: `=`, `!=`, `>`, `>=`, `<`,
  `<=`, `in`, `not_in`, `like`, `ilike`, `is`.
- `Listable::Conditions`, which normalises a filters payload — the hash a query string parses
  into, or an array from a programmatic caller — into the positional list the engine reads.
- `Listable::Contract`, the dry-validation contract guarding listing query parameters. It takes
  a filterable surface and a sortable surface, both required, and caps a request at twenty
  conditions.
- `Listable::UnknownField` and `Listable::UnknownKey`, raised when an undeclared field or sort
  key reaches the query builder.
- Support for translated attributes stored as a JSON document keyed by locale. The translation
  library is an optional dependency, detected at runtime.
- Validation messages in English, French and Japanese, under the gem's own `listable` i18n
  namespace, overridable one key at a time.

### Request format

The filters payload is a positional list of conditions, each carrying exactly `field`,
`operator` and `value`:

```
filters[0][field]=created_at&filters[0][operator]=>=&filters[0][value]=2026-01-01
```

The sort parameter is a single string of keys separated by commas, a leading `-` asking for
descending order: `sort=-created_at,name`.

### Message keys

`list?`, `hash?`, `too_many`, `field_required`, `field_scalar`, `field_unknown`,
`operator_required`, `operator_scalar`, `operator_invalid`, `value_required`, `value_scalar`,
`value_list`, `unknown_key?`, `sort_scalar`, `sort_unknown`.

[0.1.0]: https://github.com/softmonkeyjapan/listable/releases/tag/v0.1.0
