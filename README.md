# Simple NFT Auction

## Setup
Install foundryup if you don't already have it:

    curl -L https://foundry.paradigm.xyz | bash

Restart terminal or reload PATH env variable. Where this is stored will depend on your machine. The installation above will show your correct path. E.g:

    source ~/.bashrc

run foundryup. This will install forge, cast, and other related binaries:

    foundryup

More information on can be found in the Foundry Book: https://book.getfoundry.sh/getting-started/installation

Clone repo:

    git clone https://github.com/lukmaan-k/simple-nft-auction.git

`cd` into the newly cloned directory and install dependencies:

    forge install

## Tests

Run unit tests with:

    forge test

## Deployment

First rename `.env.example` to `.env` and use this to store your environment vars. The existing `PRIVATE_KEY` is a test account loaded with some SepoliaETH.
`PRIVATE_KEY_ANVIL` is the first local test account provided by anvil (the local blockchain). You will need to fill in your own endpoint for Sepolia and an etherscan key if you also want to verify the contract (see below).

To deploy locally, first start a local node by running:

    anvil

Run deployment script with:

    forge script script/Deploy.s.sol:Deploy --rpc-url http://localhost:8545 --broadcast

To deploy to a testnet, change line 10 in `script/Deploy.s.sol` to use `PRIVATE_KEY` instead of `PRIVATE_KEY_ANVIL`

Now load the variables in the `.env` file with:

    source .env

Deploy with with:

    forge script script/Deploy.s.sol:Deploy --rpc-url $SEPOLIA_RPC_URL --broadcast

Or to also verify contracts when deploying, run:

    forge script script/Deploy.s.sol:Deploy --rpc-url $SEPOLIA_RPC_URL --broadcast --verify --etherscan-api-key $ETHERSCAN_KEY

All of the forge commands above (except `forge install`) can have a `-vvvv` flag added at the end for a more verbose output