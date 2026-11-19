# Working agreement

Rules for any agent working in this repository. They govern every commit. A change that
conflicts with a rule below is refused, however much code it would save.

## Documentation comments

Every method carries a documentation comment in English. No exception: private methods,
one-line methods and accessors are documented too.

Format is classic RDoc:

```ruby
# Casts a filter value according to the column's declared type.
#
# ==== Parameters
#
# * +value+ - the raw value as received from the client
# * +type+ - the Active Record type of the column
#
# ==== Returns
#
# The cast value, or the untouched value when the type is unknown.
```

A comment states *why the code is shaped the way it is*, not what the next line does.
Every trap described in the specification lives as a comment at the exact place a reader
would otherwise "simplify" the code back into the bug — the pattern operator that refuses
to build a predicate against a non-textual expression, the cast failure that drops one
condition instead of raising, the translated attribute compared through its locale
extraction rather than through the column, the value arity refused before it reaches Arel,
the primary key appended to every sort.

## PostgreSQL only

The gem targets PostgreSQL. Operators, casts and expressions are written against
PostgreSQL semantics, and the suite runs against a real PostgreSQL database.

No branch, no shim and no fallback for another engine is accepted, and no operator is
weakened so it also means something on another engine.

## Fail closed

Nothing is filterable and nothing is sortable until a model declares it. The default
declared surface is the empty list: a model that declares nothing refuses every filter and
every sort and discloses no column by omission.

Any change that would make the default surface non-empty is refused — deriving it from the
model's columns, from its attributes, or from anything else. This holds even when the
change deletes code, simplifies a method, or fixes a failing test elsewhere.

A field that reaches the query builder without being declared raises. Silence there would
hand a client an unfiltered listing it believes is filtered.

## Public surface

Committed and versioned:

* `Listable` — the module a model includes; carries filtering and sorting together.
* `Listable::OPERATORS` — the operator vocabulary.
* `Listable::Conditions` — normalises a raw filters payload into a positional list.
* `Listable::Contract` — the dry-validation contract guarding listing query parameters.
* `Listable::Definition` — one listing declared once: its contract, its filtering and sorting.
* `Listable::UnknownField` — raised when an undeclared field reaches the query builder.
* `Listable::UnknownKey` — raised when an undeclared sort key reaches the query builder.
* The custom-filter protocol: any object answering `.apply(relation, operator, value)` and
  returning a relation, and optionally `.refusal(operator, value)` answering a message key or
  `nil`, which `Listable::Contract` asks when it is handed the filter. No inheritance.
* The custom-sort protocol: any object answering `.ordering(relation, descending)` and
  returning one Arel ordering node or an array of them. One method, no inheritance.

`Listable` is the only top-level constant the gem defines.

Everything else — the field resolver, the index-key pattern, the casting mechanics — is
internal and may change without ceremony. Renaming, splitting or deleting an internal
object needs no version bump and no deprecation. Changing anything in the list above, or
the request format, or a message key, bumps the minor version.
