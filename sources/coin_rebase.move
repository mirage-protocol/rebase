/// Elastically rebasing numbers
module rebase::coin_rebase {
    use aptos_framework::coin::{Self, Coin};

    use safe64::safe64;

    /// A rebase with elastic specifically designated as a Coins
    struct CoinRebase<phantom CoinType> has store {
        /// The elastic part can change independant of the base
        elastic: Coin<CoinType>,
        /// Base parts represent a fixed portion of the elastic
        base: u64,
    }

    /// Represents base ownership of a rebase
    struct Base<phantom CoinType> has store {
        /// The amount of base part
        amount: u64,
    }

    /// Get zero rebase
    public fun zero_rebase<CoinType>(): CoinRebase<CoinType> {
        CoinRebase<CoinType> {
            elastic: coin::zero<CoinType>(),
            base: 0
        }
    }

    /// Get a zero value base
    public fun zero_base<CoinType>(): Base<CoinType> {
        Base<CoinType> { amount: 0 }
    }

    /// Merge two base
    public fun merge_base<CoinType>(dst_base: &mut Base<CoinType>, base: Base<CoinType>) {
        let Base { amount } = base;
        dst_base.amount = dst_base.amount + amount;
    }

    /// Extract from a base
    public fun extract_base<CoinType>(dst_base: &mut Base<CoinType>, amount: u64): Base<CoinType> {
        dst_base.amount = dst_base.amount - amount;
        Base<CoinType> { amount }
    }

    /// Extract all from Base
    public fun extract_all_base<CoinType>(dst_base: &mut Base<CoinType>): Base<CoinType> {
        let amount = dst_base.amount;
        dst_base.amount = 0;
        Base<CoinType> { amount }
    }

    /// Get the amount in a Base
    public fun get_base_amount<CoinType>(base: &Base<CoinType>): u64 {
        base.amount
    }

    /// Get elastic rebase part
    public fun get_elastic<CoinType>(rebase:  &CoinRebase<CoinType>): u64 {
        coin::value(&rebase.elastic)
    }

    /// Get base rebase part
    public fun get_base<CoinType>(rebase:  &CoinRebase<CoinType>): u64 {
        rebase.base
    }

    /// Add elastic to a rebase
    /// Keeps the amount of elastic per base constant
    /// Returns the newly created Base
    public fun add_elastic<CoinType>(
        rebase: &mut CoinRebase<CoinType>,
        elastic: Coin<CoinType>,
        round_up: bool
    ): Base<CoinType> {
        let base = elastic_to_base(rebase, coin::value(&elastic), round_up);
        coin::merge(
            &mut rebase.elastic,
            elastic
        );
        rebase.base = rebase.base + base;
        Base<CoinType> { amount: base }
    }

    /// Accepts Base to sub from a rebase
    /// Keeps the amount of elastic per base constant
    /// Returns the elastic that was removed
    public fun sub_base<CoinType>(
        rebase: &mut CoinRebase<CoinType>,
        base: Base<CoinType>,
        round_up: bool
    ): Coin<CoinType> {
        let Base { amount } = base;
        let elastic = base_to_elastic(rebase, amount, round_up);
        rebase.base = rebase.base - amount;
        coin::extract<CoinType>(
            &mut rebase.elastic,
            elastic
        )
    }

    /// Accepts an elastic amount to sub from a rebase
    /// and a Base to reduce.
    /// Keeps the amount of elastic per base constant
    /// Reduces base_to_reduce
    /// Returns (the reduced base, the removed elastic)
    ///
    /// The given base_to_reduce must have an amount greater
    /// than the base to be destroyed
    public fun sub_elastic<CoinType>(
        rebase: &mut CoinRebase<CoinType>,
        base_to_reduce: &mut Base<CoinType>,
        elastic: u64,
        round_up: bool
    ): (u64, Coin<CoinType>) {
        let base = elastic_to_base(rebase, elastic, round_up);
        rebase.base = rebase.base - base;
        base_to_reduce.amount = base_to_reduce.amount - base;
        (
            base,
            coin::extract<CoinType>(
                &mut rebase.elastic,
                elastic
            )
        )
    }

