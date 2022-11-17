// import nba_NFT from "../../contracts/utility/dapper/nba_nft.cdc"
import ExampleNFT from "../../contracts/utility/ExampleNFT.cdc"
import NonFungibleToken from "../../contracts/utility/NonFungibleToken.cdc"
import MetadataViews from "../../contracts/utility/MetadataViews.cdc"
import DapperUtilityCoin from "../../contracts/utility/dapper/DapperUtilityCoin.cdc"
import FungibleToken from "../../contracts/utility/FungibleToken.cdc"
import NFTStorefrontV2 from "../../contracts/NFTStorefrontV2.cdc"
import TokenForwarding from "../../contracts/utility/dapper/TokenForwarding.cdc"

// This transaction facilitates the listing of an NFT with the StorefrontV2 contract
// 
// Collection Identifier: nba_NFT
// Vault Identifier: duc
//
// Version: 0.1.1

/// `saleItemID` - ID of the NFT that is put on sale by the seller.
/// `saleItemPrice` - Amount of tokens (FT) buyer needs to pay for the purchase of listed NFT.
/// `customID` - Optional string to represent identifier of the dapp.
/// `commissionAmount` - Commission amount that will be taken away by the purchase facilitator i.e marketplacesAddress.
/// `expiry` - Unix timestamp at which created listing become expired.
/// `marketplacesAddress` - List of addresses that are allowed to get the commission.

