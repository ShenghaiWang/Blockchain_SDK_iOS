# BlockChain_SDK_iOS

BlockChain SDK iOS aims to provide simple & intuitive interface for iOS apps to access various blockchains. 
The code is in Swift and generated based on the `OpenRPC specifications`.


## Usage

### Import the package

    import BlockChain_SDK_iOS
        
### Set endpoints

    Eth.baseURL = URL(string: "https://eth-mainnet.alchemyapi.io/v2/...")!

### Call the method

    let result = try await Eth.eth_getBlockByHash(blockHash: "0x9e3b33ba48d2cec5314886e03bf205ec873e2a1171311d1534eaba6fbbcbe303", hydratedTransactions: true)
    print(result)

## Requirements

* Xcode 12.x
* Swift 5.x
    
## Installation

### [Swift Package Manager](https://github.com/apple/swift-package-manager)    

Use the url of this repo (https://github.com/ShenghaiWang/BlockChain_SDK_iOS.git).

## Request support for more chain types

If you want to access more chains, please send a pull request with the `OpenRPC specification` file. 
We will generate the coresponding code ASAP.

