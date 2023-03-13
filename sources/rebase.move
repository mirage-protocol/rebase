/// Manages elastically rebasing numbers
module rebase::rebase {
    use safe_u64::safe_u64::muldiv_64;

    #[test_only]
    const MAX_U64: u128 = 18446744073709551615;

    #[test_only]
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

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
    public fun get_elastic(rebase: &Rebase): u64 { rebase.elastic }

    /// Get base rebase part
    public fun get_base(rebase: &Rebase): u64 { rebase.base }

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

    /// Add an elastic value into a rebase with new base
    public fun add_elastic(
        rebase: &mut Rebase,
        elastic: u64,
        roundUp: bool
    ): u64 {
        let base = elastic_to_base(rebase, elastic, roundUp);
        rebase.elastic = rebase.elastic + elastic;
        rebase.base = rebase.base + base;
        base
    }

    /// Remove base from a rebase with removed elastic
    public fun sub_base(
        rebase: &mut Rebase,
        base: u64,
        roundUp: bool
    ): u64 {
        let elastic = base_to_elastic(rebase, base, roundUp);
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

    ////////////////////////////////////////////////////////////
    //                        TESTING                         //
    ////////////////////////////////////////////////////////////

    #[test_only]
    fun destroy(rebase: Rebase) {
        let Rebase { elastic: _, base: _ } = rebase;
    }

    #[test]
    fun test_zero_rebase() {
        let Rebase { elastic, base } = zero_rebase();
        assert!(elastic == 0, 1);
        assert!(base == 0, 1);
    }

    #[test]
    fun test_add_elastic() {
        let rebase = Rebase { elastic: 1000, base: 10 };

        add_elastic(&mut rebase, 1000, false);

        let Rebase { elastic, base } = rebase;
        assert!(elastic == 2000, 1);
        assert!(base == 20, 1);
    }

    #[test]
    fun test_sub_base() {
        let rebase = Rebase { elastic: 1000, base: 10 };

        sub_base(&mut rebase, 5, false);

        let Rebase { elastic, base } = rebase;
        assert!(elastic == 500, 1);
        assert!(base == 5, 1);
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

    #[test]
    fun test_update_rebase() {
        let rebase = Rebase { elastic: 50, base: 10 };
        let new = Rebase { elastic: 100, base: 100 };

        update_rebase(&mut rebase, new);

        let Rebase { elastic, base } = rebase;
        assert!(elastic == 100, 1);
        assert!(base == 100, 1);
    }

}
