///a Manages elastically rebasing numbers
module rebase::rebase {
    #[test_only]
    use std::signer::address_of;

    #[test_only]
    use aptos_framework::account;

    use safe_u64::math::muldiv_64;

    #[test_only]
    const MAX_U64: u256 = 18446744073709551615;

    /// A rebase has an elastic part and a base part
    struct Rebase has copy, store {
        /// The elastic part can change independant of the base
        elastic: u64,
        /// Base parts represent a fixed portion of the elastic
        base: u64,
    }

    /// Get zero rebase
    public fun zero_rebase(): Rebase { Rebase { elastic: 0, base: 0 } }

    /// Get elastic rebase part
    public fun get_elastic(total: &Rebase): u64 { total.elastic }

    /// Get base rebase part
    public fun get_base(total: &Rebase): u64 { total.base }

    /// Update a rebase given a new copy
    public fun update_rebase(
        dst_rebase: &mut Rebase,
        source: Rebase
    ) {
        let Rebase { elastic, base } = source;
        dst_rebase.elastic = elastic;
        dst_rebase.base = base;
    }

    /// Calculates a given elastic value in the base
    public fun elastic_to_base(
        rebase: &Rebase,
        new_elastic: u64,
        roundUp: bool
    ): u64 {
        let Rebase { elastic, base } = *rebase;

        let new_base_part: u64;
        if (elastic == 0) {
            new_base_part = new_elastic;
        } else {
            new_base_part = muldiv_64(new_elastic, base, elastic);
            if (
                new_base_part != 0 &&
                    roundUp &&
                    muldiv_64(new_base_part, elastic, base) < new_elastic
            ) {
                new_base_part = new_base_part + 1;
            };
        };
        new_base_part
    }

    /// Calculates a given base value in the elastic
    public fun base_to_elastic(
        rebase: &Rebase,
        new_base_part: u64,
        roundUp: bool
    ): u64 {
        let Rebase { elastic, base } = *rebase;

        let new_elastic: u64;
        if (base == 0) {
            new_elastic = new_base_part
        } else {
            new_elastic = muldiv_64(new_base_part, elastic, base);
            if (
                new_elastic != 0 &&
                    roundUp &&
                    muldiv_64(new_elastic, base, elastic) < new_base_part
            ) {
                new_elastic = new_elastic + 1;
            };
        };
        new_elastic
    }

    /// Add an elastic value into a rebase
    public fun add_elastic(
        rebase: &mut Rebase,
        elastic: u64,
        roundUp: bool
    ): u64 {
        let base = elastic_to_base(freeze(rebase), elastic, roundUp);
        rebase.elastic = rebase.elastic + elastic;
        rebase.base = rebase.base + base;
        base
    }

    /// Subtract a base value from a rebase
    public fun sub_base(
        rebase: &mut Rebase,
        base: u64,
        roundUp: bool
    ): u64 {
        let elastic = base_to_elastic(freeze(rebase), base, roundUp);
        rebase.elastic = rebase.elastic - elastic;
        rebase.base = rebase.base - base;
        elastic
    }

    /// Add an elastic and a base to a rebase
    public fun increase_elastic_and_base(
        total: &mut Rebase,
        elastic: u64,
        base: u64
    ) {
        total.elastic = total.elastic + elastic;
        total.base = total.base + base;
    }

    /// Subtract an elastic and base from a rebase
    public fun decrease_elastic_and_base(
        total: &mut Rebase,
        elastic: u64,
        base: u64
    ) {
        total.elastic = total.elastic - elastic;
        total.base = total.base - base;
    }

    /// Add only to the elastic part of a rebase
    public fun increase_elastic(total: &mut Rebase, elastic: u64) {
        total.elastic = total.elastic + elastic;
    }

    /// Subtract only from the elastic part of a rebase
    public fun decrease_elastic(total: &mut Rebase, elastic: u64) {
        total.elastic = total.elastic - elastic;
    }

    #[test(account = @0x1)]
    public entry fun test_add_elastic(account: signer) {
        let account_addr = address_of(&account);
        account::create_account_for_test(account_addr);

        let rebase = Rebase { elastic: ((MAX_U64 - 1000) as u64), base: ((MAX_U64 - 1000) as u64) };

        let part = add_elastic(&mut rebase, 100, false);

        assert!(part == 100, 1);
        assert!(rebase.elastic == ((MAX_U64 - 900) as u64), 1);

        let Rebase { elastic: _, base: _ } = rebase;
    }
}
