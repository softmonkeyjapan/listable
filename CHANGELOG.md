# Changelog

What this file records, and why it is not a log of every commit: the request format and the
message keys are the API surface of every application that installs this gem. A change to
either one is a change a consumer has to make in its own controllers, its own clients and its
own documentation, so it is flagged here under **Breaking** and it bumps the minor version.

Everything else — the field resolver, the index-key pattern, the casting mechanics — is
internal and changes without ceremony or an entry.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions stay in
the `0.x` range while the public surface is still allowed to move.

## [0.4.0] — 2026-09-24

### Breaking

- **A refusal is attributed to the index the client sent, written as the client wrote it.**
  The index used to be read as a number before it became the failure key, so a client sending
  `filters[007]` read its refusal under `7` — an index it never sent — and matching a message
  back to its condition by key failed on exactly the payload that needed it.

  The key is now a string for both accepted payload shapes. An array payload reports under
  `"0"`, `"1"`, and a hash payload reports the key it received. Callers reading the result hash
  in process must look refusals up by string; over HTTP the change is visible only for an index
  that was not already in canonical form, since JSON stringifies object keys either way.

  Conditions are still read and reported in the numeric order of their indices: ordering and
  reporting read different values. Two indices that differ as text and agree as numbers —
  `"7"` and `"007"` — keep arrival order, in `Listable::Conditions` as in `Listable::Contract`.

## [0.3.0] — 2026-09-24

### Breaking

- **A condition answers every mistake it carries again**, not just the first one. A condition
  whose field is blank, whose operator is unknown and whose value is missing answers three
  messages instead of one, in that fixed order.

  Earlier versions returned one message per condition, which made a client discover its
  mistakes one round trip at a time: told only that its field was undeclared, it corrected the
  field, sent the request again and learned the operator was wrong too. The rule that keeps a
  payload of malformed conditions readable is that every message is attributed to the index the
  client sent — not that there is only one of them.

  Each of the four families of checks still contributes one message at most, so a field that is
  an object is reported as an object and not also as an undeclared name. An entry that is not
  an object at all still answers that alone.

  A response body can therefore carry more messages under an index than it did in `0.2.x`. No
  message key, text or interpolation token changes.

## [0.2.1] — 2026-09-23

### Fixed

- Three French messages — `too_many`, `field_unknown` and `sort_unknown` — carried a
  non-breaking space before their colon where the published contract carries an ordinary one.
  The text is otherwise unchanged, and no message key or interpolation token moves.

## [0.2.0] — 2026-09-23

### Breaking

- **The fifteen validation messages are reworded.** Each one is now a complete sentence —
  `The field cannot be filtered on. Allowed fields: id, name.` — where it used to be a clause
  completing the name of the key it hangs off — `must carry a field among: id, name`. English,
  French and Japanese are all reworded.

  These strings are served straight to the clients of every listing endpoint that installs the
  gem, so this is a change visible in HTTP responses. An application already in production
  answers different text to its clients from the moment it upgrades, and anything asserting on
  the old wording — a client's test suite, a support runbook, a translated screen — has to be
  updated with it.

  Nothing else about the messages moves: the fifteen keys are the same keys, and the three
  interpolation tokens are still `%{cap}` for `too_many` and `%{fields}` for `field_unknown`
  and `sort_unknown`. A host that overrode a message by key keeps overriding the same key.

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

[0.4.0]: https://github.com/softmonkeyjapan/listable/releases/tag/v0.4.0
[0.3.0]: https://github.com/softmonkeyjapan/listable/releases/tag/v0.3.0
[0.2.1]: https://github.com/softmonkeyjapan/listable/releases/tag/v0.2.1
[0.2.0]: https://github.com/softmonkeyjapan/listable/releases/tag/v0.2.0
[0.1.0]: https://github.com/softmonkeyjapan/listable/releases/tag/v0.1.0
