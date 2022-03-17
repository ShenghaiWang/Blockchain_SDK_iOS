import Foundation

public enum Eth {
    public static var baseURL = URL(string: "https://cloudflare-eth.com")!

    public enum OpenRPCError: Error {
        case wrongParameter(input: String, pattern: String)
        case resultDataError(data: SingleValueDecodingContainer, typeName: String)
    }

    public struct RpcResult<T>: Decodable where T: Decodable {
        let jsonrpc: String
        let id: Int
        let result: T
    }

    public struct RpcRequest: Encodable {
        let jsonrpc = "2.0"
        let method: String
        let id = 1
        var paramsEncoding: (inout UnkeyedEncodingContainer) throws -> Void

        enum CodingKeys: String, CodingKey {
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

    private static func checkParamter(input: String, pattern: String) throws -> Bool {
        let regex = try NSRegularExpression(pattern: pattern)
        return regex.firstMatch(in: input, range: NSRange(location: 0, length: input.count)) != nil
    }

    private static func request(for data: Data) -> URLRequest {
        var request = URLRequest(url: Self.baseURL)
        request.httpMethod = "POST"
        request.httpBody = data
        return request
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
                throw OpenRPCError.resultDataError(data: values, typeName: "BlockTag")
            }
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

            throw OpenRPCError.resultDataError(data: values, typeName: "Signed1559TransactionSigned2930TransactionSignedLegacyTransaction")
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

            throw OpenRPCError.resultDataError(data: values, typeName: "EIP1559TransactionEIP2930TransactionLegacyTransaction")
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

            throw OpenRPCError.resultDataError(data: values, typeName: "SyncingProgressNotSyncing")
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

            throw OpenRPCError.resultDataError(data: values, typeName: "AddressAddresses")
        }
    }

    public enum BlockNumberBlockTag: Codable {
        case blockNumber(value: String)
        case blockTag(value: String)

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
            if let value = try? values.decode(String.self) { self = .blockTag(value: value); return }

            throw OpenRPCError.resultDataError(data: values, typeName: "BlockNumberBlockTag")
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

            throw OpenRPCError.resultDataError(data: values, typeName: "TransactionHashesFullTransactions")
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

