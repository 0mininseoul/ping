import Foundation
import FirebaseAuth
import FirebaseCore
@preconcurrency import FirebaseFirestore

@MainActor
final class FirebaseClient: ObservableObject {
    static let shared = FirebaseClient()

    @Published private(set) var currentUid: String?
    @Published private(set) var isConfigured = false

    private(set) var db: Firestore?

    private init() {}

    func configureIfNeeded() throws {
        guard FirebaseApp.app() == nil else {
            db = Firestore.firestore()
            isConfigured = true
            return
        }

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            throw PingError.firebaseConfigurationMissing
        }

        FirebaseApp.configure()
        db = Firestore.firestore()
        isConfigured = true
    }

    func bootstrap() async throws -> String {
        try configureIfNeeded()

        if let user = Auth.auth().currentUser {
            currentUid = user.uid
            return user.uid
        }

        let result = try await Auth.auth().signInAnonymously()
        currentUid = result.user.uid
        return result.user.uid
    }

    func requireDB() throws -> Firestore {
        guard let db else { throw PingError.firestoreUnavailable }
        return db
    }
}
