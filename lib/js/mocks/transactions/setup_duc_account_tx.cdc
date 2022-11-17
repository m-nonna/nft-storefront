
// This transaction is a template for a transaction
// to create a new link in their account to be used for receiving royalties
// This transaction can be used for any fungible token, which is specified by the `vaultPath` argument
// 
// If the account wants to receive royalties in FLOW, they'll use `/storage/flowTokenVault`
// If they want to receive it in USDC, they would use FiatToken.VaultStoragePath
// and so on. 
// The path used for the public link is a new path that in the future, is expected to receive
// and generic token, which could be forwarded to the appropriate vault

import FungibleToken from "../../../../contracts/utility/FungibleToken.cdc"
import DapperUtilityCoin from "../../../../contracts/utility/dapper/DapperUtilityCoin.cdc"

transaction(/**vaultPath: StoragePath*/) {

    prepare(signer: AuthAccount) {

        // Create a new ExampleToken Vault and put it in storage
        signer.save(
            <-DapperUtilityCoin.createEmptyVault(),
            to: /storage/dapperUtilityCoinVault
        )

        // Create a public capability to the Vault that only exposes
        // the deposit function through the Receiver interface
        signer.link<&DapperUtilityCoin.Vault{FungibleToken.Receiver}>(
            /public/dapperUtilityCoinReceiver,
            target: /storage/dapperUtilityCoinVault
        )

        // Create a public capability to the Vault that only exposes
        // the balance field through the Balance interface
        signer.link<&DapperUtilityCoin.Vault{FungibleToken.Balance}>(
            /public/dapperUtilityCoinBalance,
            target: /storage/dapperUtilityCoinVault
        )
    }
}