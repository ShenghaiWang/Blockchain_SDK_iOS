import Combine
import Foundation
import Starscream

extension Eth.Configuration {
    var isValid: Bool {
        rpcConfiguration?.baseURL != nil || websocketConfiguration?.baseURL != nil
    }
}

public final class Eth {
    public struct Configuration {
        public struct WebsocketConfiguration {
            public let baseURL: URL
            public let callbackQueue: DispatchQueue?
            public let certPinner: CertificatePinning?
            public let compressionHandler: CompressionHandler?
            public let useCustomEngine: Bool
            public let timeoutInterval: TimeInterval?

            public init(baseURL: URL,
                        callbackQueue: DispatchQueue? = .main,
                        certPinner: CertificatePinning? = FoundationSecurity(),
                        compressionHandler: CompressionHandler? = nil,
                        useCustomEngine: Bool = true,
                        timeoutInterval: TimeInterval? = nil) {
                self.baseURL = baseURL
                self.callbackQueue = callbackQueue
                self.certPinner = certPinner
                self.compressionHandler = compressionHandler
                self.useCustomEngine = useCustomEngine
                self.timeoutInterval = timeoutInterval
            }
        }

        public struct RpcConfiguration {
            public let baseURL: URL
            public let urlSessionConfiguration: URLSessionConfiguration?
            public let urlSessionDelegate: URLSessionDelegate?
            public let urlDelegateQueue: OperationQueue?

            public init(baseURL: URL,
                        urlSessionConfiguration: URLSessionConfiguration? = nil,
                        urlSessionDelegate: URLSessionDelegate? = nil,
                        urlDelegateQueue: OperationQueue? = nil) {
                self.baseURL = baseURL
                self.urlSessionConfiguration = urlSessionConfiguration
                self.urlSessionDelegate = urlSessionDelegate
                self.urlDelegateQueue = urlDelegateQueue
            }
        }

        public let rpcConfiguration: RpcConfiguration?
        public let websocketConfiguration: WebsocketConfiguration?

        public init(rpcConfiguration: RpcConfiguration? = nil,
                    websocketConfiguration: WebsocketConfiguration? = nil) {
            self.rpcConfiguration = rpcConfiguration
            self.websocketConfiguration = websocketConfiguration
        }
    }

    lazy var urlSession: URLSession = {
        let urlSession: URLSession
        guard let configuration = rpcConfiguration?.urlSessionConfiguration else { return .shared }
        return URLSession(configuration: configuration,
                          delegate: rpcConfiguration?.urlSessionDelegate,
                          delegateQueue: rpcConfiguration?.urlDelegateQueue)
    }()

    public enum SDKError: Error {
        case wrongParameter(input: String, pattern: String)
        case resultDataError(data: SingleValueDecodingContainer, typeName: String)
        case wrongConfiguration
    }

    public struct RpcResult<T>: Decodable where T: Decodable {
        public let jsonrpc: String
        public let id: String
        public let result: T?
    }

    public struct RpcRequest: Encodable {
        public let jsonrpc = "2.0"
        public let method: String
        public let id: String
        public var paramsEncoding: (inout UnkeyedEncodingContainer) throws -> Void

        public init(method: String, id: String = "1", paramsEncoding: @escaping (inout UnkeyedEncodingContainer) throws -> Void) {
            self.method = method
            self.id = id
            self.paramsEncoding = paramsEncoding
        }

        public enum CodingKeys: String, CodingKey {
            case jsonrpc
            case method
            case id
            case params
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(jsonrpc, forKey: .jsonrpc)
            try container.encode(method, forKey: .method)
            try container.encode(id, forKey: .id)
            var params = container.nestedUnkeyedContainer(forKey: .params)
            try paramsEncoding(&params)
        }
    }

    private func checkParamter(input: String, pattern: String) throws -> Bool {
        let regex = try NSRegularExpression(pattern: pattern)
        return regex.firstMatch(in: input, range: NSRange(location: 0, length: input.count)) != nil
    }

    private func request(for data: Data) throws -> URLRequest {
        guard let url = rpcConfiguration?.baseURL else {
            throw SDKError.wrongConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        return request
    }

    public enum WebSocketStatus {
        public enum DisconnectedType {
            case reason(reason: String, code: UInt16)
            case error(Error?)
        }
        case connected
        case disconnected(DisconnectedType?)

        public var isConnected: Bool {
            switch self {
            case .connected: return true
            default: return false
            }
        }
    }

    let webSocketStatusSubject = CurrentValueSubject<WebSocketStatus, Never>(.disconnected(nil))
    public var webSocketStatus: WebSocketStatus {
        webSocketStatusSubject.value
    }
    public var webSocketStatusPublisher: AnyPublisher<WebSocketStatus, Never> {
        webSocketStatusSubject.eraseToAnyPublisher()
    }

    let webSocketResultSubject = PassthroughSubject<(id: Int, result: Any), Never>()
    public var webSocketResultPublisher: AnyPublisher<(id: Int, result: Any), Never> {
        webSocketResultSubject.eraseToAnyPublisher()
    }

    lazy var socket: WebSocket? = {
        guard let websocketConfiguration = websocketConfiguration else { return nil }
        var request = URLRequest(url: websocketConfiguration.baseURL)
        if let timeoutInterval = websocketConfiguration.timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        let socket = WebSocket(request: request,
                               certPinner: websocketConfiguration.certPinner,
                               compressionHandler: websocketConfiguration.compressionHandler,
                               useCustomEngine: websocketConfiguration.useCustomEngine)
        socket.onEvent = {[weak self, webSocketStatusSubject] event in
            switch event {
            case .connected(let headers):
                webSocketStatusSubject.send(.connected)
            case .disconnected(let reason, let code):
                webSocketStatusSubject.send(.disconnected(.reason(reason: reason, code: code)))
            case .text(let string):
                self?.parseResultFrom(data: Data(string.utf8))
            case .binary(let data):
                self?.parseResultFrom(data: data)
            case .ping,.pong,.viabilityChanged,.reconnectSuggested:
                break
            case .cancelled:
                webSocketStatusSubject.send(.disconnected(nil))
            case .error(let error):
                webSocketStatusSubject.send(.disconnected(.error(error)))
            }
        }
        socket.connect()
        return socket
    }()

    public init(configuration: Configuration) throws {
        guard configuration.isValid else {
            throw SDKError.wrongConfiguration
        }
        self.rpcConfiguration = configuration.rpcConfiguration
        self.websocketConfiguration = configuration.websocketConfiguration
    }

    public let rpcConfiguration: Configuration.RpcConfiguration?
    public let websocketConfiguration: Configuration.WebsocketConfiguration?

    public func connectWebSocket() {
        socket?.connect()
    }

    public func disconnectWebSocket() {
        socket?.disconnect()
    }

    private func decode<T: Decodable>(from data: Data) throws -> T? {
        try JSONDecoder().decode(RpcResult<T>.self, from: data).result
    }

    public enum BlockTag: String, Codable {
        case earliest
        case latest
        case pending

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.singleValueContainer()
            let value = try values.decode(String.self)
            if let enumValue = BlockTag(rawValue: value) {
                self = enumValue
            } else {
                throw SDKError.resultDataError(data: values, typeName: "BlockTag")
            }
        }
    }

