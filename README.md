# Aptos contract

## install aptos cli

reference to <https://aptos.dev/cli-tools/aptos-cli-tool/install-aptos-cli/>

[Aptos CLI release page](https://github.com/aptos-labs/aptos-core/releases?q=cli&expanded=true)

after installation, run the following command to show the version

```shell
aptos --version
```

## generate account

### 1. generate key pair

```shell
aptos key generate --key-type ed25519 --output-file user1.key
```

this command will generate two files in the current directory

```json
{
  "Result": {
    "PrivateKey Path": "user1.key",
    "PublicKey Path": "user1.key.pub"
  }
}
```

### 2. create account with private key file

```shell
aptos init
aptos init --private-key-file user1.key --profile user1
```

### 3. list account

```shell
aptos account list
aptos account list --profile user1
```

## update config

update named addresses in config files

```text
router/Move.toml
asset/Move.toml
```

```toml
[addresses]
Multichain = "0x1111111111111111111111111111111111111111111111111111111111111111"
```

## compile contract

```shell
aptos move compile --save-metadata --package-dir router
```

## test contract

```shell
aptos move test --package-dir router
```

## publish contract

```shell
aptos move publish --profile user1 --package-dir router
```

## prove contract

```shell
aptos move prove --package-dir router
```

## common operations

### for admin

#### 1. deploy mintable coins

ref. `asset/USDC.move` as an example template

to deploy a new coin (eg. `USDT`)

1. copy `asset/USDC.move` to `asset/USDT.move`, and modity the copied file
2. replace module name `Multichain::USDC` with `Multichain::USDT`
3. replace constants `NAME`, `SYMBOL`, `DECIMALS` accordingly

#### 2. add pool coin for underlyings

```rust
fun add_poolcoin<UnderlyingCoinType>(
    admin: &signer,
    name: String,
    symbol: String,
    decimals: u8
)
```

### for users

#### 1. register coins

users should register coin store before they can receive coins

they can use script to call `0x1::coin::register` to do this.

for our coins, we provides the following wrapper methods

* for pool coins

  call `Multichain::Pool::register`

  ```text
  fun register<UnderlyingCoinType>(account: &signer)
  ```

  eg.

  ```shell
  aptos move run --profile user1 \
  --function-id 0x1111111111111111111111111111111111111111111111111111111111111111::Pool::register \
  --type-args 0x2222222222222222222222222222222222222222222222222222222222222222::asset::USDC
  ```

  where the `type-args` is the `UnderlyingCoin` our pool supports

* for mintable coins (use `USDC` as an example)

  call `Multichain::USDC::register`

  ```text
  fun register(account: &signer)
  ```

  eg.

  ```shell
  aptos move run --profile user1 \
  --function-id 0x1111111111111111111111111111111111111111111111111111111111111111::USDC::register
  ```

### 2. call swapout of our router

call `Multichain::Router::swapout`

```text
fun swapout<CoinType>(
    account: &signer,
    amount: u64,
    receiver: String,
    to_chain_id: u64
)
```

eg.

```shell
aptos move run --profile user1 \
--function-id 0x1111111111111111111111111111111111111111111111111111111111111111::Router::swapout \
--type-args 0x1111111111111111111111111111111111111111111111111111111111111111::USDC::MakerDAO \
--args u64:1000000 --args string:0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --args u64:1
```
