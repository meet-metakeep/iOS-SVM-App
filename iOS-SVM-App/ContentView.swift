//
//  ContentView.swift
//  iOS-SVM-App
//
//  Created by Meet  on 29/08/25.
//

import SwiftUI
import MetaKeep
import SolanaSwift
import Foundation

struct ContentView: View {
    @State private var walletResult: String = ""
    @State private var solanaAddress: String = ""
    @State private var transactionResult: String = ""
    @State private var isLoading: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("MetaKeep Wallet")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Button(action: getWallet) {
                Text("Get Wallet")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 40)
            
            if !solanaAddress.isEmpty {
                VStack(spacing: 10) {
                    Text("Solana Wallet Address:")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(solanaAddress)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                        .textSelection(.enabled)
                    
                    Button(action: signAndSendTransaction) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .foregroundColor(.white)
                            }
                            Text(isLoading ? "Processing..." : "Sign & Send Transaction")
                        }
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isLoading ? Color.gray : Color.orange)
                        .cornerRadius(10)
                    }
                    .disabled(isLoading)
                }
                .padding(.horizontal)
            }
            
            if !walletResult.isEmpty {
                Text(walletResult)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
            
            if !transactionResult.isEmpty {
                ScrollView {
                    Text("Transaction Result:")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.bottom, 5)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if transactionResult.hasPrefix("SUCCESS:") {
                            Text("Transaction sent successfully!")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.green)
                            
                            if let txHash = extractTxHash(from: transactionResult) {
                                Text("Transaction Hash:")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.semibold)
                                
                                Link(destination: URL(string: "https://explorer.solana.com/tx/\(txHash)?cluster=devnet")!) {
                                    HStack {
                                        Text(txHash)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.blue)
                                            .underline()
                                        
                                        Image(systemName: "arrow.up.right.square")
                                            .foregroundColor(.blue)
                                            .font(.caption)
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                                }
                                
                                Text("")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        } else {
                            Text(transactionResult)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding()
        .onOpenURL { url in // Add onOpenURL handler
            MetaKeep.companion.resume(url: url.description) // Send callback to MetaKeep SDK
        }
    }
    
    private func getWallet() {
        // Use the static SDK instance from the main app
        let sdk = iOS_SVM_AppApp.sdk
        
        sdk.getWallet(
            callback: Callback(
                onSuccess: { (result: JsonResponse) in
                    DispatchQueue.main.async {
                        walletResult = "Success: \(result.description)"
                        
                        // Parse the JSON response to extract Solana address
                        let jsonString = result.description
                        if let jsonData = jsonString.data(using: .utf8) {
                            do {
                                if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                   let wallet = json["wallet"] as? [String: Any],
                                   let solAddress = wallet["solAddress"] as? String {
                                    solanaAddress = solAddress
                                    print("Solana Wallet Address: \(solAddress)")
                                }
                            } catch {
                                print("Error parsing JSON: \(error)")
                                solanaAddress = "Error parsing response"
                            }
                        }
                    }
                },
                onFailure: { (error: JsonResponse) in
                    DispatchQueue.main.async {
                        walletResult = "Failure: \(error.description)"
                        solanaAddress = ""
                    }
                }
            )
        )
    }
    
    private func signAndSendTransaction() {
        guard !solanaAddress.isEmpty else { return }
        
        isLoading = true
        transactionResult = ""
        
        Task {
            do {
                let transaction = try await buildSolanaTransaction()
                let signature = try await signTransactionWithMetaKeep(transaction: transaction)
                let txHash = try await sendTransactionToSolana(transaction: transaction, signature: signature)
                
                DispatchQueue.main.async {
                    self.transactionResult = "SUCCESS:\(txHash)"
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.transactionResult = "Error: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func buildSolanaTransaction() async throws -> SolanaSwift.Transaction {
        // Create API endpoint for Solana devnet
        let endpoint = APIEndPoint(
            address: "https://api.devnet.solana.com",
            network: .devnet
        )
        
        let apiClient = JSONRPCAPIClient(endpoint: endpoint)
        
        // Get latest blockhash (getRecentBlockhash may be disabled on some RPC nodes)
        struct LatestBlockhashRPC: Decodable { struct Value: Decodable { let blockhash: String }; let value: Value }
        let latest: LatestBlockhashRPC = try await apiClient.request(method: "getLatestBlockhash")
        let recentBlockhash = latest.value.blockhash
        
        // Create transfer instruction (sending 0.001 SOL to specified address)
        let fromPublicKey = try PublicKey(string: solanaAddress)
        let toPublicKey = try PublicKey(string: "6xEeDTksyAhBz7QBgzPmYxJN2zbmT7twx5rr1ejnaona")
        let lamports: UInt64 = 1000000 // 0.001 SOL
        
        let transferInstruction = SystemProgram.transferInstruction(
            from: fromPublicKey,
            to: toPublicKey,
            lamports: lamports
        )
        
        // Create transaction
        let transaction = SolanaSwift.Transaction(
            instructions: [transferInstruction],
            recentBlockhash: recentBlockhash,
            feePayer: fromPublicKey
        )
        
        return transaction
    }
    
    private func signTransactionWithMetaKeep(transaction: SolanaSwift.Transaction) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let message = try transaction.compileMessage()
                let serializedMessage = try message.serialize()
                let serializedHex = "0x" + serializedMessage.map { String(format: "%02x", $0) }.joined()
                
                let txnObject = """
                {
                    "serializedTransactionMessage": "\(serializedHex)"
                }
                """
                
                let sdk = iOS_SVM_AppApp.sdk
                
                sdk.signTransaction(
                    transaction: try JsonRequest(jsonString: txnObject),
                    reason: "Transfer 0.001 SOL to recipient",
                    callback: Callback(
                        onSuccess: { (result: JsonResponse) in
                            if let jsonData = result.description.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                               let signature = json["signature"] as? String {
                                continuation.resume(returning: signature)
                            } else {
                                continuation.resume(throwing: NSError(domain: "SigningError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse signature from response"]))
                            }
                        },
                        onFailure: { (error: JsonResponse) in
                            continuation.resume(throwing: NSError(domain: "SigningError", code: -1, userInfo: [NSLocalizedDescriptionKey: error.description]))
                        }
                    )
                )
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func sendTransactionToSolana(transaction: SolanaSwift.Transaction, signature: String) async throws -> String {
        // Create API endpoint for Solana devnet
        let endpoint = APIEndPoint(
            address: "https://api.devnet.solana.com",
            network: .devnet
        )
        
        let apiClient = JSONRPCAPIClient(endpoint: endpoint)
        
        // Convert hex signature to bytes and add to transaction
        let signatureHex = signature.replacingOccurrences(of: "0x", with: "")
        let signatureBytes = Data(hex: signatureHex) ?? Data()
        
        // Create a mutable copy of the transaction and add signature
        var signedTransaction = transaction
        signedTransaction.signatures = [SolanaSwift.Signature(signature: signatureBytes, publicKey: transaction.feePayer!)]
        
        // Serialize and send transaction
        let serializedTransaction = try signedTransaction.serialize()
        let base64Transaction = serializedTransaction.base64EncodedString()
        
        // Send transaction to Solana using sendTransaction method (base64 encoded)
        struct SendTxParams: Encodable { let encoding: String = "base64" }
        let txHash: String = try await apiClient.request(method: "sendTransaction", params: [base64Transaction, SendTxParams()])
        
        return txHash
    }
    
    // Helper function to extract transaction hash from result string
    private func extractTxHash(from result: String) -> String? {
        if result.hasPrefix("SUCCESS:") {
            return String(result.dropFirst("SUCCESS:".count))
        }
        return nil
    }
}

// Extension to handle hex string conversion
extension Data {
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        var i = hex.startIndex
        for _ in 0..<len {
            let j = hex.index(i, offsetBy: 2)
            let bytes = hex[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }
}

#Preview {
    ContentView()
}
