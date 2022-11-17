import NonFungibleToken from "../../../../contracts/utility/NonFungibleToken.cdc"
import MetadataViews from "../../../../contracts/utility/MetadataViews.cdc"
import ExampleNFT from "../../../../contracts/utility/dapper/nba_NFT.cdc"

// This transaction is what an account would run
// to set itself up to receive NFTs

transaction {

    prepare(signer: AuthAccount) {
        // Return early if the account already has a collection
        if signer.borrow<&nba_NFT.Collection>(from: nba_NFT.CollectionStoragePath) != nil {
            return
        }

        // Create a new empty collection
        let collection <- nba_NFT.createEmptyCollection()

        // save it to the account
        signer.save(<-collection, to: nba_NFT.CollectionStoragePath)

        // create a public capability for the collection
        signer.link<&{NonFungibleToken.CollectionPublic, nba_NFT.nba_NFTCollectionPublic, MetadataViews.ResolverCollection}>(
            nba_NFT.CollectionPublicPath,
            target: nba_NFT.CollectionStoragePath
        )
    }
}