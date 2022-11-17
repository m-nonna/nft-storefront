import FungibleToken from {{0xFungibleTokenContractAddress}}
import NonFungibleToken from {{0xNonFungibleTokenContractAddress}}
import DapperUtilityCoin from {{0xDapperUtilityCoinContractAddress}}
import NFL_NFT from {{0xTeamNFTContractAddress}} 
import NFTStorefront from {{0xNFTStorefrontContractAddress}}
transaction(
    storefrontAddress: Address, 
    listingResourceID: UInt64, 
    expectedPrice: UFix64, 
    metadata: {String: String}
) {
    let paymentVault: @FungibleToken.Vault
    let buyerNFTCollection: &NFL_NFT.Collection{NonFungibleToken.CollectionPublic, NFL_NFT.NFL_NFTCollectionPublic}
    let storefront: &NFTStorefront.Storefront{NFTStorefront.StorefrontPublic}
    let listing: &NFTStorefront.Listing{NFTStorefront.ListingPublic}
    let nflAllDayAuthAccount: AuthAccount
    let mainDUCVault: &DapperUtilityCoin.Vault
    let balanceBeforeTransfer: UFix64
    prepare(nflAllDay: AuthAccount, dapper: AuthAccount, buyer: AuthAccount) {
        // Initialize the AllDay collection if the buyer does not already have one
        if buyer.borrow<&NFL_NFT.Collection>(from: NFL_NFT.CollectionStoragePath) == nil {
            // save it to the account
            buyer.save(<-NFL_NFT.createEmptyCollection(), to: NFL_NFT.CollectionStoragePath)
            // create a public capability for the collection
            buyer.link<&NFL_NFT.Collection{NonFungibleToken.CollectionPublic, NFL_NFT.NFL_NFTCollectionPublic}>(
                NFL_NFT.CollectionPublicPath,
                target: NFL_NFT.CollectionStoragePath
            )
                ?? panic("Could not link NFL_NFT.Collection Public Path");
        }
        self.nflAllDayAuthAccount = nflAllDay
        self.storefront = getAccount(storefrontAddress)
            .getCapability<&NFTStorefront.Storefront{NFTStorefront.StorefrontPublic}>(NFTStorefront.StorefrontPublicPath)
            .borrow()
            ?? panic("Could not borrow a reference to the storefront")
        self.listing = self.storefront.borrowListing(listingResourceID: listingResourceID)
                    ?? panic("No Listing with that ID in Storefront")
        let salePrice = self.listing.getDetails().salePrice
        
        if expectedPrice != salePrice {
            panic("Sale price not expected value")
        }
        self.mainDUCVault = dapper.borrow<&DapperUtilityCoin.Vault>(from: /storage/dapperUtilityCoinVault)
                    ?? panic("Could not borrow reference to Dapper Utility Coin vault")
        self.balanceBeforeTransfer = self.mainDUCVault.balance
        self.paymentVault <- self.mainDUCVault.withdraw(amount: salePrice)
        self.buyerNFTCollection = buyer
            .getCapability<&NFL_NFT.Collection{NonFungibleToken.CollectionPublic, NFL_NFT.NFL_NFTCollectionPublic}>(
                NFL_NFT.CollectionPublicPath
            )
            .borrow()
            ?? panic("Cannot borrow NFL_NFT collection receiver from buyerAddress")
    }
    // The pre phase is executed after the prepare phase,
    // and is used for checking if explicit conditions hold before executing the remainder of the transaction
    pre {
        self.nflAllDayAuthAccount.address == {{0xAllDayContractAddress2}}: "Requires valid authorizing signature"
    }
    execute {
        let item <- self.listing.purchase(
            payment: <-self.paymentVault
        )
        self.buyerNFTCollection.deposit(token: <-item)
    }
    post {
        // Ensure there is no DUC leakage
        self.mainDUCVault.balance == self.balanceBeforeTransfer: "transaction would leak DUC"
    }
}