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
    @Published var lastError: String? = nil
    
    private var db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    
    init() {
        listenToMessages()
    }
    
    deinit {
        listenerRegistration?.remove()
    }
    
    func listenToMessages() {
        listenerRegistration?.remove()
        
        listenerRegistration = db.collection("messages")
            .order(by: "timestamp", descending: false)
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
                
                self.messages = documents.compactMap { document -> ChatMessage? in
                    try? document.data(as: ChatMessage.self)
                }
            }
    }
    
    func sendMessage(text: String) {
        guard let user = Auth.auth().currentUser else {
            lastError = "You must be signed in to send messages."
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
        } catch {
            lastError = "Error sending message: \(error.localizedDescription)"
        }
    }
}
