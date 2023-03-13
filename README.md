# Rebase

A pure move library for elastic `u64` numbers.

A `Rebase { elastic: u64, base: u64 }` holds an `elastic` and a `base` part.

* `base` represents shares of elastic
* `elastic` is freely floating and can be modified
* the ownership of some `base` part will remain a fixed percentage of the `total_elastic`, e.g.

```rust
(my_base_part / total_base) * total_elastic = my_portion
```

## Example

Rebase numbers have many interesting use cases, for example if we define:

```rust
my_basket_rebase = Rebase { 
    elastic: coin::value(some_basket_of_coin),
    base: 100,
}
```

We now have `100` base parts which each represent ownership over `1%` of `basket_of_coin`.

If we define a function:

```rust
fun add_to_basket(coin: Coin<C>) {
    rebase::increase_elastic(
        &mut my_basket_rebase,
        coin::value(&coin)
    )
    coin::merge(&mut some_basket_of_coin, coin);
}
```

Then as `coin`'s are added through `add_to_basket(coin)`, each of the `100` base parts continue to represent `1%` of the assets in `some_basket_of_coins`. The ownership "elastically increases" without need for any tallying. 

This is useful for handling a large number of owners over a pool of resources.

## License

MIT
