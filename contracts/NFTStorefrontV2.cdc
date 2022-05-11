import FungibleToken from "./FungibleToken.cdc"
import NonFungibleToken from "./NonFungibleToken.cdc"

// NFTStorefrontV2
//
// A general purpose sale support contract for Flow NonFungibleTokens.
// 
// Each account that wants to list NFTs for sale installs a Storefront,
// and lists individual sales within that Storefront as Listings.
// There is one Storefront per account, it handles sales of all NFT types
// for that account.
//
// Each Listing can have one or more "cut"s of the sale price that
// goes to one or more addresses. Cuts can be used to pay listing fees
// or other considerations. 
// Each Listing can have the commission amount that is there to facilitate the
// purchase. Seller can choose to provide an optional list of market places 
// reciever capability whom commission amount would get transfer during the purchase.
//
// Each NFT may be listed in one or more Listings, the validity of each
// Listing can easily be checked.
// 
// Purchasers can watch for Listing events and check the NFT type and
// ID to see if they wish to buy the listed item.
// Marketplaces and other aggregators can watch for Listing events
// and list items of interest.
//
pub contract NFTStorefrontV2 {
    // NFTStorefrontV2Initialized
    // This contract has been deployed.
    // Event consumers can now expect events from this contract.
    //
    pub event NFTStorefrontV2Initialized()

    // StorefrontInitialized
    // A Storefront resource has been created.
    // Event consumers can now expect events from this Storefront.
    // Note that we do not specify an address: we cannot and should not.
    // Created resources do not have an owner address, and may be moved
    // after creation in ways we cannot check.
    // ListingAvailable events can be used to determine the address
    // of the owner of the Storefront (...its location) at the time of
    // the listing but only at that precise moment in that precise transaction.
    // If the seller moves the Storefront while the listing is valid, 
    // that is on them.
    //
    pub event StorefrontInitialized(storefrontResourceID: UInt64)

    // StorefrontDestroyed
    // A Storefront has been destroyed.
    // Event consumers can now stop processing events from this Storefront.
    // Note that we do not specify an address.
    //
    pub event StorefrontDestroyed(storefrontResourceID: UInt64)

    // ListingAvailable
    // A listing has been created and added to a Storefront resource.
    // The Address values here are valid when the event is emitted, but
    // the state of the accounts they refer to may be changed outside of the
    // NFTStorefrontV2 workflow, so be careful to check when using them.
    //
    pub event ListingAvailable(
        storefrontAddress: Address,
        listingResourceID: UInt64,
        nftType: Type,
        nftUUID: UInt64, 
        nftID: UInt64,
        ftVaultType: Type,
        price: UFix64,
        customID: String?,
        commissionAmount: UFix64,
        expiry: UInt64
    )

    // ListingCompleted
    // The listing has been resolved. It has either been purchased, or removed and destroyed.
    //
    pub event ListingCompleted(
        listingResourceID: UInt64, 
        storefrontResourceID: UInt64, 
        purchased: Bool,
        nftType: Type,
        nftUUID: UInt64,
        nftID: UInt64,
        ftVaultType: Type,
        price: UFix64,
        customID: String?,
        commissionAmount: UFix64,
        expiry: UInt64
    )

    // StorefrontStoragePath
    // The location in storage that a Storefront resource should be located.
    pub let StorefrontStoragePath: StoragePath

    // StorefrontPublicPath
    // The public location for a Storefront link.
    pub let StorefrontPublicPath: PublicPath


    // SaleCut
    // A struct representing a recipient that must be sent a certain amount
    // of the payment when a token is sold.
    //
    pub struct SaleCut {
        // The receiver for the payment.
        // Note that we do not store an address to find the Vault that this represents,
        // as the link or resource that we fetch in this way may be manipulated,
        // so to find the address that a cut goes to you must get this struct and then
        // call receiver.borrow()!.owner.address on it.
        // This can be done efficiently in a script.
        pub let receiver: Capability<&{FungibleToken.Receiver}>

        // The amount of the payment FungibleToken that will be paid to the receiver.
        pub let amount: UFix64

        // initializer
        //
        init(receiver: Capability<&{FungibleToken.Receiver}>, amount: UFix64) {
            self.receiver = receiver
            self.amount = amount
        }
    }


    // ListingDetails
    // A struct containing a Listing's data.
    //
    pub struct ListingDetails {
        // The Storefront that the Listing is stored in.
        // Note that this resource cannot be moved to a different Storefront,
        // so this is OK. If we ever make it so that it *can* be moved,
        // this should be revisited.
        pub var storefrontID: UInt64
        // Whether this listing has been purchased or not.
        pub var purchased: Bool
        // The Type of the NonFungibleToken.NFT that is being listed.
        pub let nftType: Type
        // The Resource ID of the NFT which can only be set in the contract
        pub let nftUUID: UInt64
        // The Type of the FungibleToken that payments must be made in.
        pub let nftID: UInt64
        // The Type of the FungibleToken that payments must be made in.
        pub let salePaymentVaultType: Type
        // The amount that must be paid in the specified FungibleToken.
        pub let salePrice: UFix64
        // This specifies the division of payment between recipients.
        pub let saleCuts: [SaleCut]
        // Allow different dApp team to provide custom string as the distinguisher string
        // that would help them to filter events related to their customID.
        pub var customID: String?
        // setToPurchased
        pub let commissionAmount: UFix64
        // Expiry of listing
        pub let expiry: UInt64

        // Irreversibly set this listing as purchased.
        //
        access(contract) fun setToPurchased() {
            self.purchased = true
        }

        access(contract) fun setCustomID(customID: String?){
            self.customID = customID
        }

        // Initializer
        //
        init (
            nftType: Type,
            nftUUID: UInt64,
            nftID: UInt64,
            salePaymentVaultType: Type,
            saleCuts: [SaleCut],
            storefrontID: UInt64,
            customID: String?,
            commissionAmount: UFix64,
            expiry: UInt64
        ) {

            pre {
                // Validate the expiry
                expiry > UInt64(getCurrentBlock().timestamp) : "Expiry should be in future"
                // Validate the length of the sale cut
                saleCuts.length > 0: "Listing must have at least one payment cut recipient"
            }
            self.storefrontID = storefrontID
            self.purchased = false
            self.nftType = nftType
            self.nftUUID = nftUUID
            self.nftID = nftID
            self.salePaymentVaultType = salePaymentVaultType
            self.customID = customID
            self.commissionAmount = commissionAmount
            self.expiry = expiry
            self.saleCuts = saleCuts

            // Calculate the total price from the cuts
            var salePrice = commissionAmount
            // Perform initial check on capabilities, and calculate sale price from cut amounts.
            for cut in self.saleCuts {
                // Make sure we can borrow the receiver.
                // We will check this again when the token is sold.
                cut.receiver.borrow()
                    ?? panic("Cannot borrow receiver")
                // Add the cut amount to the total price
                salePrice = salePrice + cut.amount
            }
            assert(salePrice > 0.0, message: "Listing must have non-zero price")

            // Store the calculated sale price
            self.salePrice = salePrice
        }
    }


    // ListingPublic
    // An interface providing a useful public interface to a Listing.
    //
    pub resource interface ListingPublic {
        // borrowNFT
        // This will assert in the same way as the NFT standard borrowNFT()
        // if the NFT is absent, for example if it has been sold via another listing.
        //
        pub fun borrowNFT(): &NonFungibleToken.NFT

        // purchase
        // Purchase the listing, buying the token.
        // This pays the beneficiaries and returns the token to the buyer.
        //
        pub fun purchase(
            payment: @FungibleToken.Vault, 
            commissionRecipient: Capability<&{FungibleToken.Receiver}>,
            ): @NonFungibleToken.NFT

        // getDetails
        // Fetches the details of the listing.
        pub fun getDetails(): ListingDetails

    }


    // Listing
    // A resource that allows an NFT to be sold for an amount of a given FungibleToken,
    // and for the proceeds of that sale to be split between several recipients.
    // 
    pub resource Listing: ListingPublic {
        // The simple (non-Capability, non-complex) details of the sale
        access(self) let details: ListingDetails

        // A capability allowing this resource to withdraw the NFT with the given ID from its collection.
        // This capability allows the resource to withdraw *any* NFT, so you should be careful when giving
        // such a capability to a resource and always check its code to make sure it will use it in the
        // way that it claims.
        access(contract) let nftProviderCapability: Capability<&{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>

        // Optional list of marketplaces capabilities, Used for incentivising 
        // them if purchase gets facilitated by them.
        access(contract) let marketplacesCap: [Capability<&{FungibleToken.Receiver}>]?

        // borrowNFT
        // This will assert in the same way as the NFT standard borrowNFT()
        // if the NFT is absent, for example if it has been sold via another listing.
        //
        pub fun borrowNFT(): &NonFungibleToken.NFT {
            let ref = self.nftProviderCapability.borrow()!.borrowNFT(id: self.getDetails().nftID)
            assert(ref.isInstance(self.getDetails().nftType), message: "NFT has wrong type")
            assert(ref.id == self.getDetails().nftID, message: "NFT has wrong ID")
            return ref as &NonFungibleToken.NFT
        }

        // getDetails
        // Get the details of the current state of the Listing as a struct.
        // This avoids having more public variables and getter methods for them, and plays
        // nicely with scripts (which cannot return resources). 
        //
        pub fun getDetails(): ListingDetails {
            return self.details
        }

        // purchase
        // Purchase the listing, buying the token.
        // This pays the beneficiaries and commission to the facilitator and returns extra token to the buyer.
        // This also cleans up duplicate listings for the item being purchased.
        pub fun purchase(
            payment: @FungibleToken.Vault, 
            commissionRecipient: Capability<&{FungibleToken.Receiver}>,
        ): @NonFungibleToken.NFT {

            pre {
                self.details.purchased == false: "listing has already been purchased"
                payment.isInstance(self.details.salePaymentVaultType): "payment vault is not requested fungible token"
                payment.balance == self.details.salePrice: "payment vault does not contain requested price"
                self.details.expiry > UInt64(getCurrentBlock().timestamp): "Listing is expired"
                self.owner != nil : "Resource doesn't have the assigned owner"
            }
            // Access the StoreFrontManager resource reference to remove the duplicate listings if purchase would happen successfully.
            let storeFrontPublicRef = self.owner!.getCapability<&NFTStorefrontV2.Storefront{NFTStorefrontV2.StorefrontPublic}>(NFTStorefrontV2.StorefrontPublicPath)
                                        .borrow() ?? panic("Unable to borrow the storeFrontManager resource")
            // Make sure the listing cannot be purchased again.
            self.details.setToPurchased() 
            
            if (self.details.commissionAmount > 0.0) {
                if self.marketplacesCap != nil {
                    var doesCapabilityAllowed = false
                    for cap in self.marketplacesCap! {
                        if cap.getType() == commissionRecipient.getType() && cap.address == commissionRecipient.address && cap.check() {
                            doesCapabilityAllowed = true
                            break
                        }
                    }
                    assert(doesCapabilityAllowed, message: "Given recipient is not allowed")
                }
                let commissionPayment <- payment.withdraw(amount: self.details.commissionAmount)
                let recipient = commissionRecipient.borrow() ?? panic("Unable to borrow the recipent capability")
                recipient.deposit(from: <- commissionPayment)
            }
            // Fetch the token to return to the purchaser.
            let nft <-self.nftProviderCapability.borrow()!.withdraw(withdrawID: self.details.nftID)
            // Neither receivers nor providers are trustworthy, they must implement the correct
            // interface but beyond complying with its pre/post conditions they are not gauranteed
            // to implement the functionality behind the interface in any given way.
            // Therefore we cannot trust the Collection resource behind the interface,
            // and we must check the NFT resource it gives us to make sure that it is the correct one.
            assert(nft.isInstance(self.details.nftType), message: "withdrawn NFT is not of specified type")
            assert(nft.id == self.details.nftID, message: "withdrawn NFT does not have specified ID")

            // Fetch the duplicate listing for the given NFT
            let duplicateListings = storeFrontPublicRef.getDuplicateListingIDs(nftType: self.details.nftType, nftID: self.details.nftID, listingID: self.uuid)

            // Let's force removal of the listing in this storefront for the NFT that is being purchased. 
            for listingID in duplicateListings {
                storeFrontPublicRef.cleanup(listingResourceID: listingID)
            }

            // Rather than aborting the transaction if any receiver is absent when we try to pay it,
            // we send the cut to the first valid receiver.
            // The first receiver should therefore either be the seller, or an agreed recipient for
            // any unpaid cuts.
            var residualReceiver: &{FungibleToken.Receiver}? = nil
            // Pay the comission 
            // Pay each beneficiary their amount of the payment.

            for cut in self.details.saleCuts {
                if let receiver = cut.receiver.borrow() {
                   let paymentCut <- payment.withdraw(amount: cut.amount)
                    receiver.deposit(from: <-paymentCut)
                    if (residualReceiver == nil) {
                        residualReceiver = receiver
                    }
                }
            }

            assert(residualReceiver != nil, message: "No valid payment receivers")

            // At this point, if all recievers were active and availabile, then the payment Vault will have
            // zero tokens left, and this will functionally be a no-op that consumes the empty vault
            residualReceiver!.deposit(from: <-payment)

            // If the listing is purchased, we regard it as completed here.
            // Otherwise we regard it as completed in the destructor.

            emit ListingCompleted(
                listingResourceID: self.uuid,
                storefrontResourceID: self.details.storefrontID,
                purchased: self.details.purchased,
                nftType: self.details.nftType,
                nftUUID: self.details.nftUUID,
                nftID: self.details.nftID,
                ftVaultType: self.details.salePaymentVaultType,
                price: self.details.salePrice,
                customID: self.details.customID,
                commissionAmount: self.details.commissionAmount,
                expiry: self.details.expiry
            )

            return <-nft
        }

        // destructor
        //
        destroy () {
            // If the listing has not been purchased, we regard it as completed here.
            // Otherwise we regard it as completed in purchase().
            // This is because we destroy the listing in Storefront.removeListing()
            // or Storefront.cleanup() .
            // If we change this destructor, revisit those functions.
            if !self.details.purchased {
                emit ListingCompleted(
                    listingResourceID: self.uuid,
                    storefrontResourceID: self.details.storefrontID,
                    purchased: self.details.purchased,
                    nftType: self.details.nftType,
                    nftUUID: self.details.nftUUID,
                    nftID: self.details.nftID,
                    ftVaultType: self.details.salePaymentVaultType,
                    price: self.details.salePrice,
                    customID: self.details.customID,
                    commissionAmount: self.details.commissionAmount,
                    expiry: self.details.expiry
                )
            }
        }

        // initializer
        //
        init (
            nftProviderCapability: Capability<&{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>,
            nftType: Type,
            nftUUID: UInt64,
            nftID: UInt64,
            salePaymentVaultType: Type,
            saleCuts: [SaleCut],
            marketplacesCap: [Capability<&{FungibleToken.Receiver}>]?,
            storefrontID: UInt64,
            customID: String?,
            commissionAmount: UFix64,
            expiry: UInt64
        ) {
            // Store the sale information
            self.details = ListingDetails(
                nftType: nftType,
                nftUUID: nftUUID,
                nftID: nftID,
                salePaymentVaultType: salePaymentVaultType,
                saleCuts: saleCuts,
                storefrontID: storefrontID,
                customID: customID,
                commissionAmount: commissionAmount,
                expiry: expiry
            )

            // Store the NFT provider
            self.nftProviderCapability = nftProviderCapability
            self.marketplacesCap = marketplacesCap

            // Check that the provider contains the NFT.
            // We will check it again when the token is sold.
            // We cannot move this into a function because initializers cannot call member functions.
            let provider = self.nftProviderCapability.borrow()
            assert(provider != nil, message: "cannot borrow nftProviderCapability")

            // This will precondition assert if the token is not available.
            let nft = provider!.borrowNFT(id: self.details.nftID)
            assert(nft.isInstance(self.details.nftType), message: "token is not of specified type")
            assert(nft.id == self.details.nftID, message: "token does not have specified ID")
        }
    }

    // StorefrontManager
    // An interface for adding and removing Listings within a Storefront,
    // intended for use by the Storefront's own
    //
    pub resource interface StorefrontManager {
        // createListing
        // Allows the Storefront owner to create and insert Listings.
        //
        pub fun createListing(
            nftProviderCapability: Capability<&{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>,
            nftType: Type,
            nftID: UInt64,
            salePaymentVaultType: Type,
            saleCuts: [SaleCut],
            marketplacesCap: [Capability<&{FungibleToken.Receiver}>]?,
            customID: String?,
            commissionAmount: UFix64,
            expiry: UInt64
        ): UInt64

        // removeListing
        // Allows the Storefront owner to remove any sale listing, acepted or not.
        //
        pub fun removeListing(listingResourceID: UInt64)
    }

    // StorefrontPublic
    // An interface to allow listing and borrowing Listings, and purchasing items via Listings
    // in a Storefront.
    //
    pub resource interface StorefrontPublic {
        pub fun getListingIDs(): [UInt64]
        pub fun getDuplicateListingIDs(nftType: Type, nftID: UInt64, listingID: UInt64): [UInt64]
        pub fun borrowListing(listingResourceID: UInt64): &Listing{ListingPublic}?
        pub fun cleanupExpiredListings(fromIndex: UInt64, toIndex: UInt64)
        access(contract) fun cleanup(listingResourceID: UInt64)
   }

    // Storefront
    // A resource that allows its owner to manage a list of Listings, and anyone to interact with them
    // in order to query their details and purchase the NFTs that they represent.
    //
    pub resource Storefront : StorefrontManager, StorefrontPublic {
        // The dictionary of Listing uuids to Listing resources.
        access(contract) var listings: @{UInt64: Listing}
        // Dictionary to keep track of listing ids for same NFTs listing.
        // nftType.identifier -> nftID -> [listing resource ID]
        access(contract) var listedNFTs: {String: {UInt64 : [UInt64]}}

        // insert
        // Create and publish a Listing for an NFT.
        //
         pub fun createListing(
            nftProviderCapability: Capability<&{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>,
            nftType: Type,
            nftID: UInt64,
            salePaymentVaultType: Type,
            saleCuts: [SaleCut],
            marketplacesCap: [Capability<&{FungibleToken.Receiver}>]?,
            customID: String?,
            commissionAmount: UFix64,
            expiry: UInt64
         ): UInt64 {
            
            //let's ensure that the seller does indeed hold the NFT being listed
            let collectionRef = nftProviderCapability.borrow()
                ?? panic("Could not borrow reference to collection")
            let nftRef = collectionRef.borrowNFT(id: nftID)

            // Instead of letting an arbitrary value be set for the UUID of a given NFT, the contract
            // should fetch it itelf     
            let uuid = nftRef.uuid
            let listing <- create Listing(
                nftProviderCapability: nftProviderCapability,
                nftType: nftType,
                nftUUID: uuid,
                nftID: nftID,
                salePaymentVaultType: salePaymentVaultType,
                saleCuts: saleCuts,
                marketplacesCap: marketplacesCap,
                storefrontID: self.uuid,
                customID: customID,
                commissionAmount: commissionAmount,
                expiry: expiry
            )
        
            let listingResourceID = listing.uuid
            let listingPrice = listing.getDetails().salePrice
            // Add the new listing to the dictionary.
            let oldListing <- self.listings[listingResourceID] <- listing
            // Note that oldListing will always be nil, but we have to handle it.

            destroy oldListing

            // Add the `listingResourceID` in the tracked listings.
            self.addDuplicateListing(nftIdentifier: nftType.identifier, nftID: nftID, listingResourceID: listingResourceID)

            emit ListingAvailable(
                storefrontAddress: self.owner?.address!,
                listingResourceID: listingResourceID,
                nftType: nftType,
                nftUUID: uuid,
                nftID: nftID,
                ftVaultType: salePaymentVaultType,
                price: listingPrice,
                customID: customID,
                commissionAmount: commissionAmount,
                expiry: expiry
            )

            return listingResourceID
        }

        access(contract) fun addDuplicateListing(nftIdentifier: String, nftID: UInt64, listingResourceID: UInt64) {
             if !self.listedNFTs.containsKey(nftIdentifier) {
                self.listedNFTs.insert(key: nftIdentifier, {nftID: [listingResourceID]})
            } else {
                if !self.listedNFTs[nftIdentifier]!.containsKey(nftID) {
                    self.listedNFTs[nftIdentifier]!.insert(key: nftID, [listingResourceID])
                } else {
                    self.listedNFTs[nftIdentifier]![nftID]!.append(listingResourceID)
                } 
            }
        }
        
        // removeListing
        // Remove a Listing that has not yet been purchased from the collection and destroy it.
        //
        pub fun removeListing(listingResourceID: UInt64) {
            let listing <- self.listings.remove(key: listingResourceID)
                ?? panic("missing Listing")
    
            // This will emit a ListingCompleted event.
            destroy listing
        }

        // getListingIDs
        // Returns an array of the Listing resource IDs that are in the collection
        //
        pub fun getListingIDs(): [UInt64] {
            return self.listings.keys
        }

        // getDuplicateListingIDs
        // Returns an array of listing Ids that are duplicate for the given `nftType` and `nftID`.
        //
        pub fun getDuplicateListingIDs(nftType: Type, nftID: UInt64, listingID: UInt64): [UInt64] {            
            var listingIDs = self.listedNFTs[nftType.identifier]![nftID] ?? panic("No duplicate listing existed")
            // Verify that given listing Id also a part of the `listingIds`
            let doesListingExisted = listingIDs.contains(listingID)
            // Find out the index of the existing listing.
            if doesListingExisted {
                var index: Int = 0
                for id in listingIDs {
                    if id == listingID {
                        break
                    }
                    index = index + 1
                }
                listingIDs.remove(at:index)
                return listingIDs
            } 
           return []
        }

        // cleanupExpiredListings
        // Cleanup the expired listing by iterating over the provided range of indexes.
        //
        pub fun cleanupExpiredListings(fromIndex: UInt64, toIndex: UInt64) {
            pre {
                fromIndex <= toIndex : "Incorrect start index"
                Int(toIndex - fromIndex) < self.getListingIDs().length : "Provided range is out of bound"
            }
            var index = fromIndex
            let listingsIDs = self.getListingIDs()
            while index <= toIndex {
                // There is a possibility that some index may not have the listing.
                // Becuase of the instead of failing the transaction index moved to next listing.
                
                if let listing = self.borrowListing(listingResourceID: listingsIDs[index]) {
                    if listing.getDetails().expiry <= UInt64(getCurrentBlock().timestamp) {
                        self.cleanup(listingResourceID: listingsIDs[index])
                    }
                }
                index = index + UInt64(1) 
            }
        } 

        // borrowSaleItem
        // Returns a read-only view of the SaleItem for the given listingID if it is contained by this collection.
        //
        pub fun borrowListing(listingResourceID: UInt64): &Listing{ListingPublic}? {
             if self.listings[listingResourceID] != nil {
                return &self.listings[listingResourceID] as &Listing{ListingPublic}?
            } else {
                return nil
            }
        }

        // cleanup
        // Remove an listing *if* it has been purchased.
        // Anyone can call, but at present it only benefits the account owner to do so.
        // Kind purchasers can however call it if they like.
        //
        access(contract) fun cleanup(listingResourceID: UInt64) {
            pre {
                self.listings[listingResourceID] != nil: "could not find listing with given id"
            }
            let listing <- self.listings.remove(key: listingResourceID)!
            destroy listing
        }

        // destructor
        //
        destroy () {
            destroy self.listings

            // Let event consumers know that this storefront will no longer exist
            emit StorefrontDestroyed(storefrontResourceID: self.uuid)
        }

        // constructor
        //
        init () {
            self.listings <- {}
            self.listedNFTs = {}

            // Let event consumers know that this storefront exists
            emit StorefrontInitialized(storefrontResourceID: self.uuid)
        }
    }

    // createStorefront
    // Make creating a Storefront publicly accessible.
    //
    pub fun createStorefront(): @Storefront {
        return <-create Storefront()
    }

    init () {
        self.StorefrontStoragePath = /storage/NFTStorefrontV2
        self.StorefrontPublicPath = /public/NFTStorefrontV2

        emit NFTStorefrontV2Initialized()
    }
}
 