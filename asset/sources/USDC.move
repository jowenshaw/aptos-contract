module Multichain::USDC {
    use std::string;
    use std::signer;
    use aptos_framework::coin::{Self, BurnCapability, MintCapability, FreezeCapability};
    use Multichain::Router;

    const NAME: vector<u8> = b"USDC";
    const SYMBOL: vector<u8> = b"USDC";
    const DECIMALS: u8 = 6;

    struct MakerDAO has key {}

    struct Capabilities<phantom CoinType> has key {
        mint_cap: MintCapability<CoinType>,
        burn_cap: BurnCapability<CoinType>,
        freeze_cap: FreezeCapability<CoinType>
    }

    fun init_module(account: &signer) {
        let (burn_cap, freeze_cap, mint_cap) =
            coin::initialize<MakerDAO>(
                account,
                string::utf8(NAME),
                string::utf8(SYMBOL),
                DECIMALS,
                false,
            );
        move_to(account, Capabilities<MakerDAO>{mint_cap, burn_cap, freeze_cap});

        Router::approve_coin<MakerDAO>(account, mint_cap, burn_cap);

        register(account);
    }

    public entry fun register(account: &signer) {
        let account_addr = signer::address_of(account);
        if (!coin::is_account_registered<MakerDAO>(account_addr)) {
            coin::register<MakerDAO>(account);
        }
    }
}
