/// Manages elastically rebasing numbers
module rebase::rebase {
    use safe64::safe64;

    /// An elastic part of a rebase that has been created and
    /// This must always be accounted for
    struct Elastic has store {
        /// The amount of elastic part
        amount: u64,
    }

    /// A base part of a rebase that has been created and
    /// This must always be accounted for
    struct Base has store {
        /// The amount of base part
        amount: u64,
    }

    /// A rebase has an elastic part and a base part
    struct Rebase has store {
        /// The elastic part can change independant of the base
        elastic: u64,
        /// Base parts represent a fixed portion of the elastic
        base: u64,
    }

    /// Get zero rebase
    public fun zero_rebase(): Rebase {
        Rebase {
            elastic: 0,
            base: 0
        }
    }

    /// Get a zero value elastic
    public fun zero_elastic(): Elastic {
        Elastic { amount: 0 }
    }

    /// Get a zero value base
    public fun zero_base(): Base {
        Base { amount: 0 }
    }

    /// Merge two elastic
    public fun merge_elastic(dst_elastic: &mut Elastic, elastic: Elastic) {
        let Elastic { amount } = elastic;
        dst_elastic.amount = dst_elastic.amount + amount;
    }

    /// Extract from an elastic
    public fun extract_elastic(dst_elastic: &mut Elastic, amount: u64): Elastic {
        dst_elastic.amount = dst_elastic.amount - amount;
        Elastic { amount }
    }

    /// Merge two base
    public fun merge_base(dst_base: &mut Base, base: Base) {
        let Base { amount } = base;
        dst_base.amount = dst_base.amount + amount;
    }

    /// Extract from a base
    public fun extract_base(dst_base: &mut Base, amount: u64): Base {
        dst_base.amount = dst_base.amount - amount;
        Base { amount }
    }

    /// Extract all from Base
    public fun extract_all_base(dst_base: &mut Base): Base {
        let amount = dst_base.amount;
        dst_base.amount = 0;
        Base { amount }
    }

    /// Extract all from Elastic
    public fun extract_all_elastic(dst_elastic: &mut Elastic): Elastic {
        let amount = dst_elastic.amount;
        dst_elastic.amount = 0;
        Elastic { amount }
    }

    /// Get the amount in an Elastic
    public fun get_elastic_amount(elastic: &Elastic): u64 {
        elastic.amount
    }

    /// Get the amount in a Base
    public fun get_base_amount(base: &Base): u64 {
        base.amount
    }

    /// Get elastic rebase part
    public fun get_elastic(rebase: &Rebase): u64 {
        rebase.elastic
    }

    /// Get base rebase part
    public fun get_base(rebase: &Rebase): u64 {
        rebase.base
    }

    /// Add elastic to a rebase
    /// Keeps the amount of elastic per base constant
    /// Returns the newly created Base
    public fun add_elastic(
        rebase: &mut Rebase,
        elastic: u64,
        round_up: bool
    ): Base {
        let base = elastic_to_base(rebase, elastic, round_up);
        rebase.elastic = rebase.elastic + elastic;
        rebase.base = rebase.base + base;
        Base { amount: base }
    }

    /// Accepts Base to sub from a rebase
    /// Keeps the amount of elastic per base constant
    /// Returns the amount of elastic that has been destroyed
    public fun sub_base(
        rebase: &mut Rebase,
        base: Base,
        round_up: bool
    ): u64 {
        let Base { amount } = base;
        let elastic = base_to_elastic(rebase, amount, round_up);
        rebase.elastic = rebase.elastic - elastic;
        rebase.base = rebase.base - amount;
        elastic
    }

    /// Accepts Elastic to sub from a rebase
    /// Keeps the amount of elastic per base constant
    /// Reduces base_to_reduce and return the remaining amount
    ///
    /// The given base_to_reduce must have an amount greater
    /// than the base to be destroyed
    public fun sub_elastic(
        rebase: &mut Rebase,
        base_to_reduce: &mut Base,
        elastic: u64,
        round_up: bool
    ): u64 {
        let base = elastic_to_base(rebase, elastic, round_up);
        rebase.elastic = rebase.elastic - elastic;
        rebase.base = rebase.base - base;
        base_to_reduce.amount = base_to_reduce.amount - base;
        base
    }