    /// Add only to the elastic part of a rebase
    /// The amount of elastic per base part will increase
    ///
    /// Note: No new Base is created, all current Base holders 
    /// will have their elastic increase
    public fun increase_elastic<CoinType>(
        rebase: &mut CoinRebase<CoinType>,
        elastic: Coin<CoinType>
    ) {
        coin::merge<CoinType>(
            &mut rebase.elastic,
            elastic
        );
    }

    /// Remove only from the elastic part of a rebase
    /// The amount of elastic per base part will decrease
    public fun decrease_elastic<CoinType>(
        rebase: &mut CoinRebase<CoinType>,
        elastic: u64
    ): Coin<CoinType> {
        coin::extract<CoinType>(
            &mut rebase.elastic,
            elastic
        )
    }

    /// Remove elastic and base from a rebase
    /// The amount of elastic per base part will potentially change
    public fun decrease_elastic_and_base<CoinType>(
        rebase: &mut CoinRebase<CoinType>,
        elastic: u64,
        base: Base<CoinType>,
    ): Coin<CoinType> {
        let Base { amount } = base;
        rebase.base = rebase.base - amount;
        coin::extract<CoinType>(
            &mut rebase.elastic,
            elastic
        )
    }

    /// Returns the amount of base for the given elastic
    /// If the given rebase has no base or elastic, equally
    /// increment the entire rebase by new_elastic.
    public fun elastic_to_base<CoinType>(
        rebase: &CoinRebase<CoinType>,
        new_elastic: u64,
        round_up: bool
    ): u64 {
        let elastic = coin::value(&rebase.elastic);
        let base = rebase.base;

        let new_base_part: u64;
        if (elastic == 0 || base == 0) {
            new_base_part = new_elastic;
        } else {
            new_base_part = safe64::muldiv_64(new_elastic, base, elastic);
            if (
                new_base_part != 0 &&
                round_up &&
                safe64::muldiv_64(new_base_part, elastic, base) < new_elastic
            ) {
                new_base_part = new_base_part + 1;
            };
        };
        new_base_part
    }

    /// Returns the amount of elastic for the given base
    /// If the given rebase has no base or elastic, equally
    /// increment the entire rebase by new_base_part.
    public fun base_to_elastic<CoinType>(
        rebase: &CoinRebase<CoinType>,
        new_base_part: u64,
        round_up: bool
    ): u64 {
        let elastic = coin::value(&rebase.elastic);
        let base = rebase.base;

        let new_elastic: u64;
        if (base == 0) {
            new_elastic = new_base_part
        } else if (elastic == 0) {
            new_elastic = 0
        } else {
            new_elastic = safe64::muldiv_64(new_base_part, elastic, base);
            if (
                new_elastic != 0 &&
                round_up &&
                safe64::muldiv_64(new_elastic, base, elastic) < new_base_part
            ) {
                new_elastic = new_elastic + 1;
            };
        };
        new_elastic
    }

    ////////////////////////////////////////////////////////////
    //                        TESTING                         //
    ////////////////////////////////////////////////////////////

    #[test_only]
    use std::signer;
    #[test_only]
    use std::string;
    #[test_only]
    use aptos_framework::account;

    #[test_only]
    const PRECISION_8: u64 = 100000000;

    #[test_only]
    const MAX_U64: u128 = 18446744073709551615;

    #[test_only]
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    #[test_only]
    struct FakeCoin {}

    #[test_only]
    struct FakeCoinCapabilities has key {
        burn_cap: coin::BurnCapability<FakeCoin>,
        freeze_cap: coin::FreezeCapability<FakeCoin>,
        mint_cap: coin::MintCapability<FakeCoin>,
    }


    #[test_only]
    fun initialize_fake_coin(
        account: &signer,
    ): (coin::BurnCapability<FakeCoin>, coin::FreezeCapability<FakeCoin>, coin::MintCapability<FakeCoin>) {
        account::create_account_for_test(signer::address_of(account));
        coin::initialize<FakeCoin>(
            account,
            string::utf8(b"Fake Coin"),
            string::utf8(b"FAKE"),
            8,
            true
        )
    }

