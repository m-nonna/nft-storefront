// import nba_NFT from "../../contracts/utility/dapper/nba_nft.cdc"
import ExampleNFT from "../../contracts/utility/ExampleNFT.cdc"
import DapperUtilityCoin from "../../contracts/utility/dapper/DapperUtilityCoin.cdc"
import FungibleToken from "../../contracts/utility/FungibleToken.cdc"
import NonFungibleToken from "../../contracts/utility/NonFungibleToken.cdc"
import NFTStorefrontV2 from "../../contracts/NFTStorefrontV2.cdc"

/// Transaction facilitates the purcahse of listed NFT.
/// It takes the storefront address, listing resource that need
/// to be purchased & a address that will takeaway the commission.
///
/// Buyer of the listing (,i.e. underling NFT) would authorize and sign the
/// transaction and if purchase happens then transacted NFT would store in
/// buyer's collection.

transaction(listingResourceID: UInt64, storefrontAddress: Address, commissionRecipient: Address?) {
    let paymentVault: @FungibleToken.Vault
    //let nbaNFTCollection: &nba_NFT.Collection{NonFungibleToken.Receiver}
    let exampleNFTCollection: &ExampleNFT.Collection{NonFungibleToken.Receiver}
    let storefront: &NFTStorefrontV2.Storefront{NFTStorefrontV2.StorefrontPublic}
    let listing: &NFTStorefrontV2.Listing{NFTStorefrontV2.ListingPublic}
    var commissionRecipientCap: Capability<&{FungibleToken.Receiver}>?

    prepare(buyer: AuthAccount, universalDucPayer: AuthAccount) {
        self.commissionRecipientCap = nil
        assert(storefrontAddress != buyer.address, message : "Buyer and seller can not be same")
        // Access the storefront public resource of the seller to purchase the listing.
        self.storefront = getAccount(storefrontAddress)
            .getCapability<&NFTStorefrontV2.Storefront{NFTStorefrontV2.StorefrontPublic}>(
                NFTStorefrontV2.StorefrontPublicPath
            )!
            .borrow()
            ?? panic("Could not borrow Storefront from provided address")

        // Borrow the listing
        self.listing = self.storefront.borrowListing(listingResourceID: listingResourceID)
                    ?? panic("No Offer with that ID in Storefront")
        let price = self.listing.getDetails().salePrice

        // Access the vault of the buyer to pay the sale price of the listing.
        let mainDucVault = universalDucPayer.borrow<&DapperUtilityCoin.Vault>(from: /storage/dapperUtilityCoinVault)
            ?? panic("Cannot borrow DUC vault from universalDucPayer account storage")
        self.paymentVault <- mainDucVault.withdraw(amount: price)

        // // Initialize the nba_NFT collection if the buyer does not already have one
        // if buyer.borrow<&nba_NFT.Collection>(from: nba_NFT.CollectionStoragePath) == nil {
        //     // save it to the account
        //     buyer.save(<-nba_NFT.createEmptyCollection(), to: nba_NFT.CollectionStoragePath)
        //     // create a public capability for the collection
        //     buyer.link<&nba_NFT.Collection{NonFungibleToken.CollectionPublic, nba_NFT.nba_NFTCollectionPublic}>(
        //         nba_NFT.CollectionPublicPath,
        //         target: nba_NFT.CollectionStoragePath
        //     )?? panic("Could not link nba_NFT.Collection Pub Path");
        // }

        // // Access the buyer's NFT collection to store the purchased NFT.
        // self.nbaNFTCollection = buyer.borrow<&nba_NFT.Collection{NonFungibleToken.Receiver}>(
        //     from: nba_NFT.CollectionStoragePath
        // )!


        // Initialize the nba_NFT collection if the buyer does not already have one
        if buyer.borrow<&ExampleNFT.Collection>(from: ExampleNFT.CollectionStoragePath) == nil {
            // save it to the account
            buyer.save(<-ExampleNFT.createEmptyCollection(), to: ExampleNFT.CollectionStoragePath)
            // create a public capability for the collection
            buyer.link<&ExampleNFT.Collection{NonFungibleToken.CollectionPublic, ExampleNFT.ExampleNFTCollectionPublic}>(
                ExampleNFT.CollectionPublicPath,
                target: ExampleNFT.CollectionStoragePath
            )?? panic("Could not link ExampleNFT.Collection Pub Path");
        }

        // Access the buyer's NFT collection to store the purchased NFT.
        self.exampleNFTCollection = buyer.borrow<&ExampleNFT.Collection{NonFungibleToken.Receiver}>(
            from: ExampleNFT.CollectionStoragePath
        )!



        // Fetch the commission amt.
        let commissionAmount = self.listing.getDetails().commissionAmount

        if commissionRecipient != nil && commissionAmount != 0.0 {
            // Access the capability to receive the commission.
            let _commissionRecipientCap = getAccount(commissionRecipient!).getCapability<&{FungibleToken.Receiver}>(/public/dapperUtilityCoinReceiver)
            assert(_commissionRecipientCap.check(), message: "Commission Recipient doesn't have DUC receiving capability")
            self.commissionRecipientCap = _commissionRecipientCap
        } else if commissionAmount == 0.0 {
            self.commissionRecipientCap = nil
        } else {
            panic("Commission recipient can not be empty when commission amount is non zero")
        }
    }

    execute {
        // Purchase the NFT
        let item <- self.listing.purchase(
            payment: <-self.paymentVault,
            commissionRecipient: self.commissionRecipientCap
        )
        // // // Deposit the NFT in the buyer's collection.
        // // self.nbaNFTCollection.deposit(token: <-item)
        // Deposit the NFT in the buyer's collection.
        self.exampleNFTCollection.deposit(token: <-item)
        // Be kind and recycle
        self.storefront.cleanupPurchasedListings(listingResourceID: listingResourceID)
    }
}