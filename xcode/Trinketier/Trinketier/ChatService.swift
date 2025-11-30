import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

struct ChatMessage: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var text: String
    var sender: String
    var timestamp: Date
    
    // Helper to determine if the message is from the current user
    func isFromCurrentUser() -> Bool {
        guard let currentUser = Auth.auth().currentUser else { return false }
        return sender == currentUser.uid
    }
}

class ChatService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var hasUnreadMessages: Bool = false
    @Published var lastError: String? = nil
    
    private let limit = 100
    
    private var db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    private var lastReadTimestamp: Date = Date()
    
    private var lastMessageSentTime: Date?
    
    init() {
        listenToMessages()
    }
    
    deinit {
        stop()
    }
    
    func stop() {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }
    
    func markAsRead() {
        hasUnreadMessages = false
        lastReadTimestamp = Date()
    }
    
    func listenToMessages() {
        listenerRegistration?.remove()
        
        listenerRegistration = db.collection("messages")
            .order(by: "timestamp", descending: false)
            .limit(toLast: limit) // Optimization: Only load the last 100 messages
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.lastError = "Error fetching messages: \(error.localizedDescription)"
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    self.messages = []
                    return
                }
                
                let newMessages = documents.compactMap { document -> ChatMessage? in
                    try? document.data(as: ChatMessage.self)
                }
                
                // Check for unread messages
                // We only care about messages that are NEWER than our last read timestamp
                // AND are NOT from the current user
                if let lastMsg = newMessages.last,
                   !lastMsg.isFromCurrentUser(),
                   lastMsg.timestamp > self.lastReadTimestamp {
                    self.hasUnreadMessages = true
                }
                
                self.messages = newMessages
            }
    }
    
    func sendMessage(text: String) {
        guard let user = Auth.auth().currentUser else {
            lastError = "You must be signed in to send messages."
            return
        }
        
        // Rate Limiting: Check if 2 seconds have passed since the last message
        if let lastSent = lastMessageSentTime, Date().timeIntervalSince(lastSent) < 2.0 {
            lastError = "Please wait a moment before sending another message."
            return
        }
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        let newMessage = ChatMessage(
            text: trimmedText,
            sender: user.uid,
            timestamp: Date()
        )
        
        do {
            try db.collection("messages").addDocument(from: newMessage)
            lastMessageSentTime = Date()
            cleanupOldMessages() // Trigger cleanup after sending
        } catch {
            lastError = "Error sending message: \(error.localizedDescription)"
        }
    }
    
    private func cleanupOldMessages() {
        // Query all messages ordered by timestamp
        db.collection("messages")
            .order(by: "timestamp", descending: false)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self, let documents = snapshot?.documents else { return }
                
                if documents.count > limit {
                    let messagesToDeleteCount = documents.count - limit
                    let messagesToDelete = documents.prefix(messagesToDeleteCount)
                    
                    let batch = self.db.batch()
                    for document in messagesToDelete {
                        batch.deleteDocument(document.reference)
                    }
                    
                    batch.commit { error in
                        if let error = error {
                            print("Error cleaning up old messages: \(error)")
                        }
                    }
                }
            }
    }
}
