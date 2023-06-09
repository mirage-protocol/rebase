/// Elastically rebasing numbers
module rebase::rebase {
    use std::error;

    const ENONZERO_DESTRUCTION: u64 = 1;

    /// A rebase has an elastic part and a base part
    ///
    /// The general idea is that the base part represents ownership
    /// over the elastic part, which is a free-floating value
    ///
    /// Ownership value can be calculated as:
    /// base_part * total_elastic / total_base
    /// 
    /// Therefore it is the ratio of the elastic and base that
    /// determines how much one "share" of base is worth.
    ///
    /// In general, rebases will be updated with add_elastic(),
    /// which adds new elastic at the same ratio. This is equivalent
    /// to a new owner "buying in" and the newly created Base
    /// shares must be accounted for.
    ///
    /// When ownership is destroyed, sub_base() is called,
    /// which destroys a Base part and reduces elastic, keeping
    /// the total ratio of the rebase the same. This is equivalent to
    /// an owner taking their elastic out, and renouncing their shares.
    ///
    /// Note: in the above scenarios, the ratio of the rebase is constant
    ///
    /// The functions increase_elastic(), decrease_elastic() modify
    /// the free floating elastic value and will alter the value
    /// of "one share"
    ///
    /// Elastic is more or less a freely modifiable
    /// value, whereas base ownership is tracked and accounted for
    /// with Base
    struct Rebase has store {
        /// The elastic part can change independant of the base
        elastic: u64,
        /// Base parts represent a fixed portion of the elastic
        base: u64,
    }

    /// Represents base ownership of a rebase. Whenever
    /// elastic part is added into a rebase (at a constant ratio),
    /// new Base must be created and accounted for.
    ///
    /// To remove Base from a rebase, Base must
    /// be passed to sub_base()
    struct Base has store {
        /// The amount of base part
        amount: u64,
    }

    /// Get zero rebase
    public fun zero_rebase(): Rebase {
        Rebase { elastic: 0, base: 0 }
    }

    /// Destroy a zero rebase
    public fun destroy_zero(rebase: Rebase) {
        let Rebase { elastic, base } = rebase;
        assert!(elastic == 0 && base == 0, error::invalid_argument(ENONZERO_DESTRUCTION));
    }

    /// Get a zero value base
    public fun zero_base(): Base {
        Base { amount: 0 }
    }

    /// Destroy a zero rebase
    public fun destroy_zero_base(base: Base) {
        let Base { amount } = base;
        assert!(amount == 0, error::invalid_argument(ENONZERO_DESTRUCTION));
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

    spec add_elastic {
        ensures rebase.elastic == old(rebase.elastic) + elastic;
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

    spec sub_base {
        ensures rebase.base == old(rebase.base) - base.amount;
    }

    /// Accepts an elastic amount to sub from a rebase
    /// and a Base to reduce.
    /// Keeps the amount of elastic per base constant
    /// Reduces base_to_reduce and return the reduced amount
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

    spec sub_elastic {
        ensures rebase.elastic == old(rebase.elastic) - elastic;
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
        elastic: u64,
        round_up: bool
    ): u64 {
        // if elastic = 0 and base > 0 we want to create new base, note in that situation
        // the one "buying in" will be giving away some ownership to exisiting Base
        // if elastic > 0 and base = 0, we want to create a new base part and assign existing
        // elastic to it. In either instance the result is the same:
        if (rebase.elastic == 0 || rebase.base == 0) {
            elastic
        } else {
            let new_base_part = ((elastic as u128) * (rebase.base as u128) / (rebase.elastic as u128) as u64);
            if (
                round_up &&
                new_base_part != 0 &&
                ((new_base_part as u128) * (rebase.elastic as u128) / (rebase.base as u128) as u64) < elastic
            ) {
                new_base_part + 1
            } else {
                new_base_part
            }
        }
    }

    /// Returns the amount of elastic for the given base
    /// If the given rebase has no base or elastic, equally
    /// increment the entire rebase by new_base_part.
    public fun base_to_elastic(
        rebase: &Rebase,
        base: u64,
        round_up: bool
    ): u64 {
        // if elastic is 0 the result should clearly be 0
        // if base is 0 we add new ownership
        if (rebase.base == 0) {
            base
        } else {
            let new_elastic = ((base as u128) * (rebase.elastic as u128) / (rebase.base as u128) as u64);
            if (
                round_up &&
                new_elastic != 0 && // => rebase.elastic > 0
                ((new_elastic as u128) * (rebase.base as u128) / (rebase.elastic as u128) as u64) < base
            ) {
                new_elastic + 1
            } else {
                new_elastic
            }
        }
    }

    ////////////////////////////////////////////////////////////
    //                        TESTING                         //
    ////////////////////////////////////////////////////////////

    #[test_only]
    const MAX_U64: u64 = 18446744073709551615;

    #[test_only]
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    #[test_only]
    /// Destroy a rebase
    fun destroy(rebase: Rebase) {
        let Rebase { elastic: _, base: _ } = rebase;
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

    #[test]
    #[expected_failure(arithmetic_error, location = Self)]
    fun test_add_elastic_overflow() {
        let almost_max = MAX_U64 - 1;
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

    #[test]
    #[expected_failure(arithmetic_error, location = Self)]
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
