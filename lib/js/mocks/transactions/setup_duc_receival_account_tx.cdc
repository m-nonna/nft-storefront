
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
import MetadataViews from "../../../../contracts/utility/MetadataViews.cdc"
import TokenForwarding from "../../../../contracts/utility/dapper/TokenForwarding.cdc"

transaction(/**vaultPath: StoragePath*/) {

    prepare(signer: AuthAccount) {

        // Return early if the account doesn't have a FungibleToken Vault
        if signer.borrow<&FungibleToken.Vault>(from: /storage/dapperUtilityCoinVault /**vaultPath*/) == nil {
            panic("A vault for the specified fungible token path does not exist")
        }

        // Get the receiver capability for the account being forwarded to
        let recipient = signer.getCapability<&{FungibleToken.Receiver}>(/public/dapperUtilityCoinReceiver)

        // Create the forwarder and save it to the account that is doing the forwarding
        let vault <- TokenForwarding.createNewForwarder(recipient: recipient)
        signer.save(<-vault, to: /storage/ducTokenForwarder)

        // Unlink the existing receiver capability
        if signer.getCapability(/public/dapperUtilityCoinReceiver).check<&{FungibleToken.Receiver}>() {
            signer.unlink(/public/dapperUtilityCoinReceiver)
        }

        // Create a public capability to the Vault that only exposes
        // the deposit function through the Receiver interface
        let capability = signer.link<&{FungibleToken.Receiver}>(
            /public/dapperUtilityCoinReceiver,
            target: /storage/ducTokenForwarder /**vaultPath*/  // js testing library doesn't support the dynamic value of the storage paths
        )!

        // Make sure the capability is valid
        if !capability.check() { panic("Beneficiary capability is not valid!") }
    }
}