    #[test_only]
    fun initialize_and_register_fake_coin(
        account: &signer
    ): (coin::BurnCapability<FakeCoin>, coin::FreezeCapability<FakeCoin>, coin::MintCapability<FakeCoin>) {
        let (burn_cap, freeze_cap, mint_cap) = initialize_fake_coin(account);
        coin::register<FakeCoin>(account);
        (burn_cap, freeze_cap, mint_cap)
    }

    #[test_only]
    public entry fun create_fake_coin(
        account: &signer,
        amount: u64
    ): Coin<FakeCoin> {
        let (burn_cap, freeze_cap, mint_cap) = initialize_and_register_fake_coin(account);
        let mint = coin::mint<FakeCoin>(amount, &mint_cap);
        move_to(account, FakeCoinCapabilities {
            burn_cap,
            freeze_cap,
            mint_cap,
        });

        mint
    }

    #[test_only]
    /// Destroy a base part and get its value
    fun destroy_base<CoinType>(base: Base<CoinType>): u64 {
        let Base { amount } = base;
        amount
    }

    #[test(account = @rebase)]
    fun test_zero_rebase(account: &signer) {
        let coin = create_fake_coin(account, 100 * PRECISION_8);

        let CoinRebase { elastic, base } = zero_rebase<FakeCoin>();
        assert!(coin::value(&elastic) == 0, 1);
        assert!(base == 0, 1);

        // kill coin
        coin::deposit(signer::address_of(account), elastic);
        coin::deposit(signer::address_of(account), coin);
    }

    #[test(account = @rebase)]
    fun test_add_elastic(account: &signer) {
        let coin = create_fake_coin(account, 100 * PRECISION_8);

        let rebase = zero_rebase<FakeCoin>();

        let base = add_elastic(&mut rebase, coin, false);

        assert!(base.amount == 100 * PRECISION_8, 1);

        destroy_base<FakeCoin>(base);

        let CoinRebase { elastic, base } = rebase;
        assert!(coin::value(&elastic) == 100 * PRECISION_8, 1);
        assert!(base == 100 * PRECISION_8, 1);

        // kill coin
        coin::deposit(signer::address_of(account), elastic);
    }

    #[test(account = @rebase)]
    fun test_sub_base(account: &signer) {
        let coin = create_fake_coin(account, 100 * PRECISION_8);

        let rebase = zero_rebase<FakeCoin>();

        let base = add_elastic(&mut rebase, coin, false);

        let half_base = extract_base(
            &mut base,
            50 * PRECISION_8
        );

        destroy_base<FakeCoin>(base);

        let elastic = sub_base(&mut rebase, half_base, false);

        let CoinRebase { elastic: rem_elastic, base } = rebase;
        assert!(coin::value(&elastic) == 50 * PRECISION_8, 1);
        assert!(base == 50 * PRECISION_8, 1);
        assert!(coin::value(&rem_elastic) == 50 * PRECISION_8, 1);

        // kill coin
        coin::deposit(signer::address_of(account), elastic);
        coin::deposit(signer::address_of(account), rem_elastic);
    }

    #[test(account = @rebase)]
    fun test_increase_elastic(account: &signer) {
        let coin = create_fake_coin(account, 100 * PRECISION_8);

        let rebase = zero_rebase<FakeCoin>();

        increase_elastic(&mut rebase, coin);

        let CoinRebase { elastic, base } = rebase;

        assert!(coin::value(&elastic) == 100 * PRECISION_8, 1);
        assert!(base == 0, 1);

        // kill coin
        coin::deposit(signer::address_of(account), elastic);
    }

    #[test(account = @rebase)]
    fun test_decrease_elastic(account: &signer) {
        let coin = create_fake_coin(account, 100 * PRECISION_8);

        let rebase = zero_rebase<FakeCoin>();

        increase_elastic(&mut rebase, coin);

        let removed_coin = decrease_elastic(&mut rebase, 50 * PRECISION_8);

        let CoinRebase { elastic, base } = rebase;

        assert!(coin::value(&removed_coin) == 50 * PRECISION_8, 1);
        assert!(coin::value(&elastic) == 50 * PRECISION_8, 1);
        assert!(base == 0, 1);

        // kill coin
        coin::deposit(signer::address_of(account), elastic);
        coin::deposit(signer::address_of(account), removed_coin);
    }
}
