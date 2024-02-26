/// A rebase that stores FungibleAssets
module rebase::fungible_asset_rebase {
    use std::error;
    use std::object::{Self, Object, DeleteRef};
    use std::signer;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::fungible_asset::{Self, FungibleStore, FungibleAsset, Metadata};
    use aptos_framework::resource_account;

    // base isn't owned by rebase
    const EDIFFERENT_REBASE: u64 = 0;
    const ENOT_OWNER: u64 = 2;
    const ENONZERO_DESTRUCTION: u64 = 3;

    /// A rebase with elastic specifically designated as a Coins
    struct FungibleAssetRebase has key {
        /// The elastic part can change independent of the base
        elastic: Object<FungibleStore>,
        /// Base parts represent a fixed portion of the elastic
        base: u64,
        /// DeleteRef for cleaning up object
        delete_ref: DeleteRef,
        /// address of FA rebase owner
        owner_addr: address
    }

    /// Represents base ownership of a rebase
    struct Base has key {
        rebase: Object<FungibleAssetRebase>,
        /// The amount of base part
        amount: u64,
        /// DeleteRef for cleaning up object
        delete_ref: DeleteRef,
 
    }

    // Stores permission config such as SignerCapability for controlling the resource account.
    struct PermissionConfig has key {
        // Required to obtain the resource account signer.
        signer_cap: SignerCapability,
   }

    // Initialize PermissionConfig to establish control over the resource account.
    // This function is invoked only when this package is deployed the first time.
    fun init_module(account: &signer) {
        let signer_cap = resource_account::retrieve_resource_account_cap(account, @protocol_deployer);
        move_to(account, PermissionConfig {
            signer_cap,
        });
    }

    fun assert_base_owner(base_obj: Object<Base>, account: &signer) acquires Base, FungibleAssetRebase {
        let base = borrow_global<Base>(object::object_address(&base_obj));
        let fa_rebase = borrow_global<FungibleAssetRebase>(object::object_address(&base.rebase));
        assert!(fa_rebase.owner_addr == signer::address_of(account), ENOT_OWNER);
    }

    fun assert_fa_rebase_owner(rebase_obj: Object<FungibleAssetRebase>, account: &signer) acquires FungibleAssetRebase {
        let owner_addr = borrow_global<FungibleAssetRebase>(object::object_address(&rebase_obj)).owner_addr;
        assert!(owner_addr == signer::address_of(account), ENOT_OWNER);
    }

    /// Get zero rebase
    public fun zero_rebase<T: key>(
        owner: address,
        metadata: Object<T>
    ): Object<FungibleAssetRebase> {
        let constructor_ref = object::create_object(@rebase);
        let rebase_signer = object::generate_signer(&constructor_ref);
        move_to(&rebase_signer, FungibleAssetRebase {
            elastic: fungible_asset::create_store(&constructor_ref, metadata),
            base: 0,
            delete_ref: object::generate_delete_ref(&constructor_ref),
            owner_addr: owner,
        });
        let rebase_obj = object::object_from_constructor_ref<FungibleAssetRebase>(&constructor_ref);
        rebase_obj
    }

    public fun destroy_zero(
        owner: &signer,
        rebase_obj: Object<FungibleAssetRebase>
    ) acquires FungibleAssetRebase {
        assert_fa_rebase_owner(rebase_obj, owner);
        let FungibleAssetRebase {
            elastic,
            base,
            delete_ref,
            owner_addr: _,
        } = move_from<FungibleAssetRebase>(object::object_address(&rebase_obj));
        // rebase must have zero balance
        assert!(fungible_asset::balance(elastic) == 0 && base == 0, error::invalid_argument(ENONZERO_DESTRUCTION));
        // remove store
        fungible_asset::remove_store(&delete_ref);
        // delete object
        object::delete(delete_ref)
    }

