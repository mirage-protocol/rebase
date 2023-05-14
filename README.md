# Rebase

A move library for elastic numbers.

A `Rebase { elastic: u64, base: u64 }` holds an `elastic` and a `base` part.

* `base` represents shares of elastic
* `elastic` is freely floating and can be modified
* the ownership of some `base` part will remain a fixed percentage of the `total_elastic`, e.g.

```rust
(my_base_part / total_base) * total_elastic = my_portion
```

## How to Use

Add to `Move.toml`:

```toml
[dependencies.Rebase]
git = "https://github.com/mirage-protocol/rebase.git"
rev = "main"
```

And then use in your `.move` file:

```rust
use rebase::rebase;
use rebase::coin_rebase;

...
```

## Example: CoinRebase

Rebase numbers have many interesting use cases. If we have a situation where we want to represent ownership of some `Coin<CoinType>` we can use a `CoinRebase`

```rust
// create an empty rebase
let rebase = coin_rebase::zero_rebase<CoinType>();

// get some coin
let my_deposit: Coin<CoinType> = coin::withdraw<CoinType>(my_account, 1_000_000);

// add the coin as elastic part
// this function returns new "Base" which represent ownership shares
let base_shares: Base<CoinType> = coin_rebase::add_elastic<CoinType>(
    &mut rebase,
    my_deposit,
);

// we can calculate the coin value of the Base we just created
let calculated_base_to_coin: u64 = coin_rebase::base_to_elastic<CoinType>(
    &rebase,
    coin_rebase::get_base_amount(base_shares),
    false, // don't round up
);

// as expected, the calculated coin value is the original deposit!
assert!(calculated_base_to_coin == 1_000_000, ERROR);

// ------------

// we can also add new Coin (elastic) without creating new ownership (Base)
// this will increase the coin value of all Base shares
coin_rebase::increase_elastic<CoinType>(
    &mut rebase,
    coin::withdraw<CoinType>(other_account, 500_000),
);

// now if we recalculate the worth of our base shares now
calculated_base_to_coin = coin_rebase::base_to_elastic<CoinType>(
    &rebase,
    coin_rebase::get_base_amount(base_shares),
    false, // don't round up
);

// we can see the value of the shares has increased!
assert!(calculated_base_to_coin == 1_500_000, ERROR);

// ------------

// we can also renounce base ownership and get our coins back!
let returned_coin = coin_rebase::sub_base<CoinType>(
    &mut rebase,
    base_shares,
    false, // don't round up
);

// we can see the value of the returned coin is what we calculated earlier!
assert!(calculated_base_to_coin, coin::value(&returned_coin));

// The user was able to redeem the same base_shares we created
// at the very start for their initial deposit plus an extra
// 500,000 Coin that came from the use of increase_elastic.
coin::deposit(signer::address_of(my_account), returned_coin);
```

Then as `Coin<CoinType>`'s are added to the rebase, each of the base parts net coin value will continue to increase.

This kind of structure is useful for many sorts of situations when multiple users own a pool of assets. `CoinRebase` (and `Rebase`) expose useful functions that make operations like taking interest, taking fees, distributing rewards, etc. extremely simple.

## License

MIT
