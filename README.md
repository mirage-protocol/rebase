# Rebase

A pure move library for elastic `u64` numbers.

A `Rebase { elastic, base }` holds an `elastic` and a `base` part.

* `base` represents shares of elastic
* `elastic` is freely floating and can be modified
* as `elastic` changes, the net "worth" of a `base` value decreases

## License

MIT