    public fun destroy_zero_base(
        owner: &signer,
        base_obj: Object<Base>
    )  acquires Base, FungibleAssetRebase  {
        assert_base_owner(base_obj, owner);
        let Base { rebase: _, amount, delete_ref } = move_from<Base>(object::object_address(&base_obj));
        assert!(amount == 0, error::invalid_argument(ENONZERO_DESTRUCTION));
        // delete object
        object::delete(delete_ref)
    }

    /// Get a zero value base
    public fun zero_base(
        owner: &signer,
        rebase_obj: Object<FungibleAssetRebase>
    ): Object<Base> acquires FungibleAssetRebase {
        assert_fa_rebase_owner(rebase_obj, owner);
        create_base(owner, rebase_obj, 0)
    }

    /// Get a new base
    fun create_base(
        owner: &signer,
        rebase_obj: Object<FungibleAssetRebase>,
        amount: u64
    ): Object<Base> acquires FungibleAssetRebase {
        assert_fa_rebase_owner(rebase_obj, owner);

        let constructor_ref = object::create_object(@rebase);
        let base_signer = object::generate_signer(&constructor_ref);

        // base object is owned by rebase
        move_to(&base_signer, Base {
            rebase: rebase_obj,
            amount,
            delete_ref: object::generate_delete_ref(&constructor_ref),
        } );
        object::object_from_constructor_ref(&constructor_ref)
    }

    #[view]
    public fun rebase_metadata(rebase_obj: Object<FungibleAssetRebase>): Object<Metadata> acquires FungibleAssetRebase {
        let elastic = borrow_global<FungibleAssetRebase>(object::object_address(&rebase_obj)).elastic;
        fungible_asset::store_metadata(elastic)
    }

    #[view]
    public fun base_metadata(base: Object<Base>): Object<Metadata> acquires FungibleAssetRebase {
        let rebase = object::owner(base);
        rebase_metadata(object::address_to_object(rebase))
    }

    /// Merge two base
    public fun merge_base(
        owner: &signer,
        dst_obj: Object<Base>,
        src_obj: Object<Base>
    )  acquires Base, FungibleAssetRebase {
        assert_base_owner(dst_obj, owner);
        assert_base_owner(src_obj, owner);

        let Base { rebase: src_rebase, amount: src_amount, delete_ref: _ } = move_from(object::object_address(&src_obj));
        let dst_base = borrow_global_mut<Base>(object::object_address(&dst_obj));
        assert!(dst_base.rebase == src_rebase, EDIFFERENT_REBASE);
        dst_base.amount = dst_base.amount + src_amount;
    }

    /// Extract from a base
    public fun extract_base(
        owner: &signer,
        dst_obj: Object<Base>,
        amount: u64
    ): Object<Base>  acquires Base, FungibleAssetRebase {
        assert_base_owner(dst_obj, owner);

        let dst_base = borrow_global_mut<Base>(object::object_address(&dst_obj));

        let new_obj = create_base(owner, dst_base.rebase, amount);
        dst_base.amount = dst_base.amount - amount;

        new_obj
    }

    /// Extract all from Base
    public fun extract_all_base(
        owner: &signer,
        dst_obj: Object<Base>
    ): Object<Base>  acquires Base, FungibleAssetRebase {
        assert_base_owner(dst_obj, owner);
        let dst_base = borrow_global_mut<Base>(object::object_address(&dst_obj));

        let amount = dst_base.amount;
        dst_base.amount = 0;

        create_base(owner, dst_base.rebase, amount)
    }

    #[view]
    /// Get the amount in a Base
    public fun get_base_amount(base_obj: Object<Base>): u64 acquires Base {
        let base = borrow_global_mut<Base>(object::object_address(&base_obj));
        base.amount
    }

