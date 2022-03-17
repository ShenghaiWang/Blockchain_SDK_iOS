# Blockchain_SDK_iOS

BlockChain SDK iOS aims to provide simple & intuitive interface for iOS apps to access various blockchains. 
The code is in Swift and generated based on the `OpenRPC specifications`.


## Usage

### Import the package

    import Blockchain_SDK_iOS
        
### Configure endpoint

#### HTTP

    let configuration = Eth.Configuration(rpcConfiguration: .init(baseURL: URL(string: "https://eth-mainnet.alchemyapi.io/v2/...")!))
    let eth = try Eth(configuration: configuration)
    
#### Web socket

    let config = Eth.Configuration(websocketConfiguration: .init(baseURL: URL(string: "wss://eth-mainnet.alchemyapi.io/v2/...")!))
    let eth = try Eth(configuration: config)

### Call method & get response

#### HTTP 

##### Via asyn method

    let result = try await eth.eth_getBlockByHash(blockHash: "0x9e3b33ba48d2cec5314886e03bf205ec873e2a1171311d1534eaba6fbbcbe303", hydratedTransactions: true)

##### Via combine subscription
    
    try eth.eth_getBlockByHash(blockHash: "0xfa4f674587a6f836de096f12b0f9612d4d2fa7f7f6c94db3acc06dbda8ff61cc",
                               hydratedTransactions: true)
    .sink { completion in
        print(completion)
    } receiveValue: { value in
        print(value)
    }.store(in: &cancellables)

#### Web socket

##### Connect

    eth.connectWebSocket()

##### Monitor connection status

    eth.webSocketStatusPublisher
        .receive(on: RunLoop.main)
        .sink { value in
            print(value)
        }.store(in: &cancellables)

##### Send out request

    try eth.eth_getBlockByHash(blockHash: "0xfa4f674587a6f836de096f12b0f9612d4d2fa7f7f6c94db3acc06dbda8ff61cc",
                               hydratedTransactions: true,
                               id: 1)
                               
##### Monitor response

    eth.webSocketResultPublisher
    .sink { value in
        print(value)
    }.store(in: &cancellables)

##### Disconnect

    eth.disconnectWebSocket()


## Requirements

* Xcode 12.x
* Swift 5.x
    
## Installation

### [Swift Package Manager](https://github.com/apple/swift-package-manager)    

Use the url of this repo (https://github.com/ShenghaiWang/Blockchain_SDK_iOS.git).

## Request support for more chain types

Eth supports all the chains that are compatible with Etherum. If you want to access more chains that have different specifications, please send a pull request with the `OpenRPC specification` files. We will generate the coresponding code ASAP.

