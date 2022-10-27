module Multichain::Pool {
    use std::string::String;
    use std::signer;
    use std::error;
    use aptos_framework::coin::{Self, BurnCapability, MintCapability, FreezeCapability};

    friend Multichain::Router;

    struct PoolCoin<phantom UnderlyingCoinType> has key {
        underlying: coin::Coin<UnderlyingCoinType>,
        enabled: bool
    }

    struct Capabilities<phantom UnderlyingCoinType> has key {
        mint_cap: MintCapability<PoolCoin<UnderlyingCoinType>>,
        burn_cap: BurnCapability<PoolCoin<UnderlyingCoinType>>,
        freeze_cap: FreezeCapability<PoolCoin<UnderlyingCoinType>>
    }

    public entry fun add_poolcoin<UnderlyingCoinType>(
        admin: &signer,
        name: String,
        symbol: String,
        decimals: u8
    ) {
        check_mpc(admin);
        assert!(
            !is_poolcoin_exist<UnderlyingCoinType>(),
            error::already_exists(EPOOL_COIN_ALREADY_EXIST),
        );

        move_to(admin, PoolCoin<UnderlyingCoinType>{
            underlying: coin::zero<UnderlyingCoinType>(),
            enabled: true,
        });

        let (burn_cap, freeze_cap, mint_cap) =
            coin::initialize<PoolCoin<UnderlyingCoinType>>(
                admin, name, symbol, decimals, false,
            );
        move_to(admin, Capabilities<UnderlyingCoinType>{
             mint_cap, freeze_cap, burn_cap,
        });

        register<UnderlyingCoinType>(admin);
    }

    public entry fun register<UnderlyingCoinType>(account: &signer) {
        let account_addr = signer::address_of(account);

        if (!coin::is_account_registered<UnderlyingCoinType>(account_addr)) {
            coin::register<UnderlyingCoinType>(account);
        };

        if (!coin::is_account_registered<PoolCoin<UnderlyingCoinType>>(account_addr)) {
            coin::register<PoolCoin<UnderlyingCoinType>>(account);
        }
    }

    public entry fun enable_poolcoin<UnderlyingCoinType>(
        admin: &signer,
        enable: bool,
    ) acquires PoolCoin {
        check_mpc(admin);
        check_pool_coin_exist<UnderlyingCoinType>();
        borrow_global_mut<PoolCoin<UnderlyingCoinType>>(@Multichain).enabled = enable;
    }

    // add liquidity with underlying token
    public entry fun deposit<UnderlyingCoinType>(
        account: &signer,
        amount: u64
    ) acquires PoolCoin, Capabilities {
        check_pool_coin_exist<UnderlyingCoinType>();

        // deposit underlying token
        let underlying_vault = &mut borrow_global_mut<PoolCoin<UnderlyingCoinType>>(@Multichain).underlying;
        let coin_to_deposit = coin::withdraw<UnderlyingCoinType>(account, amount);
        coin::merge<UnderlyingCoinType>(underlying_vault, coin_to_deposit);

        // mint pool token
        let cap = borrow_global<Capabilities<UnderlyingCoinType>>(@Multichain);
        let coin_to_mint = coin::mint<PoolCoin<UnderlyingCoinType>>(amount, &cap.mint_cap);
        coin::deposit<PoolCoin<UnderlyingCoinType>>(signer::address_of(account), coin_to_mint);
    }

    // withdraw liquidity with underlying token
    public entry fun withdraw<UnderlyingCoinType>(
        account: &signer,
        amount: u64
    ) acquires PoolCoin, Capabilities {
        check_pool_coin_exist<UnderlyingCoinType>();

        // burn pool token
        let cap = borrow_global<Capabilities<UnderlyingCoinType>>(@Multichain);
        let coin_to_burn = coin::withdraw(account, amount);
        coin::burn(coin_to_burn, &cap.burn_cap);

        // withdraw underlying token
        let underlying_vault = &mut borrow_global_mut<PoolCoin<UnderlyingCoinType>>(@Multichain).underlying;
        let coin_to_withdraw = coin::extract(underlying_vault, amount);
        coin::deposit<UnderlyingCoinType>(signer::address_of(account), coin_to_withdraw);
    }

    public(friend) fun swapout<UnderlyingCoinType>(
        from: &signer,
        amount: u64
    ) acquires PoolCoin, Capabilities {
        check_pool_coin_enabled<UnderlyingCoinType>();

        if (poolcoin_balance<UnderlyingCoinType>(signer::address_of(from)) >= amount) {
            let cap = borrow_global<Capabilities<UnderlyingCoinType>>(@Multichain);
            let coin_to_burn = coin::withdraw<PoolCoin<UnderlyingCoinType>>(from, amount);
            coin::burn<PoolCoin<UnderlyingCoinType>>(coin_to_burn, &cap.burn_cap);
        } else {
            let coin_to_swapout = coin::withdraw<UnderlyingCoinType>(from, amount);
            let underlying_vault = &mut borrow_global_mut<PoolCoin<UnderlyingCoinType>>(@Multichain).underlying;
            coin::merge<UnderlyingCoinType>(underlying_vault, coin_to_swapout);
        }
    }

    public(friend) fun swapin<UnderlyingCoinType>(
        mpc: &signer,
        to: address,
        amount: u64
    ) acquires PoolCoin, Capabilities {
        check_mpc(mpc);
        check_pool_coin_enabled<UnderlyingCoinType>();

        if(underlying_vault_amount<UnderlyingCoinType>() < amount){
            let cap = borrow_global<Capabilities<UnderlyingCoinType>>(@Multichain);
            let coin_minted = coin::mint<PoolCoin<UnderlyingCoinType>>(amount, &cap.mint_cap);
            coin::deposit<PoolCoin<UnderlyingCoinType>>(to, coin_minted);
        } else {
            let underlying_vault = &mut borrow_global_mut<PoolCoin<UnderlyingCoinType>>(@Multichain).underlying;
            let coin_to_swapin = coin::extract(underlying_vault, amount);
            coin::deposit<UnderlyingCoinType>(to, coin_to_swapin);
        }
    }

    public fun is_poolcoin_exist<UnderlyingCoinType>(): bool {
        exists<PoolCoin<UnderlyingCoinType>>(@Multichain)
    }

    public fun is_poolcoin_enabled<UnderlyingCoinType>(): bool acquires PoolCoin {
        exists<PoolCoin<UnderlyingCoinType>>(@Multichain) &&
        borrow_global<PoolCoin<UnderlyingCoinType>>(@Multichain).enabled
    }

    public fun poolcoin_balance<UnderlyingCoinType>(account: address): u64 {
        coin::balance<PoolCoin<UnderlyingCoinType>>(account)
    }

    public fun underlying_vault_amount<UnderlyingCoinType>(): u64 acquires PoolCoin {
        coin::value(&borrow_global<PoolCoin<UnderlyingCoinType>>(@Multichain).underlying)
    }

    fun check_mpc(acc: &signer) {
        assert!(
            signer::address_of(acc) == @Multichain,
            error::permission_denied(EPOOL_NO_PERMISSION),
        );
    }

    fun check_pool_coin_exist<UnderlyingCoinType>() {
        assert!(
            is_poolcoin_exist<UnderlyingCoinType>(),
            error::already_exists(EPOOL_COIN_NOT_EXIST),
        );
    }

    fun check_pool_coin_enabled<UnderlyingCoinType>() acquires PoolCoin {
        check_pool_coin_exist<UnderlyingCoinType>();
        assert!(
            borrow_global<PoolCoin<UnderlyingCoinType>>(@Multichain).enabled,
            error::unavailable(EPOOL_COIN_DISABLED),
        );
    }

    const EPOOL_COIN_NOT_EXIST: u64 = 1;
    const EPOOL_COIN_ALREADY_EXIST: u64 = 2;
    const EPOOL_COIN_DISABLED: u64 = 3;
    const EPOOL_NO_PERMISSION: u64 = 4;
}