            throw OpenRPCError.resultDataError(data: values, typeName: "NewBlockHashesnewTransactionHashesnewLogs")
        }
    }

    /// address: hex encoded address
    /// storageKeys:
    public struct AccessListEntry: Codable {
        let address: String?
        let storageKeys: [String]?
    }

    /// value: value
    /// s: s
    /// accessList: accessList
    /// nonce: nonce
    /// maxFeePerGas: max fee per gas
    /// to: to address
    /// chainId: chainId
    /// type: type
    /// r: r
    /// input: input data
    /// maxPriorityFeePerGas: max priority fee per gas
    /// gas: gas limit
    /// yParity: yParity
    public struct Signed1559Transaction: Codable {
        let value: String
        let s: String
        let accessList: [AccessListEntry]
        let nonce: String
        let maxFeePerGas: String
        let to: String?
        let chainId: String
        let type: String
        let r: String
        let input: String
        let maxPriorityFeePerGas: String
        let gas: String
        let yParity: String
    }

    /// root: state root
    /// cumulativeGasUsed: cumulative gas used
    /// blockHash: block hash
    /// gasUsed: gas used
    /// from: from
    /// contractAddress: contract address
    /// blockNumber: block number
    /// status: status
    /// transactionHash: transaction hash
    /// logsBloom: logs bloom
    /// effectiveGasPrice: effective gas price
    /// transactionIndex: transaction index
    /// to: to
    /// logs: logs
    public struct ReceiptInfo: Codable {
        let root: String?
        let cumulativeGasUsed: String
        let blockHash: String
        let gasUsed: String
        let from: String
        let contractAddress: String?
        let blockNumber: String
        let status: String?
        let transactionHash: String
        let logsBloom: String
        let effectiveGasPrice: String
        let transactionIndex: String
        let to: String?
        let logs: [Log]
    }

    /// reward: rewardArray
    /// oldestBlock: oldestBlock
    /// baseFeePerGas: baseFeePerGasArray
    public struct FeeHistoryResults: Codable {
        let reward: [[String]]?
        let oldestBlock: String?
        let baseFeePerGas: [String]
    }

    /// miner: Coinbase
    /// baseFeePerGas: Base fee per gas
    /// logsBloom: Bloom filter
    /// nonce: Nonce
    /// difficulty: Difficulty
    /// gasLimit: Gas limit
    /// extraData: Extra data
    /// number: Number
    /// timestamp: Timestamp
    /// parentHash: Parent block hash
    /// mixHash: Mix hash
    /// stateRoot: State root
    /// receiptsRoot: Receipts root
    /// gasUsed: Gas used
    /// totalDifficulty: Total difficult
    /// size: Block size
    /// sha3Uncles: Ommers hash
    /// transactions:
    /// uncles: Uncles
    /// transactionsRoot: Transactions root
    public struct BlockObject: Codable {
        let miner: String
        let baseFeePerGas: String?
        let logsBloom: String
        let nonce: String
        let difficulty: String?
        let gasLimit: String
        let extraData: String
        let number: String
        let timestamp: String
        let parentHash: String
        let mixHash: String
        let stateRoot: String
        let receiptsRoot: String
        let gasUsed: String
        let totalDifficulty: String
        let size: String
        let sha3Uncles: String
        let transactions: TransactionHashesFullTransactions
        let uncles: [String]
        let transactionsRoot: String
    }

    /// from: from
    public struct TransactionObjectWithSender: Codable {
        let from: String
        let eIP1559Transaction: EIP1559Transaction?
        let eIP2930Transaction: EIP2930Transaction?
        let legacyTransaction: LegacyTransaction?
    }

    /// gasPrice: gas price
    /// chainId: chainId
    /// s: s
    /// to: to address
    /// gas: gas limit
    /// r: r
    /// value: value
    /// type: type
    /// nonce: nonce
    /// input: input data
    /// v: v
    public struct SignedLegacyTransaction: Codable {
        let gasPrice: String
        let chainId: String?
        let s: String
        let to: String?
        let gas: String
        let r: String
        let value: String
        let type: String
        let nonce: String
        let input: String
        let v: String
    }

    /// nonce: nonce
    /// r: r
    /// input: input data
    /// type: type
    /// s: s
    /// value: value
    /// gasPrice: gas price
    /// yParity: yParity
    /// gas: gas limit
    /// chainId: chainId
    /// accessList: accessList
    /// to: to address
    public struct Signed2930Transaction: Codable {
        let nonce: String
        let r: String
        let input: String
        let type: String
        let s: String
        let value: String
        let gasPrice: String
        let yParity: String
        let gas: String
        let chainId: String
        let accessList: [AccessListEntry]
        let to: String?
    }

    /// startingBlock: Starting block
    /// currentBlock: Current block
    /// highestBlock: Highest block
    public struct SyncingProgress: Codable {
        let startingBlock: String?
        let currentBlock: String?
        let highestBlock: String?
    }

    /// address: Address(es)
    /// fromBlock: from block
    /// toBlock: to block
    /// topics: Topics
    public struct Filter: Codable {
        let address: AddressAddresses?
        let fromBlock: String?
        let toBlock: String?
        let topics: [AnyTopicMatchSingleTopicMatchMultipleTopicMatch]?
    }

    /// to: to address
    /// gas: gas limit
    /// type: type
    /// accessList: accessList
    /// value: value
    /// maxFeePerGas: max fee per gas
    /// maxPriorityFeePerGas: max priority fee per gas
    /// nonce: nonce
    /// input: input data
    /// chainId: chainId
    public struct EIP1559Transaction: Codable {
        let to: String?
        let gas: String
        let type: String
        let accessList: [AccessListEntry]
        let value: String
        let maxFeePerGas: String
        let maxPriorityFeePerGas: String
        let nonce: String
        let input: String
        let chainId: String
    }

    /// data: data
    /// topics: topics
    /// address: address
    /// transactionHash: transaction hash
    /// transactionIndex: transaction index
    /// blockNumber: block number
    /// logIndex: log index
    /// removed: removed
    /// blockHash: block hash
    public struct Log: Codable {
        let data: String?
        let topics: [String]?
        let address: String?
        let transactionHash: String?
        let transactionIndex: String?
        let blockNumber: String?
        let logIndex: String?
        let removed: Bool?
        let blockHash: String?
    }

    /// blockHash: block hash
    /// blockNumber: block number
    /// hash: transaction hash
    /// transactionIndex: transaction index
    /// from: from address
    public struct TransactionInformation: Codable {
        let blockHash: String
        let blockNumber: String
        let hash: String
        let transactionIndex: String
        let from: String
        let signed1559Transaction: Signed1559Transaction?
        let signed2930Transaction: Signed2930Transaction?
        let signedLegacyTransaction: SignedLegacyTransaction?
    }

    /// input: input data
    /// gas: gas limit
    /// nonce: nonce
    /// accessList: accessList
    /// value: value
    /// chainId: chainId
    /// gasPrice: gas price
    /// to: to address
    /// type: type
    public struct EIP2930Transaction: Codable {
        let input: String
        let gas: String
        let nonce: String
        let accessList: [AccessListEntry]
        let value: String
        let chainId: String
        let gasPrice: String
        let to: String?
        let type: String
    }

    /// nonce: nonce
    /// to: to address
    /// gas: gas limit
    /// gasPrice: gas price
    /// type: type
    /// input: input data
    /// chainId: chainId
    /// value: value
    public struct LegacyTransaction: Codable {
        let nonce: String
        let to: String?
        let gas: String
        let gasPrice: String
        let type: String
        let input: String
        let chainId: String?
        let value: String
    }

    /// Summary: Returns information about a block by hash.
    public static func eth_getBlockByHash(blockHash: String,
                                          hydratedTransactions: Bool) async throws -> BlockObject {
        guard try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") else {
            throw OpenRPCError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockByHash") { encoder in
            try encoder.encode(blockHash)
            try encoder.encode(hydratedTransactions)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<BlockObject>.self, from: data)
        return value.result
    }

    /// Summary: Returns information about a block by number.
    public static func eth_getBlockByNumber(blockNumber: String,
                                            hydratedTransactions: Bool) async throws -> BlockObject {
        guard try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw OpenRPCError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockByNumber") { encoder in
            try encoder.encode(blockNumber)
            try encoder.encode(hydratedTransactions)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<BlockObject>.self, from: data)
        return value.result
    }

    /// Summary: Returns the number of transactions in a block from a block matching the given block hash.
    public static func eth_getBlockTransactionCountByHash(blockHash: String?) async throws -> [String] {
        if let blockHash = blockHash,
           try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") {
            throw OpenRPCError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockTransactionCountByHash") { encoder in
            if let blockHash = blockHash { try encoder.encode(blockHash) }
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<[String]>.self, from: data)
        return value.result
    }

    /// Summary: Returns the number of transactions in a block matching the given block number.
    public static func eth_getBlockTransactionCountByNumber(blockNumber: String?) async throws -> [String] {
        if let blockNumber = blockNumber,
           try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw OpenRPCError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getBlockTransactionCountByNumber") { encoder in
            if let blockNumber = blockNumber { try encoder.encode(blockNumber) }
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<[String]>.self, from: data)
        return value.result
    }

    /// Summary: Returns the number of uncles in a block from a block matching the given block hash.
    public static func eth_getUncleCountByBlockHash(blockHash: String?) async throws -> [String] {
        if let blockHash = blockHash,
           try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") {
            throw OpenRPCError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getUncleCountByBlockHash") { encoder in
            if let blockHash = blockHash { try encoder.encode(blockHash) }
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<[String]>.self, from: data)
        return value.result
    }

    /// Summary: Returns the number of transactions in a block matching the given block number.
    public static func eth_getUncleCountByBlockNumber(blockNumber: String?) async throws -> [String] {
        if let blockNumber = blockNumber,
           try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw OpenRPCError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getUncleCountByBlockNumber") { encoder in
            if let blockNumber = blockNumber { try encoder.encode(blockNumber) }
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<[String]>.self, from: data)
        return value.result
    }

    /// Summary: Returns the current Ethereum protocol version.
    public static func eth_protocolVersion() async throws -> String {
        let requestBody = RpcRequest(method: "eth_protocolVersion") { encoder in

        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Returns the chain ID of the current network.
    public static func eth_chainId() async throws -> String {
        let requestBody = RpcRequest(method: "eth_chainId") { encoder in

        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Returns an object with data about the sync status or false.
    public static func eth_syncing() async throws -> SyncingProgressNotSyncing {
        let requestBody = RpcRequest(method: "eth_syncing") { encoder in

        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<SyncingProgressNotSyncing>.self, from: data)
        return value.result
    }

    /// Summary: Returns the client coinbase address.
    public static func eth_coinbase() async throws -> String {
        let requestBody = RpcRequest(method: "eth_coinbase") { encoder in

        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Returns a list of addresses owned by client.
    public static func eth_accounts() async throws -> [String] {
        let requestBody = RpcRequest(method: "eth_accounts") { encoder in

        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<[String]>.self, from: data)
        return value.result
    }

    /// Summary: Returns the number of most recent block.
    public static func eth_blockNumber() async throws -> String {
        let requestBody = RpcRequest(method: "eth_blockNumber") { encoder in

        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Executes a new message call immediately without creating a transaction on the block chain.
    public static func eth_call(transaction: TransactionObjectWithSender) async throws -> String {
        let requestBody = RpcRequest(method: "eth_call") { encoder in
            try encoder.encode(transaction)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.
    public static func eth_estimateGas(transaction: TransactionObjectWithSender) async throws -> String {
        let requestBody = RpcRequest(method: "eth_estimateGas") { encoder in
            try encoder.encode(transaction)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Returns the current price per gas in wei.
    public static func eth_gasPrice() async throws -> String {
        let requestBody = RpcRequest(method: "eth_gasPrice") { encoder in

        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary:
    public static func eth_feeHistory(blockCount: String,
                                      newestBlock: BlockNumberBlockTag,
                                      rewardPercentiles: [Double]) async throws -> FeeHistoryResults {
        guard try checkParamter(input: blockCount, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw OpenRPCError.wrongParameter(input: blockCount, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_feeHistory") { encoder in
            try encoder.encode(blockCount)
            try encoder.encode(newestBlock)
            try encoder.encode(rewardPercentiles)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<FeeHistoryResults>.self, from: data)
        return value.result
    }

    /// Summary: Creates a filter object, based on filter options, to notify when the state changes (logs).
    public static func eth_newFilter(filter: Filter?) async throws -> String {
        let requestBody = RpcRequest(method: "eth_newFilter") { encoder in
            if let filter = filter { try encoder.encode(filter) }
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Creates a filter in the node, to notify when a new block arrives.
    public static func eth_newBlockFilter() async throws -> String {
        let requestBody = RpcRequest(method: "eth_newBlockFilter") { encoder in

        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Creates a filter in the node, to notify when new pending transactions arrive.
    public static func eth_newPendingTransactionFilter() async throws -> String {
        let requestBody = RpcRequest(method: "eth_newPendingTransactionFilter") { encoder in

        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Uninstalls a filter with given id.
    public static func eth_uninstallFilter(filterIdentifier: String?) async throws -> Bool {
        if let filterIdentifier = filterIdentifier,
           try checkParamter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw OpenRPCError.wrongParameter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_uninstallFilter") { encoder in
            if let filterIdentifier = filterIdentifier { try encoder.encode(filterIdentifier) }
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<Bool>.self, from: data)
        return value.result
    }

    /// Summary: Polling method for a filter, which returns an array of logs which occurred since last poll.
    public static func eth_getFilterChanges(filterIdentifier: String?) async throws -> NewBlockHashesnewTransactionHashesnewLogs {
        if let filterIdentifier = filterIdentifier,
           try checkParamter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw OpenRPCError.wrongParameter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getFilterChanges") { encoder in
            if let filterIdentifier = filterIdentifier { try encoder.encode(filterIdentifier) }
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<NewBlockHashesnewTransactionHashesnewLogs>.self, from: data)
        return value.result
    }

    /// Summary: Returns an array of all logs matching filter with given id.
    public static func eth_getFilterLogs(filterIdentifier: String?) async throws -> NewBlockHashesnewTransactionHashesnewLogs {
        if let filterIdentifier = filterIdentifier,
           try checkParamter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") {
            throw OpenRPCError.wrongParameter(input: filterIdentifier, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getFilterLogs") { encoder in
            if let filterIdentifier = filterIdentifier { try encoder.encode(filterIdentifier) }
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<NewBlockHashesnewTransactionHashesnewLogs>.self, from: data)
        return value.result
    }

    /// Summary: Returns an array of all logs matching filter with given id.
    public static func eth_getLogs(filter: Filter?) async throws -> NewBlockHashesnewTransactionHashesnewLogs {
        let requestBody = RpcRequest(method: "eth_getLogs") { encoder in
            if let filter = filter { try encoder.encode(filter) }
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<NewBlockHashesnewTransactionHashesnewLogs>.self, from: data)
        return value.result
    }

    /// Summary: Returns whether the client is actively mining new blocks.
    public static func eth_mining() async throws -> Bool {
        let requestBody = RpcRequest(method: "eth_mining") { encoder in

        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<Bool>.self, from: data)
        return value.result
    }

    /// Summary: Returns the number of hashes per second that the node is mining with.
    public static func eth_hashrate() async throws -> String {
        let requestBody = RpcRequest(method: "eth_hashrate") { encoder in

        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }



    /// Summary: Used for submitting a proof-of-work solution.
    public static func eth_submitWork(nonce: String,
                                      hash: String,
                                      digest: String) async throws -> Bool {
        guard try checkParamter(input: nonce, pattern: "^0x[0-9a-f]{16}$") else {
            throw OpenRPCError.wrongParameter(input: nonce, pattern: "^0x[0-9a-f]{16}$")
        }
        guard try checkParamter(input: hash, pattern: "^0x[0-9a-f]{64}$") else {
            throw OpenRPCError.wrongParameter(input: hash, pattern: "^0x[0-9a-f]{64}$")
        }
        guard try checkParamter(input: digest, pattern: "^0x[0-9a-f]{64}$") else {
            throw OpenRPCError.wrongParameter(input: digest, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_submitWork") { encoder in
            try encoder.encode(nonce)
            try encoder.encode(hash)
            try encoder.encode(digest)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<Bool>.self, from: data)
        return value.result
    }

    /// Summary: Used for submitting mining hashrate.
    public static func eth_submitHashrate(hashrate: String,
                                          iD: String) async throws -> Bool {
        guard try checkParamter(input: hashrate, pattern: "^0x[0-9a-f]{64}$") else {
            throw OpenRPCError.wrongParameter(input: hashrate, pattern: "^0x[0-9a-f]{64}$")
        }
        guard try checkParamter(input: iD, pattern: "^0x[0-9a-f]{64}$") else {
            throw OpenRPCError.wrongParameter(input: iD, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_submitHashrate") { encoder in
            try encoder.encode(hashrate)
            try encoder.encode(iD)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<Bool>.self, from: data)
        return value.result
    }

    /// Summary: Returns an EIP-191 signature over the provided data.
    public static func eth_sign(address: String,
                                message: String) async throws -> String {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw OpenRPCError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        guard try checkParamter(input: message, pattern: "^0x[0-9a-f]*$") else {
            throw OpenRPCError.wrongParameter(input: message, pattern: "^0x[0-9a-f]*$")
        }
        let requestBody = RpcRequest(method: "eth_sign") { encoder in
            try encoder.encode(address)
            try encoder.encode(message)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Returns an RLP encoded transaction signed by the specified account.
    public static func eth_signTransaction(transaction: TransactionObjectWithSender) async throws -> String {
        let requestBody = RpcRequest(method: "eth_signTransaction") { encoder in
            try encoder.encode(transaction)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Returns the balance of the account of given address.
    public static func eth_getBalance(address: String,
                                      block: BlockNumberBlockTag) async throws -> String {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw OpenRPCError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        let requestBody = RpcRequest(method: "eth_getBalance") { encoder in
            try encoder.encode(address)
            try encoder.encode(block)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Returns the value from a storage position at a given address.
    public static func eth_getStorageAt(address: String,
                                        storageSlot: String,
                                        block: BlockNumberBlockTag) async throws -> String {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw OpenRPCError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        guard try checkParamter(input: storageSlot, pattern: "^0x[0-9a-f]{64}$") else {
            throw OpenRPCError.wrongParameter(input: storageSlot, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getStorageAt") { encoder in
            try encoder.encode(address)
            try encoder.encode(storageSlot)
            try encoder.encode(block)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Returns the number of transactions sent from an address.
    public static func eth_getTransactionCount(address: String,
                                               block: BlockNumberBlockTag) async throws -> [String] {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw OpenRPCError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionCount") { encoder in
            try encoder.encode(address)
            try encoder.encode(block)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<[String]>.self, from: data)
        return value.result
    }

    /// Summary: Returns code at a given address.
    public static func eth_getCode(address: String,
                                   block: BlockNumberBlockTag) async throws -> String {
        guard try checkParamter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$") else {
            throw OpenRPCError.wrongParameter(input: address, pattern: "^0x[0-9,a-f,A-F]{40}$")
        }
        let requestBody = RpcRequest(method: "eth_getCode") { encoder in
            try encoder.encode(address)
            try encoder.encode(block)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Signs and submits a transaction.
    public static func eth_sendTransaction(transaction: TransactionObjectWithSender) async throws -> String {
        let requestBody = RpcRequest(method: "eth_sendTransaction") { encoder in
            try encoder.encode(transaction)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Submits a raw transaction.
    public static func eth_sendRawTransaction(transaction: String) async throws -> String {
        guard try checkParamter(input: transaction, pattern: "^0x[0-9a-f]*$") else {
            throw OpenRPCError.wrongParameter(input: transaction, pattern: "^0x[0-9a-f]*$")
        }
        let requestBody = RpcRequest(method: "eth_sendRawTransaction") { encoder in
            try encoder.encode(transaction)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<String>.self, from: data)
        return value.result
    }

    /// Summary: Returns the information about a transaction requested by transaction hash.
    public static func eth_getTransactionByHash(transactionHash: String) async throws -> TransactionInformation {
        guard try checkParamter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$") else {
            throw OpenRPCError.wrongParameter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionByHash") { encoder in
            try encoder.encode(transactionHash)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<TransactionInformation>.self, from: data)
        return value.result
    }

    /// Summary: Returns information about a transaction by block hash and transaction index position.
    public static func eth_getTransactionByBlockHashAndIndex(blockHash: String,
                                                             transactionIndex: String) async throws -> TransactionInformation {
        guard try checkParamter(input: blockHash, pattern: "^0x[0-9a-f]{64}$") else {
            throw OpenRPCError.wrongParameter(input: blockHash, pattern: "^0x[0-9a-f]{64}$")
        }
        guard try checkParamter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw OpenRPCError.wrongParameter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionByBlockHashAndIndex") { encoder in
            try encoder.encode(blockHash)
            try encoder.encode(transactionIndex)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<TransactionInformation>.self, from: data)
        return value.result
    }

    /// Summary: Returns information about a transaction by block number and transaction index position.
    public static func eth_getTransactionByBlockNumberAndIndex(blockNumber: String,
                                                               transactionIndex: String) async throws -> TransactionInformation {
        guard try checkParamter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw OpenRPCError.wrongParameter(input: blockNumber, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        guard try checkParamter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$") else {
            throw OpenRPCError.wrongParameter(input: transactionIndex, pattern: "^0x([1-9a-f]+[0-9a-f]*|0)$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionByBlockNumberAndIndex") { encoder in
            try encoder.encode(blockNumber)
            try encoder.encode(transactionIndex)
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<TransactionInformation>.self, from: data)
        return value.result
    }

    /// Summary: Returns the receipt of a transaction by transaction hash.
    public static func eth_getTransactionReceipt(transactionHash: String?) async throws -> ReceiptInfo {
        if let transactionHash = transactionHash,
           try checkParamter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$") {
            throw OpenRPCError.wrongParameter(input: transactionHash, pattern: "^0x[0-9a-f]{64}$")
        }
        let requestBody = RpcRequest(method: "eth_getTransactionReceipt") { encoder in
            if let transactionHash = transactionHash { try encoder.encode(transactionHash) }
        }
        let (data, _) = try await URLSession.shared.data(for: request(for: JSONEncoder().encode(requestBody)))
        let value = try JSONDecoder().decode(RpcResult<ReceiptInfo>.self, from: data)
        return value.result
    }
}

