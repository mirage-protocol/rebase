/// A rebase that stores FungibleAssets
module rebase::fungible_asset_rebase {
    use std::signer;
    use std::object::{Self, Object, ConstructorRef};

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::fungible_asset::{Self, FungibleStore, FungibleAsset, Metadata};
    use aptos_framework::resource_account;

    // base isn't owned by rebase
    const EDIFFERENT_REBASE: u64 = 0;
    const EDIFFERENT_METADATA: u64 = 1;
    const EINVALID_OWNER: u64 = 2;

    /// A rebase with elastic specifically designated as a Coins
    struct FungibleAssetRebase has key {
        /// The elastic part can change independant of the base
        elastic: Object<FungibleStore>,
        /// Base parts represent a fixed portion of the elastic
        base: u64,
    }

    /// Represents base ownership of a rebase
    struct Base has key {
        /// The amount of base part
        amount: u64,
    }

    // Stores permission config such as SignerCapability for controlling the resource account.
    struct PermissionConfig has key {
        // Required to obtain the resource account signer.
        signer_cap: SignerCapability,
   }

    // Initialize PermissionConfig to establish control over the resource account.
    // This function is invoked only when this package is deployed the first time.
    fun init_module(account: &signer) {
        let signer_cap = resource_account::retrieve_resource_account_cap(account, @deployer);
        move_to(account, PermissionConfig {
            signer_cap,
        });
    }

    /// Get zero rebase
    public fun zero_rebase<T: key>(
        constructor_ref: &ConstructorRef,
        metadata: Object<T>
    ): Object<FungibleAssetRebase> {
        let rebase_signer = &object::generate_signer(constructor_ref);
        move_to(rebase_signer, FungibleAssetRebase {
            elastic: fungible_asset::create_store(constructor_ref, metadata),
            base: 0
        });
        object::object_from_constructor_ref(constructor_ref)
    }

    /// Get a zero value base
    public fun zero_base(rebase: Object<FungibleAssetRebase>): Object<Base> {
        create_base(rebase, 0)
    }

    /// Get a new base
    fun create_base(rebase: Object<FungibleAssetRebase>, amount: u64): Object<Base> {
        let constructor_ref = object::create_object(object::object_address(&rebase));
        let base_signer = &object::generate_signer(&constructor_ref);
        // base object is owned by rebase object
        move_to(base_signer, Base { amount } );
        object::object_from_constructor_ref(&constructor_ref)
    }

    public fun rebase_metadata(rebase: Object<FungibleAssetRebase>): Object<Metadata> acquires FungibleAssetRebase {
        let elastic = borrow_global<FungibleAssetRebase>(object::object_address(&rebase)).elastic;
        fungible_asset::store_metadata(elastic)
    }

    public fun base_metadata(base: Object<Base>): Object<Metadata> acquires FungibleAssetRebase {
        let rebase = object::owner(base);
        rebase_metadata(object::address_to_object(rebase))
    }

    /// Merge two base
    public fun merge_base(dst_obj: Object<Base>, src_obj: Object<Base>) acquires Base {
        assert!(object::owner(dst_obj) == object::owner(src_obj), EDIFFERENT_REBASE);

        let Base { amount: src_amount } = move_from(object::object_address(&src_obj));
        let dst_base = borrow_global_mut<Base>(object::object_address(&dst_obj));
        dst_base.amount = dst_base.amount + src_amount;
    }

    /// Extract from a base
    public fun extract_base(dst_obj: Object<Base>, amount: u64): Object<Base> acquires Base {
        let dst_base = borrow_global_mut<Base>(object::object_address(&dst_obj));

        let new_obj = create_base(object::address_to_object(object::owner(dst_obj)), amount);
        dst_base.amount = dst_base.amount - amount;

        new_obj
    }

    /// Extract all from Base
    public fun extract_all_base(dst_obj: Object<Base>): Object<Base> acquires Base {
        let dst_base = borrow_global_mut<Base>(object::object_address(&dst_obj));

        let amount = dst_base.amount;
        dst_base.amount = 0;

        let rebase = object::address_to_object(object::owner(dst_obj));
        create_base(rebase, amount)
    }