transaction(saleItemID: UInt64, saleItemPrice: UFix64, customID: String?, commissionAmount: UFix64, expiry: UInt64, marketplaceAddress: [Address], universalDucReceiver: Address) {
    var ftReceiver: Capability<&AnyResource{FungibleToken.Receiver}>
    let nftProvider: Capability<&AnyResource{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>
    let storefront: &NFTStorefrontV2.Storefront
    var saleCuts: [NFTStorefrontV2.SaleCut]
    var marketplacesCapability: [Capability<&AnyResource{FungibleToken.Receiver}>]

    prepare(acct: AuthAccount) {
        self.saleCuts = []
        self.marketplacesCapability = []
        // let nbaNFTPrivateCollectionPath = /private/nba_NFT
        let exampleNFTPrivateCollectionPath = /private/ExampleNFT

        // ************************* Handling of DUC Recevier *************************** //

        // Fetch the capability of the universal DUC receiver
        let recipient = getAccount(universalDucReceiver).getCapability<&{FungibleToken.Receiver}>(/public/dapperUtilityCoinReceiver)
        assert(recipient.borrow() != nil, message: "Missing or mis-typed Fungible Token receiver for the DUC recipient")

        // Check whether the receiver has the capability to receive the DUC
        self.ftReceiver = acct.getCapability<&{FungibleToken.Receiver}>(/public/dapperUtilityCoinReceiver)
        if self.ftReceiver.borrow() == nil || !self.ftReceiver.borrow()!.isInstance(Type<@TokenForwarding.Forwarder>()) {
            acct.unlink(/public/dapperUtilityCoinReceiver)
            // Create the forwarder and save it to the account that is doing the forwarding
            let vault <- TokenForwarding.createNewForwarder(recipient: recipient)
            acct.save(<-vault, to: /storage/ducTokenForwarder)
            // Link the new forwarding receiver capability
            acct.link<&{FungibleToken.Receiver}>(
                /public/dapperUtilityCoinReceiver,
                target: /storage/ducTokenForwarder
            )
            self.ftReceiver = acct.getCapability<&{FungibleToken.Receiver}>(/public/dapperUtilityCoinReceiver)
        }

        // Validate the marketplaces capability before submiting to `createListing`.
        for mp in marketplaceAddress {
            let marketplaceReceiver = getAccount(mp).getCapability<&{FungibleToken.Receiver}>(/public/dapperUtilityCoinReceiver)
            assert(marketplaceReceiver.borrow() != nil && marketplaceReceiver.borrow()!.isInstance(Type<@TokenForwarding.Forwarder>()), message: "Marketplaces does not posses the valid receiver type for DUC")
            self.marketplacesCapability.append(marketplaceReceiver)
        }

        // *************************** Seller account interactions  *************************** //

        // // This checks for the public capability
        // if acct.getCapability<&{nba_NFT.nba_NFTCollectionPublic}>(nba_NFT.CollectionPublicPath)!.check() {
        //     acct.unlink(nba_NFT.CollectionPublicPath)
        //     acct.link<&{nba_NFT.nba_NFTCollectionPublic, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, MetadataViews.ResolverCollection }>(nba_NFT.CollectionPublicPath, target: nba_NFT.CollectionStoragePath)
        // }

        // // Check if the Provider capability exists or not if `no` then create a new link for the same.
        // if !acct.getCapability<&{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>(nbaNFTPrivateCollectionPath)!.check() {
        //     acct.unlink(nbaNFTPrivateCollectionPath)
        //     acct.link<&{nba_NFT.nba_NFTCollectionPublic, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, NonFungibleToken.Provider, MetadataViews.ResolverCollection }>(nbaNFTPrivateCollectionPath, target: nba_NFT.CollectionStoragePath)
        // }

        // This checks for the public capability
        if !acct.getCapability<&{ExampleNFT.ExampleNFTCollectionPublic}>(ExampleNFT.CollectionPublicPath)!.check() {
            acct.unlink(ExampleNFT.CollectionPublicPath)
            acct.link<&{ExampleNFT.ExampleNFTCollectionPublic, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, MetadataViews.ResolverCollection }>(ExampleNFT.CollectionPublicPath, target: ExampleNFT.CollectionStoragePath)
        }

        // Check if the Provider capability exists or not if `no` then create a new link for the same.
        if !acct.getCapability<&{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>(exampleNFTPrivateCollectionPath)!.check() {
            acct.unlink(exampleNFTPrivateCollectionPath)
            acct.link<&{ExampleNFT.ExampleNFTCollectionPublic, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, NonFungibleToken.Provider, MetadataViews.ResolverCollection }>(exampleNFTPrivateCollectionPath, target: ExampleNFT.CollectionStoragePath)
        }

        // // self.nftProvider = acct.getCapability<&{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>(nbaNFTPrivateCollectionPath)!
        self.nftProvider = acct.getCapability<&{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>(exampleNFTPrivateCollectionPath)!
        // let collectionRef = acct
        //     .getCapability(nba_NFT.CollectionPublicPath)
        //     .borrow<&nba_NFT.Collection{nba_NFT.nba_NFTCollectionPublic}>()
        //     ?? panic("Could not borrow a reference to the collection")
        
        let collectionRef = acct
            .getCapability<&{ExampleNFT.ExampleNFTCollectionPublic}>(ExampleNFT.CollectionPublicPath).borrow()
            ?? panic("Could not borrow a reference to the collection")
        var totalRoyaltyCut = 0.0
        let effectiveSaleItemPrice = saleItemPrice - commissionAmount
        // let nft = collectionRef.borrownba_NFT(id: saleItemID)!
        let nft = collectionRef.borrowExampleNFT(id: saleItemID)!
        // Check whether the NFT implements the MetadataResolver or not.
        if nft.getViews().contains(Type<MetadataViews.Royalties>()) {
            let royaltiesRef = nft.resolveView(Type<MetadataViews.Royalties>()) ?? panic("Unable to retrieve the royalties")
            let royalties = (royaltiesRef as! MetadataViews.Royalties).getRoyalties()
            for royalty in royalties {
                let royaltyReceiver = royalty.receiver
                assert(royaltyReceiver.borrow() != nil && royaltyReceiver.borrow()!.isInstance(Type<@TokenForwarding.Forwarder>()), message: "Royalty receiver does not has valid receiver type")
                self.saleCuts.append(NFTStorefrontV2.SaleCut(receiver: royalty.receiver, amount: royalty.cut * effectiveSaleItemPrice))
                totalRoyaltyCut = totalRoyaltyCut + royalty.cut * effectiveSaleItemPrice
            }
        }
        // Append the cut for the seller.
        self.saleCuts.append(NFTStorefrontV2.SaleCut(
            receiver: self.ftReceiver,
            amount: effectiveSaleItemPrice - totalRoyaltyCut
        ))
        assert(self.nftProvider.borrow() != nil, message: "Missing or mis-typed nba_NFT.Collection provider")

        if acct.borrow<&NFTStorefrontV2.Storefront>(from: NFTStorefrontV2.StorefrontStoragePath) == nil {
            // Create a new empty Storefront
            let storefront <- NFTStorefrontV2.createStorefront() as! @NFTStorefrontV2.Storefront
            // save it to the account
            acct.save(<-storefront, to: NFTStorefrontV2.StorefrontStoragePath)
            // create a public capability for the Storefront
            acct.link<&NFTStorefrontV2.Storefront{NFTStorefrontV2.StorefrontPublic}>(NFTStorefrontV2.StorefrontPublicPath, target: NFTStorefrontV2.StorefrontStoragePath)
        }
        self.storefront = acct.borrow<&NFTStorefrontV2.Storefront>(from: NFTStorefrontV2.StorefrontStoragePath)!
    }

    execute {
        // Create listing
        self.storefront.createListing(
            nftProviderCapability: self.nftProvider,
            //nftType: Type<@nba_NFT.NFT>(),
            nftType: Type<@ExampleNFT.NFT>(),
            nftID: saleItemID,
            salePaymentVaultType: Type<@DapperUtilityCoin.Vault>(),
            saleCuts: self.saleCuts,
            marketplacesCapability: self.marketplacesCapability.length == 0 ? nil : self.marketplacesCapability,
            customID: customID,
            commissionAmount: commissionAmount,
            expiry: expiry
        )
    }
}