    public enum SyncingProgressNotSyncing: Codable {
        case syncingProgress(value: SyncingProgress)
        case notSyncing(value: Bool)

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .syncingProgress(let value): try container.encode(value)
            case .notSyncing(let value): try container.encode(value)
            }
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.singleValueContainer()
            if let value = try? values.decode(SyncingProgress.self) { self = .syncingProgress(value: value); return }
            if let value = try? values.decode(Bool.self) { self = .notSyncing(value: value); return }
            throw SDKError.resultDataError(data: values, typeName: "SyncingProgressNotSyncing")
        }
    }

    public enum AddressAddresses: Codable {
        case address(value: String)
        case addresses(value: [String])

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .address(let value): try container.encode(value)
            case .addresses(let value): try container.encode(value)
            }
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.singleValueContainer()
            if let value = try? values.decode(String.self) { self = .address(value: value); return }
            if let value = try? values.decode([String].self) { self = .addresses(value: value); return }
            throw SDKError.resultDataError(data: values, typeName: "AddressAddresses")
        }
    }

    public enum BlockNumberBlockTag: Codable {
        case blockNumber(value: String)
        case blockTag(value: BlockTag)

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .blockNumber(let value): try container.encode(value)
            case .blockTag(let value): try container.encode(value)
            }
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.singleValueContainer()
            if let value = try? values.decode(String.self) { self = .blockNumber(value: value); return }
            if let value = try? values.decode(BlockTag.self) { self = .blockTag(value: value); return }
            throw SDKError.resultDataError(data: values, typeName: "BlockNumberBlockTag")
        }
    }

    public enum Signed1559TransactionSigned2930TransactionSignedLegacyTransaction: Codable {
        case signed1559Transaction(value: Signed1559Transaction)
        case signed2930Transaction(value: Signed2930Transaction)
        case signedLegacyTransaction(value: SignedLegacyTransaction)

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .signed1559Transaction(let value): try container.encode(value)
            case .signed2930Transaction(let value): try container.encode(value)
            case .signedLegacyTransaction(let value): try container.encode(value)
            }
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.singleValueContainer()
            if let value = try? values.decode(Signed1559Transaction.self) { self = .signed1559Transaction(value: value); return }
            if let value = try? values.decode(Signed2930Transaction.self) { self = .signed2930Transaction(value: value); return }
            if let value = try? values.decode(SignedLegacyTransaction.self) { self = .signedLegacyTransaction(value: value); return }
            throw SDKError.resultDataError(data: values, typeName: "Signed1559TransactionSigned2930TransactionSignedLegacyTransaction")
        }
    }

    public enum NewBlockHashesnewTransactionHashesnewLogs: Codable {
        case newBlockHashes(value: [String])
        case newTransactionHashes(value: [String])
        case newLogs(value: [Log])

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .newBlockHashes(let value): try container.encode(value)
            case .newTransactionHashes(let value): try container.encode(value)
            case .newLogs(let value): try container.encode(value)
            }
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.singleValueContainer()
            if let value = try? values.decode([String].self) { self = .newBlockHashes(value: value); return }
            if let value = try? values.decode([String].self) { self = .newTransactionHashes(value: value); return }
            if let value = try? values.decode([Log].self) { self = .newLogs(value: value); return }
            throw SDKError.resultDataError(data: values, typeName: "NewBlockHashesnewTransactionHashesnewLogs")
        }
    }

    public enum EIP1559TransactionEIP2930TransactionLegacyTransaction: Codable {
        case eIP1559Transaction(value: EIP1559Transaction)
        case eIP2930Transaction(value: EIP2930Transaction)
        case legacyTransaction(value: LegacyTransaction)

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .eIP1559Transaction(let value): try container.encode(value)
            case .eIP2930Transaction(let value): try container.encode(value)
            case .legacyTransaction(let value): try container.encode(value)
            }
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.singleValueContainer()
            if let value = try? values.decode(EIP1559Transaction.self) { self = .eIP1559Transaction(value: value); return }
            if let value = try? values.decode(EIP2930Transaction.self) { self = .eIP2930Transaction(value: value); return }
            if let value = try? values.decode(LegacyTransaction.self) { self = .legacyTransaction(value: value); return }
            throw SDKError.resultDataError(data: values, typeName: "EIP1559TransactionEIP2930TransactionLegacyTransaction")
        }
    }

    public enum TransactionHashesFullTransactions: Codable {
        case transactionHashes(value: [String])
        case fullTransactions(value: [Signed1559TransactionSigned2930TransactionSignedLegacyTransaction])

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .transactionHashes(let value): try container.encode(value)
            case .fullTransactions(let value): try container.encode(value)
            }
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.singleValueContainer()
            if let value = try? values.decode([String].self) { self = .transactionHashes(value: value); return }
            if let value = try? values.decode([Signed1559TransactionSigned2930TransactionSignedLegacyTransaction].self) { self = .fullTransactions(value: value); return }
            throw SDKError.resultDataError(data: values, typeName: "TransactionHashesFullTransactions")
        }
    }

    public enum AnyTopicMatchSingleTopicMatchMultipleTopicMatch: Codable {
        case anyTopicMatch
        case singleTopicMatch(value: String)
        case multipleTopicMatch(value: [String])

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .anyTopicMatch: try container.encodeNil()
            case .singleTopicMatch(let value): try container.encode(value)
            case .multipleTopicMatch(let value): try container.encode(value)
            }
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.singleValueContainer()
            if let value = try? values.decode(String.self) { self = .singleTopicMatch(value: value); return }
            if let value = try? values.decode([String].self) { self = .multipleTopicMatch(value: value); return }
            self = .anyTopicMatch; return
        }
    }

    /// to: to address
    /// chainId: chainId
    /// gas: gas limit
    /// input: input data
    /// nonce: nonce
    /// value: value
    /// accessList: accessList
    /// type: type
    /// gasPrice: gas price
    public struct EIP2930Transaction: Codable {
        public let to: String?
        public let chainId: String
        public let gas: String
        public let input: String
        public let nonce: String
        public let value: String
        public let accessList: [AccessListEntry]
        public let type: String
        public let gasPrice: String
    }

    /// from: from
    public struct TransactionObjectWithSender: Codable {
        public let from: String
        public let eIP1559Transaction: EIP1559Transaction?
        public let eIP2930Transaction: EIP2930Transaction?
        public let legacyTransaction: LegacyTransaction?
    }

    /// address: hex encoded address
    /// storageKeys:
    public struct AccessListEntry: Codable {
        public let address: String?
        public let storageKeys: [String]?
    }

    /// gasPrice: gas price
    /// gas: gas limit
    /// s: s
    /// nonce: nonce
    /// r: r
    /// to: to address
    /// accessList: accessList
    /// yParity: yParity
    /// type: type
    /// value: value
    /// chainId: chainId
    /// input: input data
    public struct Signed2930Transaction: Codable {
        public let gasPrice: String
        public let gas: String
        public let s: String
        public let nonce: String
        public let r: String
        public let to: String?
        public let accessList: [AccessListEntry]
        public let yParity: String
        public let type: String
        public let value: String
        public let chainId: String
        public let input: String
    }

    /// startingBlock: Starting block
    /// highestBlock: Highest block
    /// currentBlock: Current block
    public struct SyncingProgress: Codable {
        public let startingBlock: String?
        public let highestBlock: String?
        public let currentBlock: String?
    }

    /// to: to address
    /// input: input data
    /// nonce: nonce
    /// type: type
    /// gasPrice: gas price
    /// value: value
    /// s: s
    /// chainId: chainId
    /// r: r
    /// gas: gas limit
    /// v: v
    public struct SignedLegacyTransaction: Codable {
        public let to: String?
        public let input: String
        public let nonce: String
        public let type: String
        public let gasPrice: String
        public let value: String
        public let s: String
        public let chainId: String?
        public let r: String
        public let gas: String
        public let v: String
    }

    /// gas: gas limit
    /// value: value
    /// s: s
    /// yParity: yParity
    /// maxFeePerGas: max fee per gas
    /// to: to address
    /// input: input data
    /// accessList: accessList
    /// r: r
    /// chainId: chainId
    /// type: type
    /// maxPriorityFeePerGas: max priority fee per gas
    /// nonce: nonce
    public struct Signed1559Transaction: Codable {
        public let gas: String
        public let value: String
        public let s: String
        public let yParity: String
        public let maxFeePerGas: String
        public let to: String?
        public let input: String
        public let accessList: [AccessListEntry]
        public let r: String
        public let chainId: String
        public let type: String
        public let maxPriorityFeePerGas: String
        public let nonce: String
    }

    /// accessList: accessList
    /// nonce: nonce
    /// maxFeePerGas: max fee per gas
    /// input: input data
    /// to: to address
    /// maxPriorityFeePerGas: max priority fee per gas
    /// gas: gas limit
    /// value: value
    /// type: type
    /// chainId: chainId
    public struct EIP1559Transaction: Codable {
        public let accessList: [AccessListEntry]
        public let nonce: String
        public let maxFeePerGas: String
        public let input: String
        public let to: String?
        public let maxPriorityFeePerGas: String
        public let gas: String
        public let value: String
        public let type: String
        public let chainId: String
    }

    /// transactionIndex: transaction index
    /// blockHash: block hash
    /// from: from address
    /// hash: transaction hash
    /// blockNumber: block number
    public struct TransactionInformation: Codable {
        public let transactionIndex: String
        public let blockHash: String
        public let from: String
        public let hash: String
        public let blockNumber: String
        public let signed1559Transaction: Signed1559Transaction?
        public let signed2930Transaction: Signed2930Transaction?
        public let signedLegacyTransaction: SignedLegacyTransaction?
    }

    /// toBlock: to block
    /// topics: Topics
    /// address: Address(es)
    /// fromBlock: from block
    public struct Filter: Codable {
        public let toBlock: String?
        public let topics: [AnyTopicMatchSingleTopicMatchMultipleTopicMatch]?
        public let address: AddressAddresses?
        public let fromBlock: String?
    }

    /// reward: rewardArray
    /// baseFeePerGas: baseFeePerGasArray
    /// oldestBlock: oldestBlock
    public struct FeeHistoryResults: Codable {
        public let reward: [[String]]?
        public let baseFeePerGas: [String]
        public let oldestBlock: String?
    }

    /// number: Number
    /// mixHash: Mix hash
    /// baseFeePerGas: Base fee per gas
    /// size: Block size
    /// extraData: Extra data
    /// gasLimit: Gas limit
    /// gasUsed: Gas used
    /// transactions:
    /// totalDifficulty: Total difficult
    /// nonce: Nonce
    /// transactionsRoot: Transactions root
    /// miner: Coinbase
    /// logsBloom: Bloom filter
    /// timestamp: Timestamp
    /// uncles: Uncles
    /// stateRoot: State root
    /// parentHash: Parent block hash
    /// difficulty: Difficulty
    /// receiptsRoot: Receipts root
    /// sha3Uncles: Ommers hash
    public struct BlockObject: Codable {
        public let number: String
        public let mixHash: String
        public let baseFeePerGas: String?
        public let size: String
        public let extraData: String
        public let gasLimit: String
        public let gasUsed: String
        public let transactions: TransactionHashesFullTransactions
        public let totalDifficulty: String
        public let nonce: String
        public let transactionsRoot: String
        public let miner: String
        public let logsBloom: String
        public let timestamp: String
        public let uncles: [String]
        public let stateRoot: String
        public let parentHash: String
        public let difficulty: String?
        public let receiptsRoot: String
        public let sha3Uncles: String
    }

    /// value: value
    /// input: input data
    /// nonce: nonce
    /// gasPrice: gas price
    /// type: type
    /// chainId: chainId
    /// gas: gas limit
    /// to: to address
    public struct LegacyTransaction: Codable {
        public let value: String
        public let input: String
        public let nonce: String
        public let gasPrice: String
        public let type: String
        public let chainId: String?
        public let gas: String
        public let to: String?
    }

    /// logIndex: log index
    /// transactionHash: transaction hash
    /// topics: topics
    /// blockHash: block hash
    /// blockNumber: block number
    /// transactionIndex: transaction index
    /// removed: removed
    /// address: address
    /// data: data
    public struct Log: Codable {
        public let logIndex: String?
        public let transactionHash: String?
        public let topics: [String]?
        public let blockHash: String?
        public let blockNumber: String?
        public let transactionIndex: String?
        public let removed: Bool?
        public let address: String?
        public let data: String?
    }

    /// effectiveGasPrice: effective gas price
    /// status: status
    /// root: state root
    /// logs: logs
    /// logsBloom: logs bloom
    /// from: from
    /// cumulativeGasUsed: cumulative gas used
    /// transactionIndex: transaction index
    /// contractAddress: contract address
    /// to: to
    /// gasUsed: gas used
    /// transactionHash: transaction hash
    /// blockHash: block hash
    /// blockNumber: block number
    public struct ReceiptInfo: Codable {
        public let effectiveGasPrice: String
        public let status: String?
        public let root: String?
        public let logs: [Log]
        public let logsBloom: String
        public let from: String
        public let cumulativeGasUsed: String
        public let transactionIndex: String
        public let contractAddress: String?
        public let to: String?
        public let gasUsed: String
        public let transactionHash: String
        public let blockHash: String
        public let blockNumber: String
    }


    private enum MethodEnum: String {
        case eth_getBlockByHash
        case eth_getBlockByNumber
        case eth_getBlockTransactionCountByHash
        case eth_getBlockTransactionCountByNumber
        case eth_getUncleCountByBlockHash
        case eth_getUncleCountByBlockNumber
        case eth_protocolVersion
        case eth_chainId
        case eth_syncing
        case eth_coinbase
        case eth_accounts
        case eth_blockNumber
        case eth_call
        case eth_estimateGas
        case eth_gasPrice
        case eth_feeHistory
        case eth_newFilter
        case eth_newBlockFilter
        case eth_newPendingTransactionFilter
        case eth_uninstallFilter
        case eth_getFilterChanges
        case eth_getFilterLogs
        case eth_getLogs
        case eth_mining
        case eth_hashrate
        case eth_submitWork
        case eth_submitHashrate
        case eth_sign
        case eth_signTransaction
        case eth_getBalance
        case eth_getStorageAt
        case eth_getTransactionCount
        case eth_getCode
        case eth_sendTransaction
        case eth_sendRawTransaction
        case eth_getTransactionByHash
        case eth_getTransactionByBlockHashAndIndex
        case eth_getTransactionByBlockNumberAndIndex
        case eth_getTransactionReceipt
    }

    private func parseResultFrom(data: Data) {
        struct Result: Decodable {
            let id: String
        }
        guard let id = try? JSONDecoder().decode(Result.self, from: data).id else { return }
        let components = id.components(separatedBy: "|")
        guard components.count == 2,
              let methodName = components.first,
              let methodEnum = MethodEnum(rawValue: methodName),
              let idString = components.last,
              let id = Int(idString) else { return }
        switch methodEnum {
        case .eth_getBlockByHash:
            if let result: BlockObject = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getBlockByNumber:
            if let result: BlockObject = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getBlockTransactionCountByHash:
            if let result: [String] = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getBlockTransactionCountByNumber:
            if let result: [String] = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getUncleCountByBlockHash:
            if let result: [String] = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getUncleCountByBlockNumber:
            if let result: [String] = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_protocolVersion:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_chainId:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_syncing:
            if let result: SyncingProgressNotSyncing = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_coinbase:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_accounts:
            if let result: [String] = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_blockNumber:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_call:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_estimateGas:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_gasPrice:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_feeHistory:
            if let result: FeeHistoryResults = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_newFilter:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_newBlockFilter:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_newPendingTransactionFilter:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_uninstallFilter:
            if let result: Bool = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getFilterChanges:
            if let result: NewBlockHashesnewTransactionHashesnewLogs = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getFilterLogs:
            if let result: NewBlockHashesnewTransactionHashesnewLogs = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getLogs:
            if let result: NewBlockHashesnewTransactionHashesnewLogs = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_mining:
            if let result: Bool = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_hashrate:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_submitWork:
            if let result: Bool = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_submitHashrate:
            if let result: Bool = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_sign:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_signTransaction:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getBalance:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getStorageAt:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getTransactionCount:
            if let result: [String] = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getCode:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_sendTransaction:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_sendRawTransaction:
            if let result: String = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getTransactionByHash:
            if let result: TransactionInformation = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getTransactionByBlockHashAndIndex:
            if let result: TransactionInformation = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getTransactionByBlockNumberAndIndex:
            if let result: TransactionInformation = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        case .eth_getTransactionReceipt:
            if let result: ReceiptInfo = try? decode(from: data) {
                webSocketResultSubject.send((id: id, result: result))
            }
        }
    }


    /// Summary: Returns information about a block by hash.
    public func eth_getBlockByHash(blockHash: String,
                                   hydratedTransactions: Bool) async throws -> BlockObject? {
        guard try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockByHash") { encoder in
            try encoder.encode(blockHash)
            try encoder.encode(hydratedTransactions)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns information about a block by hash.
    public func eth_getBlockByHash(blockHash: String,
                                   hydratedTransactions: Bool) throws -> AnyPublisher<BlockObject?, Error> {
        guard try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockByHash") { encoder in
            try encoder.encode(blockHash)
            try encoder.encode(hydratedTransactions)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns information about a block by hash.
    public func eth_getBlockByHash(blockHash: String,
                                   hydratedTransactions: Bool,
                                   id: Int) throws {
        guard try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockByHash", id: "eth_getBlockByHash|" + String(id)) { encoder in
            try encoder.encode(blockHash)
            try encoder.encode(hydratedTransactions)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns information about a block by number.
    public func eth_getBlockByNumber(blockNumber: String,
                                     hydratedTransactions: Bool) async throws -> BlockObject? {
        guard try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw SDKError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockByNumber") { encoder in
            try encoder.encode(blockNumber)
            try encoder.encode(hydratedTransactions)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns information about a block by number.
    public func eth_getBlockByNumber(blockNumber: String,
                                     hydratedTransactions: Bool) throws -> AnyPublisher<BlockObject?, Error> {
        guard try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw SDKError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockByNumber") { encoder in
            try encoder.encode(blockNumber)
            try encoder.encode(hydratedTransactions)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns information about a block by number.
    public func eth_getBlockByNumber(blockNumber: String,
                                     hydratedTransactions: Bool,
                                     id: Int) throws {
        guard try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw SDKError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockByNumber", id: "eth_getBlockByNumber|" + String(id)) { encoder in
            try encoder.encode(blockNumber)
            try encoder.encode(hydratedTransactions)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns the number of transactions in a block from a block matching the given block hash.
    public func eth_getBlockTransactionCountByHash(blockHash: String?) async throws -> [String]? {
        if let blockHash = blockHash,
           try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") {
            throw SDKError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockTransactionCountByHash") { encoder in
            if let blockHash = blockHash { try encoder.encode(blockHash) }
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns the number of transactions in a block from a block matching the given block hash.
    public func eth_getBlockTransactionCountByHash(blockHash: String?) throws -> AnyPublisher<[String]?, Error> {
        if let blockHash = blockHash,
           try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") {
            throw SDKError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockTransactionCountByHash") { encoder in
            if let blockHash = blockHash { try encoder.encode(blockHash) }
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns the number of transactions in a block from a block matching the given block hash.
    public func eth_getBlockTransactionCountByHash(blockHash: String?,
                                                   id: Int) throws {
        if let blockHash = blockHash,
           try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") {
            throw SDKError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockTransactionCountByHash", id: "eth_getBlockTransactionCountByHash|" + String(id)) { encoder in
            if let blockHash = blockHash { try encoder.encode(blockHash) }
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns the number of transactions in a block matching the given block number.
    public func eth_getBlockTransactionCountByNumber(blockNumber: String?) async throws -> [String]? {
        if let blockNumber = blockNumber,
           try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw SDKError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockTransactionCountByNumber") { encoder in
            if let blockNumber = blockNumber { try encoder.encode(blockNumber) }
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns the number of transactions in a block matching the given block number.
    public func eth_getBlockTransactionCountByNumber(blockNumber: String?) throws -> AnyPublisher<[String]?, Error> {
        if let blockNumber = blockNumber,
           try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw SDKError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockTransactionCountByNumber") { encoder in
            if let blockNumber = blockNumber { try encoder.encode(blockNumber) }
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns the number of transactions in a block matching the given block number.
    public func eth_getBlockTransactionCountByNumber(blockNumber: String?,
                                                     id: Int) throws {
        if let blockNumber = blockNumber,
           try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw SDKError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockTransactionCountByNumber", id: "eth_getBlockTransactionCountByNumber|" + String(id)) { encoder in
            if let blockNumber = blockNumber { try encoder.encode(blockNumber) }
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns the number of uncles in a block from a block matching the given block hash.
    public func eth_getUncleCountByBlockHash(blockHash: String?) async throws -> [String]? {
        if let blockHash = blockHash,
           try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") {
            throw SDKError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getUncleCountByBlockHash") { encoder in
            if let blockHash = blockHash { try encoder.encode(blockHash) }
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns the number of uncles in a block from a block matching the given block hash.
    public func eth_getUncleCountByBlockHash(blockHash: String?) throws -> AnyPublisher<[String]?, Error> {
        if let blockHash = blockHash,
           try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") {
            throw SDKError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getUncleCountByBlockHash") { encoder in
            if let blockHash = blockHash { try encoder.encode(blockHash) }
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns the number of uncles in a block from a block matching the given block hash.
    public func eth_getUncleCountByBlockHash(blockHash: String?,
                                             id: Int) throws {
        if let blockHash = blockHash,
           try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") {
            throw SDKError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getUncleCountByBlockHash", id: "eth_getUncleCountByBlockHash|" + String(id)) { encoder in
            if let blockHash = blockHash { try encoder.encode(blockHash) }
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns the number of transactions in a block matching the given block number.
    public func eth_getUncleCountByBlockNumber(blockNumber: String?) async throws -> [String]? {
        if let blockNumber = blockNumber,
           try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw SDKError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getUncleCountByBlockNumber") { encoder in
            if let blockNumber = blockNumber { try encoder.encode(blockNumber) }
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns the number of transactions in a block matching the given block number.
    public func eth_getUncleCountByBlockNumber(blockNumber: String?) throws -> AnyPublisher<[String]?, Error> {
        if let blockNumber = blockNumber,
           try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw SDKError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getUncleCountByBlockNumber") { encoder in
            if let blockNumber = blockNumber { try encoder.encode(blockNumber) }
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns the number of transactions in a block matching the given block number.
    public func eth_getUncleCountByBlockNumber(blockNumber: String?,
                                               id: Int) throws {
        if let blockNumber = blockNumber,
           try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw SDKError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getUncleCountByBlockNumber", id: "eth_getUncleCountByBlockNumber|" + String(id)) { encoder in
            if let blockNumber = blockNumber { try encoder.encode(blockNumber) }
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns the current Ethereum protocol version.
    public func eth_protocolVersion() async throws -> String? {
        let requestBody = RpcRequest(method: "eth_protocolVersion") { encoder in

        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns the current Ethereum protocol version.
    public func eth_protocolVersion() throws -> AnyPublisher<String?, Error> {
        let requestBody = RpcRequest(method: "eth_protocolVersion") { encoder in

        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns the current Ethereum protocol version.
    public func eth_protocolVersion(                                    id: Int) throws {
        let requestBody = RpcRequest(method: "eth_protocolVersion", id: "eth_protocolVersion|" + String(id)) { encoder in

        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns the chain ID of the current network.
    public func eth_chainId() async throws -> String? {
        let requestBody = RpcRequest(method: "eth_chainId") { encoder in

        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns the chain ID of the current network.
    public func eth_chainId() throws -> AnyPublisher<String?, Error> {
        let requestBody = RpcRequest(method: "eth_chainId") { encoder in

        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns the chain ID of the current network.
    public func eth_chainId(                            id: Int) throws {
        let requestBody = RpcRequest(method: "eth_chainId", id: "eth_chainId|" + String(id)) { encoder in

        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns an object with data about the sync status or false.
    public func eth_syncing() async throws -> SyncingProgressNotSyncing? {
        let requestBody = RpcRequest(method: "eth_syncing") { encoder in

        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns an object with data about the sync status or false.
    public func eth_syncing() throws -> AnyPublisher<SyncingProgressNotSyncing?, Error> {
        let requestBody = RpcRequest(method: "eth_syncing") { encoder in

        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns an object with data about the sync status or false.
    public func eth_syncing(                            id: Int) throws {
        let requestBody = RpcRequest(method: "eth_syncing", id: "eth_syncing|" + String(id)) { encoder in

        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns the client coinbase address.
    public func eth_coinbase() async throws -> String? {
        let requestBody = RpcRequest(method: "eth_coinbase") { encoder in

        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns the client coinbase address.
    public func eth_coinbase() throws -> AnyPublisher<String?, Error> {
        let requestBody = RpcRequest(method: "eth_coinbase") { encoder in

        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns the client coinbase address.
    public func eth_coinbase(                             id: Int) throws {
        let requestBody = RpcRequest(method: "eth_coinbase", id: "eth_coinbase|" + String(id)) { encoder in

        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns a list of addresses owned by client.
    public func eth_accounts() async throws -> [String]? {
        let requestBody = RpcRequest(method: "eth_accounts") { encoder in

        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns a list of addresses owned by client.
    public func eth_accounts() throws -> AnyPublisher<[String]?, Error> {
        let requestBody = RpcRequest(method: "eth_accounts") { encoder in

        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns a list of addresses owned by client.
    public func eth_accounts(                             id: Int) throws {
        let requestBody = RpcRequest(method: "eth_accounts", id: "eth_accounts|" + String(id)) { encoder in

        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns the number of most recent block.
    public func eth_blockNumber() async throws -> String? {
        let requestBody = RpcRequest(method: "eth_blockNumber") { encoder in

        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns the number of most recent block.
    public func eth_blockNumber() throws -> AnyPublisher<String?, Error> {
        let requestBody = RpcRequest(method: "eth_blockNumber") { encoder in

        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns the number of most recent block.
    public func eth_blockNumber(                                id: Int) throws {
        let requestBody = RpcRequest(method: "eth_blockNumber", id: "eth_blockNumber|" + String(id)) { encoder in

        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Executes a new message call immediately without creating a transaction on the block chain.
    public func eth_call(transaction: TransactionObjectWithSender) async throws -> String? {
        let requestBody = RpcRequest(method: "eth_call") { encoder in
            try encoder.encode(transaction)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Executes a new message call immediately without creating a transaction on the block chain.
    public func eth_call(transaction: TransactionObjectWithSender) throws -> AnyPublisher<String?, Error> {
        let requestBody = RpcRequest(method: "eth_call") { encoder in
            try encoder.encode(transaction)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Executes a new message call immediately without creating a transaction on the block chain.
    public func eth_call(transaction: TransactionObjectWithSender,
                         id: Int) throws {
        let requestBody = RpcRequest(method: "eth_call", id: "eth_call|" + String(id)) { encoder in
            try encoder.encode(transaction)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.
    public func eth_estimateGas(transaction: TransactionObjectWithSender) async throws -> String? {
        let requestBody = RpcRequest(method: "eth_estimateGas") { encoder in
            try encoder.encode(transaction)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.
    public func eth_estimateGas(transaction: TransactionObjectWithSender) throws -> AnyPublisher<String?, Error> {
        let requestBody = RpcRequest(method: "eth_estimateGas") { encoder in
            try encoder.encode(transaction)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.
    public func eth_estimateGas(transaction: TransactionObjectWithSender,
                                id: Int) throws {
        let requestBody = RpcRequest(method: "eth_estimateGas", id: "eth_estimateGas|" + String(id)) { encoder in
            try encoder.encode(transaction)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns the current price per gas in wei.
    public func eth_gasPrice() async throws -> String? {
        let requestBody = RpcRequest(method: "eth_gasPrice") { encoder in

        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns the current price per gas in wei.
    public func eth_gasPrice() throws -> AnyPublisher<String?, Error> {
        let requestBody = RpcRequest(method: "eth_gasPrice") { encoder in

        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns the current price per gas in wei.
    public func eth_gasPrice(                             id: Int) throws {
        let requestBody = RpcRequest(method: "eth_gasPrice", id: "eth_gasPrice|" + String(id)) { encoder in

        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary:
    public func eth_feeHistory(blockCount: String,
                               newestBlock: BlockNumberBlockTag,
                               rewardPercentiles: [Double]) async throws -> FeeHistoryResults? {
        guard try checkParamter(input: blockCount, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw SDKError.wrongParameter(input: blockCount, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_feeHistory") { encoder in
            try encoder.encode(blockCount)
            try encoder.encode(newestBlock)
            try encoder.encode(rewardPercentiles)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary:
    public func eth_feeHistory(blockCount: String,
                               newestBlock: BlockNumberBlockTag,
                               rewardPercentiles: [Double]) throws -> AnyPublisher<FeeHistoryResults?, Error> {
        guard try checkParamter(input: blockCount, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw SDKError.wrongParameter(input: blockCount, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_feeHistory") { encoder in
            try encoder.encode(blockCount)
            try encoder.encode(newestBlock)
            try encoder.encode(rewardPercentiles)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary:
    public func eth_feeHistory(blockCount: String,
                               newestBlock: BlockNumberBlockTag,
                               rewardPercentiles: [Double],
                               id: Int) throws {
        guard try checkParamter(input: blockCount, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw SDKError.wrongParameter(input: blockCount, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_feeHistory", id: "eth_feeHistory|" + String(id)) { encoder in
            try encoder.encode(blockCount)
            try encoder.encode(newestBlock)
            try encoder.encode(rewardPercentiles)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Creates a filter object, based on filter options, to notify when the state changes (logs).
    public func eth_newFilter(filter: Filter?) async throws -> String? {
        let requestBody = RpcRequest(method: "eth_newFilter") { encoder in
            if let filter = filter { try encoder.encode(filter) }
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Creates a filter object, based on filter options, to notify when the state changes (logs).
    public func eth_newFilter(filter: Filter?) throws -> AnyPublisher<String?, Error> {
        let requestBody = RpcRequest(method: "eth_newFilter") { encoder in
            if let filter = filter { try encoder.encode(filter) }
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Creates a filter object, based on filter options, to notify when the state changes (logs).
    public func eth_newFilter(filter: Filter?,
                              id: Int) throws {
        let requestBody = RpcRequest(method: "eth_newFilter", id: "eth_newFilter|" + String(id)) { encoder in
            if let filter = filter { try encoder.encode(filter) }
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Creates a filter in the node, to notify when a new block arrives.
    public func eth_newBlockFilter() async throws -> String? {
        let requestBody = RpcRequest(method: "eth_newBlockFilter") { encoder in

        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Creates a filter in the node, to notify when a new block arrives.
    public func eth_newBlockFilter() throws -> AnyPublisher<String?, Error> {
        let requestBody = RpcRequest(method: "eth_newBlockFilter") { encoder in

        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Creates a filter in the node, to notify when a new block arrives.
    public func eth_newBlockFilter(                                   id: Int) throws {
        let requestBody = RpcRequest(method: "eth_newBlockFilter", id: "eth_newBlockFilter|" + String(id)) { encoder in

        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Creates a filter in the node, to notify when new pending transactions arrive.
    public func eth_newPendingTransactionFilter() async throws -> String? {
        let requestBody = RpcRequest(method: "eth_newPendingTransactionFilter") { encoder in

        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Creates a filter in the node, to notify when new pending transactions arrive.
    public func eth_newPendingTransactionFilter() throws -> AnyPublisher<String?, Error> {
        let requestBody = RpcRequest(method: "eth_newPendingTransactionFilter") { encoder in

        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Creates a filter in the node, to notify when new pending transactions arrive.
    public func eth_newPendingTransactionFilter(                                                id: Int) throws {
        let requestBody = RpcRequest(method: "eth_newPendingTransactionFilter", id: "eth_newPendingTransactionFilter|" + String(id)) { encoder in

        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Uninstalls a filter with given id.
    public func eth_uninstallFilter(filterIdentifier: String?) async throws -> Bool? {
        if let filterIdentifier = filterIdentifier,
           try checkParamter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw SDKError.wrongParameter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_uninstallFilter") { encoder in
            if let filterIdentifier = filterIdentifier { try encoder.encode(filterIdentifier) }
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Uninstalls a filter with given id.
    public func eth_uninstallFilter(filterIdentifier: String?) throws -> AnyPublisher<Bool?, Error> {
        if let filterIdentifier = filterIdentifier,
           try checkParamter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw SDKError.wrongParameter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_uninstallFilter") { encoder in
            if let filterIdentifier = filterIdentifier { try encoder.encode(filterIdentifier) }
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Uninstalls a filter with given id.
    public func eth_uninstallFilter(filterIdentifier: String?,
                                    id: Int) throws {
        if let filterIdentifier = filterIdentifier,
           try checkParamter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw SDKError.wrongParameter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_uninstallFilter", id: "eth_uninstallFilter|" + String(id)) { encoder in
            if let filterIdentifier = filterIdentifier { try encoder.encode(filterIdentifier) }
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Polling method for a filter, which returns an array of logs which occurred since last poll.
    public func eth_getFilterChanges(filterIdentifier: String?) async throws -> NewBlockHashesnewTransactionHashesnewLogs? {
        if let filterIdentifier = filterIdentifier,
           try checkParamter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw SDKError.wrongParameter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getFilterChanges") { encoder in
            if let filterIdentifier = filterIdentifier { try encoder.encode(filterIdentifier) }
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Polling method for a filter, which returns an array of logs which occurred since last poll.
    public func eth_getFilterChanges(filterIdentifier: String?) throws -> AnyPublisher<NewBlockHashesnewTransactionHashesnewLogs?, Error> {
        if let filterIdentifier = filterIdentifier,
           try checkParamter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw SDKError.wrongParameter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getFilterChanges") { encoder in
            if let filterIdentifier = filterIdentifier { try encoder.encode(filterIdentifier) }
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Polling method for a filter, which returns an array of logs which occurred since last poll.
    public func eth_getFilterChanges(filterIdentifier: String?,
                                     id: Int) throws {
        if let filterIdentifier = filterIdentifier,
           try checkParamter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw SDKError.wrongParameter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getFilterChanges", id: "eth_getFilterChanges|" + String(id)) { encoder in
            if let filterIdentifier = filterIdentifier { try encoder.encode(filterIdentifier) }
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns an array of all logs matching filter with given id.
    public func eth_getFilterLogs(filterIdentifier: String?) async throws -> NewBlockHashesnewTransactionHashesnewLogs? {
        if let filterIdentifier = filterIdentifier,
           try checkParamter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw SDKError.wrongParameter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getFilterLogs") { encoder in
            if let filterIdentifier = filterIdentifier { try encoder.encode(filterIdentifier) }
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns an array of all logs matching filter with given id.
    public func eth_getFilterLogs(filterIdentifier: String?) throws -> AnyPublisher<NewBlockHashesnewTransactionHashesnewLogs?, Error> {
        if let filterIdentifier = filterIdentifier,
           try checkParamter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw SDKError.wrongParameter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getFilterLogs") { encoder in
            if let filterIdentifier = filterIdentifier { try encoder.encode(filterIdentifier) }
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns an array of all logs matching filter with given id.
    public func eth_getFilterLogs(filterIdentifier: String?,
                                  id: Int) throws {
        if let filterIdentifier = filterIdentifier,
           try checkParamter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw SDKError.wrongParameter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getFilterLogs", id: "eth_getFilterLogs|" + String(id)) { encoder in
            if let filterIdentifier = filterIdentifier { try encoder.encode(filterIdentifier) }
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns an array of all logs matching filter with given id.
    public func eth_getLogs(filter: Filter?) async throws -> NewBlockHashesnewTransactionHashesnewLogs? {
        let requestBody = RpcRequest(method: "eth_getLogs") { encoder in
            if let filter = filter { try encoder.encode(filter) }
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns an array of all logs matching filter with given id.
    public func eth_getLogs(filter: Filter?) throws -> AnyPublisher<NewBlockHashesnewTransactionHashesnewLogs?, Error> {
        let requestBody = RpcRequest(method: "eth_getLogs") { encoder in
            if let filter = filter { try encoder.encode(filter) }
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns an array of all logs matching filter with given id.
    public func eth_getLogs(filter: Filter?,
                            id: Int) throws {
        let requestBody = RpcRequest(method: "eth_getLogs", id: "eth_getLogs|" + String(id)) { encoder in
            if let filter = filter { try encoder.encode(filter) }
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns whether the client is actively mining new blocks.
    public func eth_mining() async throws -> Bool? {
        let requestBody = RpcRequest(method: "eth_mining") { encoder in

        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns whether the client is actively mining new blocks.
    public func eth_mining() throws -> AnyPublisher<Bool?, Error> {
        let requestBody = RpcRequest(method: "eth_mining") { encoder in

        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns whether the client is actively mining new blocks.
    public func eth_mining(                           id: Int) throws {
        let requestBody = RpcRequest(method: "eth_mining", id: "eth_mining|" + String(id)) { encoder in

        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns the number of hashes per second that the node is mining with.
    public func eth_hashrate() async throws -> String? {
        let requestBody = RpcRequest(method: "eth_hashrate") { encoder in

        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns the number of hashes per second that the node is mining with.
    public func eth_hashrate() throws -> AnyPublisher<String?, Error> {
        let requestBody = RpcRequest(method: "eth_hashrate") { encoder in

        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns the number of hashes per second that the node is mining with.
    public func eth_hashrate(                             id: Int) throws {
        let requestBody = RpcRequest(method: "eth_hashrate", id: "eth_hashrate|" + String(id)) { encoder in

        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }







    /// Summary: Used for submitting a proof-of-work solution.
    public func eth_submitWork(nonce: String,
                               hash: String,
                               digest: String) async throws -> Bool? {
        guard try checkParamter(input: nonce, pattern: "^0x[0-9a-f]{16}$") else {
            throw SDKError.wrongParameter(input: nonce, pattern: "^0x[0-9a-f]{16}$")
        }
        guard try checkParamter(input: hash, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: hash, pattern: "^0x[0-9a-f]{64}$")
        }
        guard try checkParamter(input: digest, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: digest, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_submitWork") { encoder in
            try encoder.encode(nonce)
            try encoder.encode(hash)
            try encoder.encode(digest)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Used for submitting a proof-of-work solution.
    public func eth_submitWork(nonce: String,
                               hash: String,
                               digest: String) throws -> AnyPublisher<Bool?, Error> {
        guard try checkParamter(input: nonce, pattern: "^0x[0-9a-f]{16}$") else {
            throw SDKError.wrongParameter(input: nonce, pattern: "^0x[0-9a-f]{16}$")
        }
        guard try checkParamter(input: hash, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: hash, pattern: "^0x[0-9a-f]{64}$")
        }
        guard try checkParamter(input: digest, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: digest, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_submitWork") { encoder in
            try encoder.encode(nonce)
            try encoder.encode(hash)
            try encoder.encode(digest)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Used for submitting a proof-of-work solution.
    public func eth_submitWork(nonce: String,
                               hash: String,
                               digest: String,
                               id: Int) throws {
        guard try checkParamter(input: nonce, pattern: "^0x[0-9a-f]{16}$") else {
            throw SDKError.wrongParameter(input: nonce, pattern: "^0x[0-9a-f]{16}$")
        }
        guard try checkParamter(input: hash, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: hash, pattern: "^0x[0-9a-f]{64}$")
        }
        guard try checkParamter(input: digest, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: digest, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_submitWork", id: "eth_submitWork|" + String(id)) { encoder in
            try encoder.encode(nonce)
            try encoder.encode(hash)
            try encoder.encode(digest)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Used for submitting mining hashrate.
    public func eth_submitHashrate(hashrate: String,
                                   iD: String) async throws -> Bool? {
        guard try checkParamter(input: hashrate, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: hashrate, pattern: "^0x[0-9a-f]{64}$")
        }
        guard try checkParamter(input: iD, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: iD, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_submitHashrate") { encoder in
            try encoder.encode(hashrate)
            try encoder.encode(iD)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Used for submitting mining hashrate.
    public func eth_submitHashrate(hashrate: String,
                                   iD: String) throws -> AnyPublisher<Bool?, Error> {
        guard try checkParamter(input: hashrate, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: hashrate, pattern: "^0x[0-9a-f]{64}$")
        }
        guard try checkParamter(input: iD, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: iD, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_submitHashrate") { encoder in
            try encoder.encode(hashrate)
            try encoder.encode(iD)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Used for submitting mining hashrate.
    public func eth_submitHashrate(hashrate: String,
                                   iD: String,
                                   id: Int) throws {
        guard try checkParamter(input: hashrate, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: hashrate, pattern: "^0x[0-9a-f]{64}$")
        }
        guard try checkParamter(input: iD, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: iD, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_submitHashrate", id: "eth_submitHashrate|" + String(id)) { encoder in
            try encoder.encode(hashrate)
            try encoder.encode(iD)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns an EIP-191 signature over the provided data.
    public func eth_sign(address: String,
                         message: String) async throws -> String? {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw SDKError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        guard try checkParamter(input: message, pattern: "^0x[0-9a-f]*$") else {
            throw SDKError.wrongParameter(input: message, pattern: "^0x[0-9a-f]*$")
        }
        let requestBody = RpcRequest(method: "eth_sign") { encoder in
            try encoder.encode(address)
            try encoder.encode(message)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns an EIP-191 signature over the provided data.
    public func eth_sign(address: String,
                         message: String) throws -> AnyPublisher<String?, Error> {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw SDKError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        guard try checkParamter(input: message, pattern: "^0x[0-9a-f]*$") else {
            throw SDKError.wrongParameter(input: message, pattern: "^0x[0-9a-f]*$")
        }
        let requestBody = RpcRequest(method: "eth_sign") { encoder in
            try encoder.encode(address)
            try encoder.encode(message)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns an EIP-191 signature over the provided data.
    public func eth_sign(address: String,
                         message: String,
                         id: Int) throws {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw SDKError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        guard try checkParamter(input: message, pattern: "^0x[0-9a-f]*$") else {
            throw SDKError.wrongParameter(input: message, pattern: "^0x[0-9a-f]*$")
        }
        let requestBody = RpcRequest(method: "eth_sign", id: "eth_sign|" + String(id)) { encoder in
            try encoder.encode(address)
            try encoder.encode(message)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns an RLP encoded transaction signed by the specified account.
    public func eth_signTransaction(transaction: TransactionObjectWithSender) async throws -> String? {
        let requestBody = RpcRequest(method: "eth_signTransaction") { encoder in
            try encoder.encode(transaction)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns an RLP encoded transaction signed by the specified account.
    public func eth_signTransaction(transaction: TransactionObjectWithSender) throws -> AnyPublisher<String?, Error> {
        let requestBody = RpcRequest(method: "eth_signTransaction") { encoder in
            try encoder.encode(transaction)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns an RLP encoded transaction signed by the specified account.
    public func eth_signTransaction(transaction: TransactionObjectWithSender,
                                    id: Int) throws {
        let requestBody = RpcRequest(method: "eth_signTransaction", id: "eth_signTransaction|" + String(id)) { encoder in
            try encoder.encode(transaction)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns the balance of the account of given address.
    public func eth_getBalance(address: String,
                               block: BlockNumberBlockTag) async throws -> String? {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw SDKError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        let requestBody = RpcRequest(method: "eth_getBalance") { encoder in
            try encoder.encode(address)
            try encoder.encode(block)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns the balance of the account of given address.
    public func eth_getBalance(address: String,
                               block: BlockNumberBlockTag) throws -> AnyPublisher<String?, Error> {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw SDKError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        let requestBody = RpcRequest(method: "eth_getBalance") { encoder in
            try encoder.encode(address)
            try encoder.encode(block)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns the balance of the account of given address.
    public func eth_getBalance(address: String,
                               block: BlockNumberBlockTag,
                               id: Int) throws {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw SDKError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        let requestBody = RpcRequest(method: "eth_getBalance", id: "eth_getBalance|" + String(id)) { encoder in
            try encoder.encode(address)
            try encoder.encode(block)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns the value from a storage position at a given address.
    public func eth_getStorageAt(address: String,
                                 storageSlot: String,
                                 block: BlockNumberBlockTag) async throws -> String? {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw SDKError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        guard try checkParamter(input: storageSlot, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: storageSlot, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getStorageAt") { encoder in
            try encoder.encode(address)
            try encoder.encode(storageSlot)
            try encoder.encode(block)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns the value from a storage position at a given address.
    public func eth_getStorageAt(address: String,
                                 storageSlot: String,
                                 block: BlockNumberBlockTag) throws -> AnyPublisher<String?, Error> {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw SDKError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        guard try checkParamter(input: storageSlot, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: storageSlot, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getStorageAt") { encoder in
            try encoder.encode(address)
            try encoder.encode(storageSlot)
            try encoder.encode(block)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns the value from a storage position at a given address.
    public func eth_getStorageAt(address: String,
                                 storageSlot: String,
                                 block: BlockNumberBlockTag,
                                 id: Int) throws {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw SDKError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        guard try checkParamter(input: storageSlot, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: storageSlot, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getStorageAt", id: "eth_getStorageAt|" + String(id)) { encoder in
            try encoder.encode(address)
            try encoder.encode(storageSlot)
            try encoder.encode(block)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns the number of transactions sent from an address.
    public func eth_getTransactionCount(address: String,
                                        block: BlockNumberBlockTag) async throws -> [String]? {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw SDKError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionCount") { encoder in
            try encoder.encode(address)
            try encoder.encode(block)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns the number of transactions sent from an address.
    public func eth_getTransactionCount(address: String,
                                        block: BlockNumberBlockTag) throws -> AnyPublisher<[String]?, Error> {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw SDKError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionCount") { encoder in
            try encoder.encode(address)
            try encoder.encode(block)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns the number of transactions sent from an address.
    public func eth_getTransactionCount(address: String,
                                        block: BlockNumberBlockTag,
                                        id: Int) throws {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw SDKError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionCount", id: "eth_getTransactionCount|" + String(id)) { encoder in
            try encoder.encode(address)
            try encoder.encode(block)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns code at a given address.
    public func eth_getCode(address: String,
                            block: BlockNumberBlockTag) async throws -> String? {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw SDKError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        let requestBody = RpcRequest(method: "eth_getCode") { encoder in
            try encoder.encode(address)
            try encoder.encode(block)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns code at a given address.
    public func eth_getCode(address: String,
                            block: BlockNumberBlockTag) throws -> AnyPublisher<String?, Error> {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw SDKError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        let requestBody = RpcRequest(method: "eth_getCode") { encoder in
            try encoder.encode(address)
            try encoder.encode(block)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns code at a given address.
    public func eth_getCode(address: String,
                            block: BlockNumberBlockTag,
                            id: Int) throws {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw SDKError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        let requestBody = RpcRequest(method: "eth_getCode", id: "eth_getCode|" + String(id)) { encoder in
            try encoder.encode(address)
            try encoder.encode(block)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Signs and submits a transaction.
    public func eth_sendTransaction(transaction: TransactionObjectWithSender) async throws -> String? {
        let requestBody = RpcRequest(method: "eth_sendTransaction") { encoder in
            try encoder.encode(transaction)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Signs and submits a transaction.
    public func eth_sendTransaction(transaction: TransactionObjectWithSender) throws -> AnyPublisher<String?, Error> {
        let requestBody = RpcRequest(method: "eth_sendTransaction") { encoder in
            try encoder.encode(transaction)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Signs and submits a transaction.
    public func eth_sendTransaction(transaction: TransactionObjectWithSender,
                                    id: Int) throws {
        let requestBody = RpcRequest(method: "eth_sendTransaction", id: "eth_sendTransaction|" + String(id)) { encoder in
            try encoder.encode(transaction)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Submits a raw transaction.
    public func eth_sendRawTransaction(transaction: String) async throws -> String? {
        guard try checkParamter(input: transaction, pattern: "^0x[0-9a-f]*$") else {
            throw SDKError.wrongParameter(input: transaction, pattern: "^0x[0-9a-f]*$")
        }
        let requestBody = RpcRequest(method: "eth_sendRawTransaction") { encoder in
            try encoder.encode(transaction)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Submits a raw transaction.
    public func eth_sendRawTransaction(transaction: String) throws -> AnyPublisher<String?, Error> {
        guard try checkParamter(input: transaction, pattern: "^0x[0-9a-f]*$") else {
            throw SDKError.wrongParameter(input: transaction, pattern: "^0x[0-9a-f]*$")
        }
        let requestBody = RpcRequest(method: "eth_sendRawTransaction") { encoder in
            try encoder.encode(transaction)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Submits a raw transaction.
    public func eth_sendRawTransaction(transaction: String,
                                       id: Int) throws {
        guard try checkParamter(input: transaction, pattern: "^0x[0-9a-f]*$") else {
            throw SDKError.wrongParameter(input: transaction, pattern: "^0x[0-9a-f]*$")
        }
        let requestBody = RpcRequest(method: "eth_sendRawTransaction", id: "eth_sendRawTransaction|" + String(id)) { encoder in
            try encoder.encode(transaction)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns the information about a transaction requested by transaction hash.
    public func eth_getTransactionByHash(transactionHash: String) async throws -> TransactionInformation? {
        guard try checkParamter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionByHash") { encoder in
            try encoder.encode(transactionHash)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns the information about a transaction requested by transaction hash.
    public func eth_getTransactionByHash(transactionHash: String) throws -> AnyPublisher<TransactionInformation?, Error> {
        guard try checkParamter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionByHash") { encoder in
            try encoder.encode(transactionHash)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns the information about a transaction requested by transaction hash.
    public func eth_getTransactionByHash(transactionHash: String,
                                         id: Int) throws {
        guard try checkParamter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionByHash", id: "eth_getTransactionByHash|" + String(id)) { encoder in
            try encoder.encode(transactionHash)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns information about a transaction by block hash and transaction index position.
    public func eth_getTransactionByBlockHashAndIndex(blockHash: String,
                                                      transactionIndex: String) async throws -> TransactionInformation? {
        guard try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        guard try checkParamter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw SDKError.wrongParameter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionByBlockHashAndIndex") { encoder in
            try encoder.encode(blockHash)
            try encoder.encode(transactionIndex)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns information about a transaction by block hash and transaction index position.
    public func eth_getTransactionByBlockHashAndIndex(blockHash: String,
                                                      transactionIndex: String) throws -> AnyPublisher<TransactionInformation?, Error> {
        guard try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        guard try checkParamter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw SDKError.wrongParameter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionByBlockHashAndIndex") { encoder in
            try encoder.encode(blockHash)
            try encoder.encode(transactionIndex)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns information about a transaction by block hash and transaction index position.
    public func eth_getTransactionByBlockHashAndIndex(blockHash: String,
                                                      transactionIndex: String,
                                                      id: Int) throws {
        guard try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") else {
            throw SDKError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        guard try checkParamter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw SDKError.wrongParameter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionByBlockHashAndIndex", id: "eth_getTransactionByBlockHashAndIndex|" + String(id)) { encoder in
            try encoder.encode(blockHash)
            try encoder.encode(transactionIndex)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns information about a transaction by block number and transaction index position.
    public func eth_getTransactionByBlockNumberAndIndex(blockNumber: String,
                                                        transactionIndex: String) async throws -> TransactionInformation? {
        guard try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw SDKError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        guard try checkParamter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw SDKError.wrongParameter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionByBlockNumberAndIndex") { encoder in
            try encoder.encode(blockNumber)
            try encoder.encode(transactionIndex)
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns information about a transaction by block number and transaction index position.
    public func eth_getTransactionByBlockNumberAndIndex(blockNumber: String,
                                                        transactionIndex: String) throws -> AnyPublisher<TransactionInformation?, Error> {
        guard try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw SDKError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        guard try checkParamter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw SDKError.wrongParameter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionByBlockNumberAndIndex") { encoder in
            try encoder.encode(blockNumber)
            try encoder.encode(transactionIndex)
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns information about a transaction by block number and transaction index position.
    public func eth_getTransactionByBlockNumberAndIndex(blockNumber: String,
                                                        transactionIndex: String,
                                                        id: Int) throws {
        guard try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw SDKError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        guard try checkParamter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw SDKError.wrongParameter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionByBlockNumberAndIndex", id: "eth_getTransactionByBlockNumberAndIndex|" + String(id)) { encoder in
            try encoder.encode(blockNumber)
            try encoder.encode(transactionIndex)
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }

    /// Summary: Returns the receipt of a transaction by transaction hash.
    public func eth_getTransactionReceipt(transactionHash: String?) async throws -> ReceiptInfo? {
        if let transactionHash = transactionHash,
           try checkParamter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$") {
            throw SDKError.wrongParameter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionReceipt") { encoder in
            if let transactionHash = transactionHash { try encoder.encode(transactionHash) }
        }
        let (data, _) = try await urlSession.data(for: try request(for: JSONEncoder().encode(requestBody)))
        return try decode(from: data)
    }

    /// Summary: Returns the receipt of a transaction by transaction hash.
    public func eth_getTransactionReceipt(transactionHash: String?) throws -> AnyPublisher<ReceiptInfo?, Error> {
        if let transactionHash = transactionHash,
           try checkParamter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$") {
            throw SDKError.wrongParameter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionReceipt") { encoder in
            if let transactionHash = transactionHash { try encoder.encode(transactionHash) }
        }
        return urlSession.dataTaskPublisher(for: try request(for: try JSONEncoder().encode(requestBody)))
            .tryMap {[weak self] in
                try self?.decode(from: $0.data)
            }.eraseToAnyPublisher()
    }

    /// Summary: Returns the receipt of a transaction by transaction hash.
    public func eth_getTransactionReceipt(transactionHash: String?,
                                          id: Int) throws {
        if let transactionHash = transactionHash,
           try checkParamter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$") {
            throw SDKError.wrongParameter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionReceipt", id: "eth_getTransactionReceipt|" + String(id)) { encoder in
            if let transactionHash = transactionHash { try encoder.encode(transactionHash) }
        }
        socket?.write(data: try JSONEncoder().encode(requestBody))
    }
}