    /// Get the amount in a Base
    public fun get_base_amount(base_obj: Object<Base>): u64 acquires Base {
        let base = borrow_global_mut<Base>(object::object_address(&base_obj));
        base.amount
    }

    /// Get elastic rebase part
    public fun get_elastic(rebase_obj: Object<FungibleAssetRebase>): u64 acquires FungibleAssetRebase {
        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));
        fungible_asset::balance(rebase.elastic)
    }

    /// Get base rebase part
    public fun get_base(rebase_obj: Object<FungibleAssetRebase>): u64 acquires FungibleAssetRebase {
        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));
        rebase.base
    }

    /// Add elastic to a rebase
    /// Keeps the amount of elastic per base constant
    /// Returns the newly created Base
    public fun add_elastic(
        rebase_obj: Object<FungibleAssetRebase>,
        elastic: FungibleAsset,
        round_up: bool
    ): Object<Base> acquires FungibleAssetRebase {
        let metadata = rebase_metadata(rebase_obj);
        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));
        assert!(metadata == fungible_asset::store_metadata(rebase.elastic), EDIFFERENT_METADATA);

        let base = elastic_to_base(rebase, fungible_asset::amount(&elastic), round_up);
        fungible_asset::deposit(
            rebase.elastic,
            elastic
        );
        rebase.base = rebase.base + base;
        create_base(rebase_obj, base)
    }

    /// Accepts Base to sub from a rebase
    /// Keeps the amount of elastic per base constant
    /// Returns the elastic that was removed
    public fun sub_base(
        rebase_obj: Object<FungibleAssetRebase>,
        base_obj: Object<Base>,
        round_up: bool
    ): FungibleAsset acquires Base, FungibleAssetRebase, PermissionConfig {
        assert!(object::object_address(&rebase_obj) == object::owner(base_obj), EDIFFERENT_REBASE);

        let Base { amount } = move_from<Base>(object::object_address(&base_obj));
        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));
        let elastic = base_to_elastic(rebase, amount, round_up);
        rebase.base = rebase.base - amount;
        let rebase_signer = account::create_signer_with_capability(
            &borrow_global<PermissionConfig>(@rebase).signer_cap
        );

        fungible_asset::withdraw(
            &rebase_signer, 
            rebase.elastic,
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
    public fun sub_elastic(
        rebase_obj: Object<FungibleAssetRebase>,
        base_to_reduce_obj: Object<Base>,
        elastic: u64,
        round_up: bool
    ): (u64, FungibleAsset) acquires Base, FungibleAssetRebase, PermissionConfig {
        assert!(object::owner(base_to_reduce_obj) == object::object_address(&rebase_obj), EDIFFERENT_REBASE);

        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));
        let base_to_reduce = borrow_global_mut<Base>(object::object_address(&base_to_reduce_obj));

        let base = elastic_to_base(rebase, elastic, round_up);
        rebase.base = rebase.base - base;
        base_to_reduce.amount = base_to_reduce.amount - base;

        let rebase_signer = account::create_signer_with_capability(
            &borrow_global<PermissionConfig>(@rebase).signer_cap
        );
        (
            base,
            fungible_asset::withdraw(
                &rebase_signer,
                rebase.elastic,
                elastic
            )
        )
    }

    /// Add only to the elastic part of a rebase
    /// The amount of elastic per base part will increase
    ///
    /// Note: No new Base is created, all current Base holders 
    /// will have their elastic increase
    public fun increase_elastic(
        owner: &signer,
        rebase_obj: Object<FungibleAssetRebase>,
        elastic: FungibleAsset,
    ) acquires FungibleAssetRebase {
        assert!(object::owner(rebase_obj) == signer::address_of(owner), EINVALID_OWNER);

        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));
        fungible_asset::deposit(
            rebase.elastic,
            elastic
        )
    }

    /// Remove only from the elastic part of a rebase
    /// The amount of elastic per base part will decrease
    public fun decrease_elastic(
        owner: &signer,
        rebase_obj: Object<FungibleAssetRebase>,
        elastic: u64
    ): FungibleAsset acquires FungibleAssetRebase, PermissionConfig {
        assert!(object::owner(rebase_obj) == signer::address_of(owner), EINVALID_OWNER);
        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));

        let rebase_signer = account::create_signer_with_capability(
            &borrow_global<PermissionConfig>(@rebase).signer_cap
        );
        fungible_asset::withdraw(
            &rebase_signer,
            rebase.elastic,
            elastic
        )
    }

    /// Remove elastic and base from a rebase
    /// The amount of elastic per base part will potentially change
    public fun decrease_elastic_and_base(
        owner: &signer,
        rebase_obj: Object<FungibleAssetRebase>,
        elastic: u64,
        base_obj: Object<Base>,
    ): FungibleAsset acquires Base, FungibleAssetRebase {
        assert!(object::owner(rebase_obj) == signer::address_of(owner), EINVALID_OWNER);
        assert!(object::owner(base_obj) == object::object_address(&rebase_obj), EDIFFERENT_REBASE);

        let Base { amount } = move_from<Base>(object::object_address(&base_obj));
        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));
        rebase.base = rebase.base - amount;
        fungible_asset::withdraw(
            owner,
            rebase.elastic,
            elastic,
        )
    }

    /// Returns the amount of base for the given elastic
    /// If the given rebase has no base or elastic, equally
    /// increment the entire rebase by new_elastic.
    public fun elastic_to_base(
        rebase: &FungibleAssetRebase,
        elastic: u64,
        round_up: bool
    ): u64 {
        let global_elastic = fungible_asset::balance(rebase.elastic);

        if (global_elastic == 0 || rebase.base == 0) {
            elastic
        } else {
            let new_base_part = ((elastic as u128) * (rebase.base as u128) / (global_elastic as u128) as u64);
            if (
                round_up &&
                new_base_part != 0 &&
                ((new_base_part as u128) * (global_elastic as u128) / (rebase.base as u128) as u64) < elastic
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
        rebase: &FungibleAssetRebase,
        base: u64,
        round_up: bool
    ): u64 {
        let elastic = fungible_asset::balance(rebase.elastic);

        if (rebase.base == 0) {
            base
        } else {
            let new_elastic = ((base as u128) * (elastic as u128) / (rebase.base as u128) as u64);
            if (
                round_up &&
                new_elastic != 0 &&
                ((new_elastic as u128) * (rebase.base as u128) / (elastic as u128) as u64) < base
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
    use std::string;

    #[test_only]
    use std::option;

    #[test_only]
    const PRECISION_8: u64 = 100000000;

    #[test_only]
    const MAX_U64: u128 = 18446744073709551615;

    #[test_only]
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    #[test_only]
    struct FakeFungibleAssetRefs has key {
        mint_ref: fungible_asset::MintRef,
        transfer_ref: fungible_asset::TransferRef,
        burn_ref: fungible_asset::BurnRef,
        metadata: Object<Metadata>,
        store: Object<FungibleStore>,
    }


    #[test_only]
    public entry fun create_fake_fungible_asset(
        account: &signer,
        amount: u64
    ): FungibleAsset {
        let (constructor_ref, token_object) = fungible_asset::create_test_token(account);
        fungible_asset::add_fungibility(
            &constructor_ref,
            option::none(),
            string::utf8(b"TEST"),
            string::utf8(b"@@"),
            0,
            string::utf8(b"http://www.example.com/favicon.ico"),
            string::utf8(b"http://www.example.com"),
        );
        let mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(&constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(&constructor_ref);

        let metadata = object::convert(token_object);
        let mint = fungible_asset::mint(&mint_ref, amount);
        move_to(account, FakeFungibleAssetRefs {
            mint_ref,
            transfer_ref,
            burn_ref,
            metadata,
            store: fungible_asset::create_test_store(account, metadata),
        });

        mint
    }

    #[test_only]
    /// Destroy a base part and get its value
    fun destroy_base(base: Object<Base>): u64 acquires Base {
        let Base { amount } = move_from<Base>(object::object_address(&base));
        amount
    }

    #[test(account = @rebase)]
    fun test_zero_rebase(account: &signer) acquires FungibleAssetRebase, FakeFungibleAssetRefs {
        let fa = create_fake_fungible_asset(account, 100 * PRECISION_8);
        let metadata = borrow_global<FakeFungibleAssetRefs>(signer::address_of(account)).metadata;

        let constructor_ref = object::create_object(signer::address_of(account));
        let rebase = zero_rebase(&constructor_ref, metadata);
        assert!(get_elastic(rebase) == 0, 1);
        assert!(get_base(rebase) == 0, 1);

        // kill fa
        let store = borrow_global<FakeFungibleAssetRefs>(signer::address_of(account)).store;
        fungible_asset::deposit(store, fa);
    }

    #[test(account = @rebase)]
    fun test_add_elastic(account: &signer) acquires Base, FungibleAssetRebase, FakeFungibleAssetRefs {
        let fa = create_fake_fungible_asset(account, 100 * PRECISION_8);
        let metadata = borrow_global<FakeFungibleAssetRefs>(signer::address_of(account)).metadata;

        let constructor_ref = object::create_object(signer::address_of(account));
        let rebase = zero_rebase(&constructor_ref, metadata);
        let base = add_elastic(rebase, fa, false);

        assert!(get_base_amount(base) == 100 * PRECISION_8, 1);

        destroy_base(base);

        assert!(get_elastic(rebase) == 100 * PRECISION_8, 1);
        assert!(get_base(rebase) == 100 * PRECISION_8, 1);
   }

    #[test(account = @rebase)]
    fun test_sub_base(account: &signer) acquires Base, FungibleAssetRebase, FakeFungibleAssetRefs, PermissionConfig {
        let fa = create_fake_fungible_asset(account, 100 * PRECISION_8);
        let metadata = borrow_global<FakeFungibleAssetRefs>(signer::address_of(account)).metadata;

        let constructor_ref = object::create_object(signer::address_of(account));
        let rebase = zero_rebase(&constructor_ref, metadata);
        let base = add_elastic(rebase, fa, false);

        let half_base = extract_base(
            base,
            50 * PRECISION_8
        );

        destroy_base(base);

        let elastic = sub_base(rebase, half_base, false);

        assert!(fungible_asset::amount(&elastic) == 50 * PRECISION_8, 1);
        assert!(get_base_amount(base) == 50 * PRECISION_8, 1);
        assert!(get_elastic(rebase) == 50 * PRECISION_8, 1);

        // kill fa
        let store = borrow_global<FakeFungibleAssetRefs>(signer::address_of(account)).store;
        fungible_asset::deposit(store, elastic);
    }

    #[test(account = @rebase)]
    fun test_increase_elastic(account: &signer) acquires FakeFungibleAssetRefs, FungibleAssetRebase {
        let fa = create_fake_fungible_asset(account, 100 * PRECISION_8);
        let metadata = borrow_global<FakeFungibleAssetRefs>(signer::address_of(account)).metadata;

        let constructor_ref = object::create_object(signer::address_of(account));
        let rebase = zero_rebase(&constructor_ref, metadata);

        increase_elastic(account, rebase, fa);

        assert!(get_elastic(rebase) == 100 * PRECISION_8, 1);
        assert!(get_base(rebase) == 0, 1);
    }

    #[test(account = @rebase)]
    fun test_decrease_elastic(account: &signer) acquires FungibleAssetRebase, FakeFungibleAssetRefs, PermissionConfig {
        let fa = create_fake_fungible_asset(account, 100 * PRECISION_8);
        let metadata = borrow_global<FakeFungibleAssetRefs>(signer::address_of(account)).metadata;

        let constructor_ref = object::create_object(signer::address_of(account));
        let rebase = zero_rebase(&constructor_ref, metadata);

        increase_elastic(account, rebase, fa);

        let removed_coin = decrease_elastic(account, rebase, 50 * PRECISION_8);

        assert!(fungible_asset::amount(&removed_coin) == 50 * PRECISION_8, 1);
        assert!(get_elastic(rebase) == 50 * PRECISION_8, 1);
        assert!(get_base(rebase) == 0, 1);

        // kill fa
        let store = borrow_global<FakeFungibleAssetRefs>(signer::address_of(account)).store;
        fungible_asset::deposit(store, removed_coin);
    }
}