    #[view]
    /// Get elastic rebase part
    public fun get_elastic(rebase_obj: Object<FungibleAssetRebase>): u64 acquires FungibleAssetRebase {
        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));
        fungible_asset::balance(rebase.elastic)
    }

    #[view]
    /// Get base rebase part
    public fun get_base(rebase_obj: Object<FungibleAssetRebase>): u64 acquires FungibleAssetRebase {
        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));
        rebase.base
    }

    #[view]
    /// Get the base's rebase
    public fun get_rebase(base_obj: Object<Base>): Object<FungibleAssetRebase> acquires Base {
        let base = borrow_global_mut<Base>(object::object_address(&base_obj));
        base.rebase
    }

    /// Add elastic to a rebase
    /// Keeps the amount of elastic per base constant
    /// Returns the newly created Base
    public fun add_elastic(
        owner: &signer,
        rebase_obj: Object<FungibleAssetRebase>,
        elastic: FungibleAsset,
        round_up: bool
    ): Object<Base> acquires FungibleAssetRebase {
        assert_fa_rebase_owner(rebase_obj, owner);
        assert!(rebase_metadata(rebase_obj) == fungible_asset::metadata_from_asset(&elastic), EDIFFERENT_REBASE);

        let base = elastic_to_base(rebase_obj, fungible_asset::amount(&elastic), round_up);
        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));
        fungible_asset::deposit(
            rebase.elastic,
            elastic
        );
        rebase.base = rebase.base + base;
        create_base(owner, rebase_obj, base)
    }

    /// Accepts Base to sub from a rebase
    /// Keeps the amount of elastic per base constant
    /// Returns the elastic that was removed
    public fun sub_base(
        owner: &signer,
        base_obj: Object<Base>,
        round_up: bool
    ): FungibleAsset acquires Base, FungibleAssetRebase, PermissionConfig {
        assert_base_owner(base_obj, owner);

        let Base { rebase: rebase_obj, amount, delete_ref: _, } = move_from<Base>(object::object_address(&base_obj));
        let elastic = base_to_elastic(rebase_obj, amount, round_up);
        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));

        rebase.base = rebase.base - amount;
        fungible_asset::withdraw(
            &get_signer(), 
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
        owner: &signer,
        base_to_reduce_obj: Object<Base>,
        elastic: u64,
        round_up: bool
    ): (u64, FungibleAsset) acquires Base, FungibleAssetRebase, PermissionConfig {
        assert_base_owner(base_to_reduce_obj, owner);

        let base_to_reduce = borrow_global_mut<Base>(object::object_address(&base_to_reduce_obj));
        let base = elastic_to_base(base_to_reduce.rebase, elastic, round_up);

        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&base_to_reduce.rebase));
        rebase.base = rebase.base - base;
        base_to_reduce.amount = base_to_reduce.amount - base;

        (
            base,
            fungible_asset::withdraw(
                &get_signer(),
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
        assert_fa_rebase_owner(rebase_obj, owner);

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
        assert_fa_rebase_owner(rebase_obj, owner);
        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));

        fungible_asset::withdraw(
            &get_signer(),
            rebase.elastic,
            elastic
        )
    }

    /// Remove elastic and base from a rebase
    /// The amount of elastic per base part will potentially change
    public fun decrease_elastic_and_base(
        owner: &signer,
        elastic: u64,
        base_obj: Object<Base>,
    ): FungibleAsset acquires Base, FungibleAssetRebase, PermissionConfig {
        assert_base_owner(base_obj, owner);

        let Base { rebase: rebase_obj, amount, delete_ref: _ } = move_from<Base>(object::object_address(&base_obj));
        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));
        rebase.base = rebase.base - amount;
        fungible_asset::withdraw(
            &get_signer(),
            rebase.elastic,
            elastic,
        )
    }

    #[view]
    /// Returns the amount of base for the given elastic
    /// If the given rebase has no base or elastic, equally
    /// increment the entire rebase by new_elastic.
    public fun elastic_to_base(
        rebase_obj: Object<FungibleAssetRebase>,
        elastic: u64,
        round_up: bool
    ): u64 acquires FungibleAssetRebase {
        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));
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

    #[view]
    /// Returns the amount of elastic for the given base
    /// If the given rebase has no base or elastic, equally
    /// increment the entire rebase by new_base_part.
    public fun base_to_elastic(
        rebase_obj: Object<FungibleAssetRebase>,
        base: u64,
        round_up: bool
    ): u64 acquires FungibleAssetRebase {
        let rebase = borrow_global_mut<FungibleAssetRebase>(object::object_address(&rebase_obj));
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

    fun get_signer(): signer acquires PermissionConfig {
        account::create_signer_with_capability(
            &borrow_global<PermissionConfig>(@rebase).signer_cap
        )
    }

    ////////////////////////////////////////////////////////////
    //                        TESTING                         //
    ////////////////////////////////////////////////////////////
    #[test_only]
    use std::string;

    #[test_only]
    use std::option::{Self, Option};

    #[test_only]
    use aptos_framework::primary_fungible_store;

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
        other_metadata: Option<Object<Metadata>>,
        other_store: Option<Object<FungibleStore>>,
    }


    #[test_only]
    public entry fun create_fake_fungible_asset(
        account: &signer,
        amount: u64
    ): FungibleAsset {
        initialize_for_test(account);

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
            other_metadata: option::none(),
            other_store: option::none(),
        });

        mint
    }

    #[test_only]
    public entry fun create_fake_fungible_assets(
        account: &signer,
        amount: u64
    ): (FungibleAsset) {
        initialize_for_test(account);

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
        let metadata = object::convert(token_object);

        let constructor_ref_2 = object::create_named_object(
            account,
            b"YOLO"
        );

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref_2,
            option::none(),
            string::utf8(b"YOLO"),
            string::utf8(b"XXX"),
            0,
            string::utf8(b"http://www.fail.com/favicon.ico"),
            string::utf8(b"http://www.fail.com"),
        );

        let mint_ref = fungible_asset::generate_mint_ref(&constructor_ref_2);
        let burn_ref = fungible_asset::generate_burn_ref(&constructor_ref_2);
        let transfer_ref = fungible_asset::generate_transfer_ref(&constructor_ref_2);
        

        let metadata_2 = object::object_from_constructor_ref<Metadata>(&constructor_ref_2);
        let mint_2 = fungible_asset::mint(&mint_ref, amount);
        
        move_to(account, FakeFungibleAssetRefs {
            mint_ref,
            transfer_ref,
            burn_ref,
            metadata,
            store: fungible_asset::create_test_store(account, metadata),
            other_metadata: option::some(metadata_2),
            other_store: option::some(fungible_asset::create_test_store(account, metadata_2))
        });

        (mint_2)
    }

    #[test_only]
    /// Destroy a base part and get its value
    fun destroy_base(base: Object<Base>): u64 acquires Base {
        let Base { rebase: _, amount, delete_ref } = move_from<Base>(object::object_address(&base));
        object::delete(delete_ref);
        amount
    }

    #[test(rebase_module = @rebase, user = @0xcafe)]
    fun test_zero_rebase(rebase_module: &signer, user: &signer) acquires FungibleAssetRebase, FakeFungibleAssetRefs {
        let fa = create_fake_fungible_asset(rebase_module, 100 * PRECISION_8);
        let metadata = borrow_global<FakeFungibleAssetRefs>(@rebase).metadata;

        let rebase = zero_rebase(signer::address_of(user), metadata);
        assert!(get_elastic(rebase) == 0, 1);
        assert!(get_base(rebase) == 0, 1);

        // kill fa
        let store = borrow_global<FakeFungibleAssetRefs>(@rebase).store;
        fungible_asset::deposit(store, fa);
    }

    #[test(rebase_module = @rebase, user = @0xcafe)]
    fun test_add_elastic(rebase_module: &signer, user: &signer) acquires Base, FungibleAssetRebase, FakeFungibleAssetRefs {
        let fa = create_fake_fungible_asset(rebase_module, 100 * PRECISION_8);
        let metadata = borrow_global<FakeFungibleAssetRefs>(@rebase).metadata;

        let rebase = zero_rebase(signer::address_of(user), metadata);
        let base = add_elastic(user, rebase, fa, false);

        assert!(get_base_amount(base) == 100 * PRECISION_8, 1);

        destroy_base(base);

        assert!(get_elastic(rebase) == 100 * PRECISION_8, 1);
        assert!(get_base(rebase) == 100 * PRECISION_8, 1);
   }

    #[test(rebase_module = @rebase, user = @0xcafe)]
    #[expected_failure(abort_code = 0, location = rebase::fungible_asset_rebase)]
    fun test_add_elastic_different_rebase(rebase_module: &signer, user: &signer) acquires FungibleAssetRebase, FakeFungibleAssetRefs {
        let fa2 = create_fake_fungible_assets(rebase_module, 100 * PRECISION_8);
        let metadata = borrow_global<FakeFungibleAssetRefs>(@rebase).metadata;

        let rebase = zero_rebase(signer::address_of(user), metadata);
        add_elastic(user, rebase, fa2, false);
   }

    #[test(rebase_module = @rebase, user = @0xcafe)]
    fun test_sub_base(rebase_module: &signer, user: &signer) acquires Base, FungibleAssetRebase, FakeFungibleAssetRefs, PermissionConfig {
        let fa = create_fake_fungible_asset(rebase_module, 100 * PRECISION_8);
        let metadata = borrow_global<FakeFungibleAssetRefs>(@rebase).metadata;

        let rebase = zero_rebase(signer::address_of(user), metadata);
        let base = add_elastic(user, rebase, fa, false);

        let half_base = extract_base(
            user,
            base,
            50 * PRECISION_8
        );

        destroy_base(base);

        let elastic = sub_base(user, half_base, false);

        assert!(fungible_asset::amount(&elastic) == 50 * PRECISION_8, 1);
        assert!(get_base(rebase) == 50 * PRECISION_8, 1);
        assert!(get_elastic(rebase) == 50 * PRECISION_8, 1);

        // kill fa
        let store = borrow_global<FakeFungibleAssetRefs>(@rebase).store;
        fungible_asset::deposit(store, elastic);
    }

    #[test(rebase_module = @rebase, user = @0xcafe)]
    fun test_increase_elastic(rebase_module: &signer, user: &signer) acquires FakeFungibleAssetRefs, FungibleAssetRebase {
        let fa = create_fake_fungible_asset(rebase_module, 100 * PRECISION_8);
        let metadata = borrow_global<FakeFungibleAssetRefs>(@rebase).metadata;

        let rebase = zero_rebase(signer::address_of(user), metadata);

        increase_elastic(user, rebase, fa);

        assert!(get_elastic(rebase) == 100 * PRECISION_8, 1);
        assert!(get_base(rebase) == 0, 1);
    }

    #[test(rebase_module = @rebase, user = @0xcafe)]
    fun test_decrease_elastic(rebase_module: &signer, user: &signer) acquires FungibleAssetRebase, FakeFungibleAssetRefs, PermissionConfig {
        let fa = create_fake_fungible_asset(rebase_module, 100 * PRECISION_8);
        let metadata = borrow_global<FakeFungibleAssetRefs>(@rebase).metadata;

        let rebase = zero_rebase(signer::address_of(user), metadata);

        increase_elastic(user, rebase, fa);

        let removed_coin = decrease_elastic(user, rebase, 50 * PRECISION_8);

        assert!(fungible_asset::amount(&removed_coin) == 50 * PRECISION_8, 1);
        assert!(get_elastic(rebase) == 50 * PRECISION_8, 1);
        assert!(get_base(rebase) == 0, 1);

        // kill fa
        let store = borrow_global<FakeFungibleAssetRefs>(@rebase).store;
        fungible_asset::deposit(store, removed_coin);
    }

    #[test_only]
    public fun initialize_for_test(rebase_account: &signer) {
        let rebase_addr = std::signer::address_of(rebase_account);
        if (!exists<PermissionConfig>(rebase_addr)) {
            move_to(rebase_account, PermissionConfig {
                signer_cap: account::create_test_signer_cap(rebase_addr),
            });
        };
    }
}
