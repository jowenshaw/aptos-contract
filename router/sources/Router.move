module Multichain::Router {
    use std::string::String;
    use std::error;
    use std::signer;
    use aptos_framework::account::new_event_handle;
    use aptos_framework::coin::{Self, BurnCapability, MintCapability};
    use aptos_std::type_info;
    use aptos_std::event::{Self, EventHandle};
    use Multichain::Pool;

    struct Capabilities<phantom CoinType> has key {
        mint_cap: MintCapability<CoinType>,
        burn_cap: BurnCapability<CoinType>,
        enabled: bool
    }

    struct SwapOutEventHolder has key {
        events: EventHandle<SwapOutEvent>
    }

    struct SwapInEventHolder has key {
        events: EventHandle<SwapInEvent>
    }

    struct SwapOutEvent has drop, store {
        token: String,
        from: address,
        to: String,
        amount: u64,
        to_chain_id: u64
    }

    struct SwapInEvent has drop, store {
        swapid: String,
        token: String,
        to: address,
        amount: u64,
        from_chain_id: u64
    }

    struct Status has key {
        paused: bool
    }

    fun init_module(admin: &signer ) {
        move_to(admin, SwapInEventHolder {
            events: new_event_handle<SwapInEvent>(admin)
        });
        move_to(admin, SwapOutEventHolder {
            events: new_event_handle<SwapOutEvent>(admin)
        });
        move_to(admin, Status {
            paused: false
        });
    }

    public entry fun set_paused(admin: &signer, paused: bool) acquires Status {
        check_mpc(admin);
        borrow_global_mut<Status>(@Multichain).paused = paused;
    }

    public entry fun enable_capability<CoinType>(
        admin: &signer,
        enable: bool,
    ) acquires Capabilities {
        check_mpc(admin);
        assert!(
            exists<Capabilities<CoinType>>(@Multichain),
            error::unavailable(EROUTER_CAPABILITY_NOT_EXIST),
        );
        borrow_global_mut<Capabilities<CoinType>>(@Multichain).enabled = enable;
    }

    public entry fun swapout<CoinType>(
        account: &signer,
        amount: u64,
        receiver: String,
        to_chain_id: u64
    ) acquires Status, Capabilities, SwapOutEventHolder {
        check_status();

        if (Pool::is_poolcoin_enabled<CoinType>()) {
            Pool::swapout<CoinType>(account, amount);
        } else {
            check_capabilities<CoinType>();
            let cap = borrow_global<Capabilities<CoinType>>(@Multichain);
            let coin_to_burn = coin::withdraw<CoinType>(account, amount);
            coin::burn<CoinType>(coin_to_burn, &cap.burn_cap);
        };

        let event_holder = borrow_global_mut<SwapOutEventHolder>(@Multichain);
        event::emit_event(&mut event_holder.events, SwapOutEvent {
            token: type_info::type_name<CoinType>(),
            from: signer::address_of(account),
            to: receiver,
            amount: amount,
            to_chain_id: to_chain_id,
        });
    }

    public entry fun swapin<CoinType>(
        mpc: &signer,
        receiver: address,
        amount: u64,
        swapid: String,
        from_chain_id: u64
    ) acquires Status, Capabilities, SwapInEventHolder {
        check_status();
        check_mpc(mpc);

        if (Pool::is_poolcoin_enabled<CoinType>()) {
            Pool::swapin<CoinType>(mpc, receiver, amount);
        } else {
            check_capabilities<CoinType>();
            let cap = borrow_global<Capabilities<CoinType>>(@Multichain);
            let coins_minted = coin::mint<CoinType>(amount, &cap.mint_cap);
            coin::deposit<CoinType>(receiver, coins_minted);
        };

        let event_holder = borrow_global_mut<SwapInEventHolder>(@Multichain);
        event::emit_event(&mut event_holder.events, SwapInEvent {
            swapid: swapid,
            token: type_info::type_name<CoinType>(),
            to: receiver,
            amount: amount,
            from_chain_id: from_chain_id,
        });
    }

    // to accept and store mint/burn capabilities of give coin
    public fun approve_coin<CoinType>(
        admin: &signer,
        mint_cap: MintCapability<CoinType>,
        burn_cap: BurnCapability<CoinType>
    ) {
        check_mpc(admin);
        let enabled = true;
        move_to(admin, Capabilities<CoinType>{ mint_cap, burn_cap, enabled });
    }

    fun check_mpc(acc: &signer) {
        assert!(
            signer::address_of(acc) == @Multichain,
            error::permission_denied(EROUTER_NO_PERMISSION),
        );
    }

    fun check_status() acquires Status {
        assert!(
            !borrow_global<Status>(@Multichain).paused,
            error::unavailable(EROUTER_PAUSED),
        );
    }

    fun check_capabilities<CoinType>() acquires Capabilities {
        assert!(
            exists<Capabilities<CoinType>>(@Multichain),
            error::unavailable(EROUTER_CAPABILITY_NOT_EXIST),
        );
        assert!(
            borrow_global<Capabilities<CoinType>>(@Multichain).enabled,
            error::unavailable(EROUTER_CAPABILITY_DISABLED),
        );
    }

    const EROUTER_PAUSED: u64 = 1;
    const EROUTER_CAPABILITY_NOT_EXIST: u64 = 2;
    const EROUTER_CAPABILITY_DISABLED: u64 = 3;
    const EROUTER_NO_PERMISSION: u64 = 4;
}
