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
* `Listable::UnknownField` — raised when an undeclared field reaches the query builder.
* `Listable::UnknownKey` — raised when an undeclared sort key reaches the query builder.
* The custom-filter protocol: any object answering `.apply(relation, operator, value)` and
  returning a relation. One method, no inheritance.

`Listable` is the only top-level constant the gem defines.

Everything else — the field resolver, the index-key pattern, the casting mechanics — is
internal and may change without ceremony. Renaming, splitting or deleting an internal
object needs no version bump and no deprecation. Changing anything in the list above, or
the request format, or a message key, bumps the minor version.

## Execution regime

An agent handed a single commit implements that commit itself. It does not delegate the
work it was given.

Work spanning several commits is orchestrated: one agent per commit, dispatched by the
orchestrating agent. Orchestration is one level deep — an orchestrated agent implements,
it does not orchestrate in turn.

## Commit style

English, conventional format, one line. No body, no co-authoring trailer, no tool
attribution.

```
feat: add the sort tie-breaker on the primary key
```

## No fix-up commits

A defect found by a review, or a finding raised against work that is not yet merged, is
repaired **in the commit that introduced it**. Amend or rebase; never append a follow-up.

The history must read as if the implementation had been right the first time. A commit
whose subject is a correction of an earlier unmerged commit does not belong in this
repository.