    /// Add only to the elastic part of a rebase
    /// The amount of elastic per base part will increase
    ///
    /// Note: No new Base is created, all current Base holders 
    /// will have their elastic increase
    public fun increase_elastic(rebase: &mut Rebase, elastic: u64) {
        rebase.elastic = rebase.elastic + elastic;
    }

    /// Subtract only from the elastic part of a rebase
    /// The amount of elastic per base part will decrease
    public fun decrease_elastic(rebase: &mut Rebase, elastic: u64) {
        rebase.elastic = rebase.elastic - elastic;
    }

    /// Subtract an elastic and base from a rebase
    /// The amount of elastic per base part will potentially change
    public fun decrease_elastic_and_base(
        rebase: &mut Rebase,
        elastic: u64,
        base: Base,
    ) {
        let Base { amount } = base;
        rebase.elastic = rebase.elastic - elastic;
        rebase.base = rebase.base - amount;
    }

    /// Returns the amount of base for the given elastic
    /// If the given rebase has no base or elastic, equally
    /// increment the entire rebase by new_elastic.
    public fun elastic_to_base(
        rebase: &Rebase,
        new_elastic: u64,
        round_up: bool
    ): u64 {
        let elastic = rebase.elastic;
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
    public fun base_to_elastic(
        rebase: &Rebase,
        new_base_part: u64,
        round_up: bool
    ): u64 {
        let elastic = rebase.elastic;
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
    const MAX_U64: u128 = 18446744073709551615;

    #[test_only]
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    #[test_only]
    /// Destroy a rebase
    fun destroy(rebase: Rebase) {
        let Rebase { elastic: _, base: _ } = rebase;
    }

    #[test_only]
    /// Destroy an elastic part and get its value
    fun destroy_elastic(elastic: Elastic): u64 {
        let Elastic { amount } = elastic;
        amount
    }

    #[test_only]
    /// Destroy a base part and get its value
    fun destroy_base(base: Base): u64 {
        let Base { amount } = base;
        amount
    }

    #[test]
    fun test_zero_rebase() {
        let Rebase { elastic, base } = zero_rebase();
        assert!(elastic == 0, 1);
        assert!(base == 0, 1);
    }

    #[test]
    fun test_add_elastic() {
        let high_precision: u64 = 100000000000;

        let rebase = Rebase {
            elastic: 1000 * high_precision,
            base: 10 * high_precision
        };

        let base = add_elastic(&mut rebase, 1000 * high_precision, false);

        assert!(destroy_base(base) == 10 * high_precision, 1);

        let Rebase { elastic, base } = rebase;
        assert!(elastic == 2000 * high_precision, 1);
        assert!(base == 20 * high_precision, 1);
    }

    #[test, expected_failure]
    fun test_add_elastic_overflow() {
        let almost_max = ((MAX_U64 - 1) as u64);
        let rebase = Rebase { elastic: almost_max, base: almost_max };
        let base = add_elastic(&mut rebase, 1000, false);
        destroy(rebase);
        destroy_base(base);
    }

    #[test]
    fun test_add_elastic_zero() {

        // ownership is created
        let rebase = zero_rebase();
        let new_base = add_elastic(&mut rebase, 1000, false);

        let Rebase { elastic, base } = rebase;
        assert!(elastic == 1000, 1);
        assert!(base == 1000, 1);
        assert!(destroy_base(new_base) == 1000, 1);

        // there is no ownership of the 1000
        // adding elastic gives ownership but not of the original part
        rebase = Rebase { elastic: 1000, base: 0 };
        new_base = add_elastic(&mut rebase, 1000, false);

        let Rebase { elastic, base } = rebase;
        assert!(elastic == 2000, 1);
        assert!(base == 1000, 1);
        assert!(destroy_base(new_base) == 1000, 1);

        // there was nothing to own
        rebase = Rebase { elastic: 0, base: 1000 };
        let new_base = add_elastic(&mut rebase, 1000, false);

        let Rebase { elastic, base } = rebase;
        assert!(elastic == 1000, 1);
        assert!(base == 2000, 1);
        assert!(destroy_base(new_base) == 1000, 1);
    }

    #[test]
    fun test_sub_base() {
        let rebase = Rebase { elastic: 1000, base: 10 };

        let subbed_elastic = sub_base(&mut rebase, Base { amount: 5 }, false);

        let Rebase { elastic, base } = rebase;
        assert!(elastic == 500, 1);
        assert!(base == 5, 1);
        assert!(subbed_elastic == 500, 1);
    }

    #[test, expected_failure]
    fun test_sub_base_underflow() {
        let rebase = Rebase { elastic: 1000, base: 10 };
        sub_base(&mut rebase, Base { amount: 1000 }, false);
        destroy(rebase);
    }

    #[test]
    fun test_sub_base_zero() {

        // ownership is created
        let rebase = Rebase { elastic: 1000, base: 1000 };
        let subbed_elastic = sub_base(&mut rebase, Base { amount: 1000}, false);

        let Rebase { elastic, base } = rebase;
        assert!(elastic == 0, 1);
        assert!(base == 0, 1);
        assert!(subbed_elastic == 1000, 1);

        // there is no nothing owned
        rebase = Rebase { elastic: 0, base: 1000 };
        let subbed_elastic = sub_base(&mut rebase, Base { amount: 1000 }, false);

        let Rebase { elastic, base } = rebase;
        assert!(elastic == 0, 1);
        assert!(base == 0, 1);
        assert!(subbed_elastic == 0, 1);

        // there are no owners
        rebase = Rebase { elastic: 1000, base: 0 };
        let subbed_elastic = sub_base(&mut rebase, Base { amount: 0 }, false);

        let Rebase { elastic, base } = rebase;
        assert!(elastic == 1000, 1);
        assert!(base == 0, 1);
        assert!(subbed_elastic == 0, 1);
    }

    #[test]
    fun test_add_and_sub() {
        let high_precision: u64 = 10000000000;

        let rebase = Rebase {
            elastic: 1000 * high_precision,
            base: 10 * high_precision
        };

        let new_base = add_elastic(&mut rebase, 1000 * high_precision, false);

        assert!(rebase.elastic == 2000 * high_precision, 1);
        assert!(rebase.base == 20 * high_precision, 1);
        assert!(destroy_base(new_base) == 10 * high_precision, 1);

        let subbed_elastic = sub_base(&mut rebase, Base { amount: 15 * high_precision }, false);

        let Rebase { elastic, base } = rebase;
        assert!(elastic == 500 * high_precision, 1);
        assert!(base == 5 * high_precision, 1);
        assert!(subbed_elastic == 1500 * high_precision, 1);
    }

    #[test]
    fun test_etbte_big() {
        let almost_max = ((MAX_U64 - 1) as u64);
        let rebase = Rebase { elastic: almost_max, base: almost_max };

        let etb = elastic_to_base(&rebase, almost_max, false);
        assert!(etb == almost_max, 1);

        let bte = base_to_elastic(&rebase, etb, false);
        assert!(bte == almost_max, 1);

        destroy(rebase);
    }

    #[test]
    fun test_etbte_from_zero() {
        let rebase = zero_rebase();

        let etb = elastic_to_base(&rebase, 10, false);
        let bte = base_to_elastic(&rebase, etb, false);
        assert!(etb == 10, 1);
        assert!(bte == 10, 1);

        destroy(rebase);

        rebase = zero_rebase();

        etb = elastic_to_base(&rebase, 0, false);
        bte = base_to_elastic(&rebase, etb, false);
        assert!(etb == 0, 1);
        assert!(bte == 0, 1);

        destroy(rebase);
    }

    #[test]
    fun test_increase_elastic() {
        let rebase = Rebase { elastic: 1000, base: 10 };

        let one_part_elastic = base_to_elastic(&rebase, 1, false);
        assert!(one_part_elastic == 100, 1);
        
        increase_elastic(&mut rebase, 1000);

        one_part_elastic = base_to_elastic(&rebase, 1, false);
        assert!(one_part_elastic == 200, 1);

        destroy(rebase);
    }

    #[test]
    fun test_decrease_elastic() {
        let rebase = Rebase { elastic: 5000, base: 10 };

        let one_part_elastic = base_to_elastic(&rebase, 1, false);
        assert!(one_part_elastic == 500, 1);
        
        decrease_elastic(&mut rebase, 1000);

        one_part_elastic = base_to_elastic(&rebase, 1, false);
        assert!(one_part_elastic == 400, 1);

        destroy(rebase);
    }
}
