import SwiftUI
import Supabase
import Combine

@MainActor
final class FireVaultAuthentication: ObservableObject {
    enum Phase {
        case loading
        case signedOut
        case signedIn
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var confirmationMessage: String?
    @Published private(set) var signedInEmail = ""

    private var hasStarted = false
    private var listenerTask: Task<Void, Never>?

    deinit {
        listenerTask?.cancel()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        listenerTask = Task { [weak self] in
            for await (_, session) in SupabaseManager.client.auth.authStateChanges {
                guard let self, !Task.isCancelled else { return }
                phase = session == nil || session?.isExpired == true ? .signedOut : .signedIn
                signedInEmail = session?.user.email?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() ?? ""
            }
        }
    }

    func signIn(email: String, password: String) async {
        guard !isWorking else { return }
        clearMessages()
        isWorking = true
        defer { isWorking = false }

        do {
            let session = try await SupabaseManager.client.auth.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            signedInEmail = session.user.email?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            phase = .signedIn
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func signUp(email: String, password: String) async {
        guard !isWorking else { return }
        clearMessages()
        isWorking = true
        defer { isWorking = false }

        do {
            let response = try await SupabaseManager.client.auth.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                redirectTo: SupabaseManager.authCallbackURL
            )

            if response.session == nil {
                confirmationMessage = "Account created. Check your email and confirm your address, then sign in."
                phase = .signedOut
            } else {
                phase = .signedIn
            }
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func signOut() async {
        guard !isWorking else { return }
        clearMessages()
        isWorking = true
        defer { isWorking = false }

        do {
            try await SupabaseManager.client.auth.signOut()
            signedInEmail = ""
            phase = .signedOut
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func deleteAccount(store: FireVaultStore) async {
        guard !isWorking else { return }
        clearMessages()
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await SupabaseManager.client.auth.session
            let userID = session.user.id
            _ = try await SupabaseManager.client.functions.invoke("delete-account")
            let removedLocalVault = store.eraseLocalAccountDataAfterCloudDeletion(for: userID)
            try? await SupabaseManager.client.auth.signOut()
            signedInEmail = ""
            confirmationMessage = removedLocalVault
                ? "Your FireVault account and its local account records were deleted."
                : "Your cloud account was deleted. This iPhone's local vault belongs to a different login and was kept safely on the device."
            phase = .signedOut
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func clearMessages() {
        errorMessage = nil
        confirmationMessage = nil
    }

    private func friendlyMessage(for error: Error) -> String {
        let message = error.localizedDescription
        return message.isEmpty ? "Something went wrong. Please try again." : message
    }
}

struct FireVaultAuthGate: View {
    @StateObject private var authentication = FireVaultAuthentication()
    @AppStorage("firevault.native.settings.appearance.v1") private var storedAppearance = FireVaultAppearanceMode.system.rawValue

    var body: some View {
        Group {
            switch authentication.phase {
            case .loading:
                ZStack {
                    NativeShellPalette.background.ignoresSafeArea()
                    ProgressView("Checking your session…")
                        .tint(NativeShellPalette.red)
                        .foregroundStyle(.secondary)
                }
            case .signedOut:
                FireVaultAuthenticationView()
            case .signedIn:
                ContentView()
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .environmentObject(authentication)
        .onAppear {
            authentication.start()
        }
        .onOpenURL { url in
            if !FireVaultWidgetDeepLinkCenter.shared.receive(url) {
                SupabaseManager.client.auth.handle(url)
            }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch FireVaultAppearanceMode(rawValue: storedAppearance) ?? .system {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

private struct FireVaultAuthenticationView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case login = "Log In"
        case signup = "Sign Up"

        var id: String { rawValue }
    }

    @EnvironmentObject private var authentication: FireVaultAuthentication
    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showsPassword = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
        case confirmPassword
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationMessage: String? {
        guard !normalizedEmail.isEmpty else { return "Enter your email address." }
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            return "Enter a valid email address."
        }
        guard password.count >= 6 else { return "Password must contain at least 6 characters." }
        if mode == .signup, password != confirmPassword {
            return "The passwords do not match."
        }
        return nil
    }

    var body: some View {
        ZStack {
            NativeShellPalette.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    brand
                    form
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 24)
                .padding(.vertical, 44)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .tint(NativeShellPalette.red)
        .onChange(of: mode) {
            authentication.clearMessages()
            password = ""
            confirmPassword = ""
            focusedField = nil
        }
    }

    private var brand: some View {
        VStack(spacing: 16) {
            FireVaultProIconBadge(size: 112, cornerRadius: 25)
                .shadow(color: NativeShellPalette.red.opacity(0.25), radius: 22, y: 10)

            VStack(spacing: 5) {
                FireVaultProWordmark(fontSize: 32, proFontSize: 11)

                Text("Secure access to your field workspace")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var form: some View {
        VStack(spacing: 18) {
            Picker("Authentication mode", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 14) {
                fieldContainer {
                    Label("Email", systemImage: "envelope")
                        .foregroundStyle(.secondary)
                    TextField("name@company.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                }

                fieldContainer {
                    Label("Password", systemImage: "lock")
                        .foregroundStyle(.secondary)
                    Group {
                        if showsPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textContentType(mode == .signup ? .newPassword : .password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(mode == .signup ? .next : .go)
                    .onSubmit {
                        if mode == .signup {
                            focusedField = .confirmPassword
                        } else {
                            submit()
                        }
                    }

                    Button {
                        showsPassword.toggle()
                    } label: {
                        Image(systemName: showsPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
                }

                if mode == .signup {
                    fieldContainer {
                        Label("Confirm", systemImage: "lock.shield")
                            .foregroundStyle(.secondary)
                        SecureField("Confirm password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .confirmPassword)
                            .submitLabel(.go)
                            .onSubmit { submit() }
                    }
                }
            }

            if let error = authentication.errorMessage {
                message(error, symbol: "exclamationmark.triangle.fill", color: .red)
            }

            if let confirmation = authentication.confirmationMessage {
                message(confirmation, symbol: "envelope.badge", color: .green)
            }

            Button {
                submit()
            } label: {
                HStack {
                    if authentication.isWorking {
                        ProgressView().tint(.white)
                    }
                    Text(authentication.isWorking ? "Please wait…" : mode.rawValue)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .disabled(authentication.isWorking)

            if mode == .signup {
                Text("By creating an account, you agree to use FireVault Pro only for authorized company and customer data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(NativeShellPalette.hairline)
        }
    }

    private func fieldContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 11, content: content)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(NativeShellPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(NativeShellPalette.hairline)
            }
    }

    private func message(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    private func submit() {
        authentication.clearMessages()
        focusedField = nil

        if let validationMessage {
            authentication.errorMessage = validationMessage
            return
        }

        Task {
            switch mode {
            case .login:
                await authentication.signIn(email: normalizedEmail, password: password)
            case .signup:
                await authentication.signUp(email: normalizedEmail, password: password)
            }
        }
    }
}

struct FireVaultAccountProfileSections: View {
    @EnvironmentObject private var authentication: FireVaultAuthentication
    @ObservedObject var store: FireVaultStore
    @State private var showsSignOutConfirmation = false

    private var accountEmail: String {
        let email = authentication.signedInEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? "Signed in" : email
    }

    private var cloudSyncTint: Color {
        if store.cloudSyncErrorMessage != nil { return .orange }
        if store.isCloudSyncing { return NativeShellPalette.blue }
        if store.cloudLastSyncedAt == nil { return .secondary }
        return NativeShellPalette.green
    }

    private var cloudSyncSymbol: String {
        if store.isCloudSyncing { return "arrow.triangle.2.circlepath" }
        if store.cloudSyncErrorMessage != nil { return "exclamationmark.icloud.fill" }
        if store.cloudLastSyncedAt == nil { return "icloud.slash" }
        return "checkmark.icloud.fill"
    }

    private var lastSyncText: String {
        guard let date = store.cloudLastSyncedAt else { return "Not yet" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var lastCheckedText: String {
        guard let date = store.cloudLastCheckedAt else { return "Not yet" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        Group {
            Section("FireVault Account") {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(NativeShellPalette.green)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in as")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(accountEmail)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }

                Text("Connects this device, customer records, CSV imports, and the FireVault portal.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: cloudSyncSymbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(cloudSyncTint)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Account records")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(store.cloudSyncStatusText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(cloudSyncTint)
                    }

                    Spacer(minLength: 4)
                    if store.isCloudSyncing { ProgressView() }
                }

                HStack(spacing: 12) {
                    syncTimestamp(title: "Last synced", value: lastSyncText)
                    Divider().frame(height: 34)
                    syncTimestamp(title: "Last checked", value: lastCheckedText)
                }

                Button {
                    Task {
                        await store.syncAccountsNow()
                    }
                } label: {
                    HStack {
                        Label(
                            store.isCloudSyncing ? "Syncing…" : "Sync Now",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        Spacer()
                    }
                }
                .disabled(store.isCloudSyncing || store.demoMode)

                if store.isCloudSyncing, store.cloudSyncTotal > 0 {
                    ProgressView(value: Double(store.cloudSyncCompleted), total: Double(store.cloudSyncTotal)) {
                        Text("Backing up legacy accounts")
                    } currentValueLabel: {
                        Text("\(store.cloudSyncCompleted) of \(store.cloudSyncTotal)")
                    }
                }
                if let message = store.cloudSyncErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Cloud Sync")
            } footer: {
                Text(
                    store.demoMode
                        ? "Demo data stays on this iPhone."
                        : "FireVault checks automatically. Use Sync Now after portal changes or whenever you want an immediate check."
                )
            }

            Section {
                Button(role: .destructive) {
                    showsSignOutConfirmation = true
                } label: {
                    HStack {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        Spacer()
                        if authentication.isWorking {
                            ProgressView()
                        }
                    }
                }
                .disabled(authentication.isWorking)
            } footer: {
                Text("Signing out disconnects this device from your FireVault account. Local information remains on this device.")
            }
        }
        .confirmationDialog(
            "Sign out of FireVault Pro?",
            isPresented: $showsSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await authentication.signOut()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will return to the Log In or Sign Up screen.")
        }
    }

    private func syncTimestamp(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FireVaultAccountDeletionView: View {
    @EnvironmentObject private var authentication: FireVaultAuthentication
    @ObservedObject var store: FireVaultStore
    @State private var showsDeleteConfirmation = false

    var body: some View {
        Form {
            Section {
                Label("Permanent account deletion", systemImage: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                Text("This removes your FireVault cloud sign-in and associated cloud data. Local account records are cleared only when they belong to this login.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Delete FireVault Account", role: .destructive) {
                    showsDeleteConfirmation = true
                }
                .disabled(authentication.isWorking || store.isCloudSyncing)
            } footer: {
                Text("This action is provided separately from customer-account deletion and cannot be undone.")
            }
        }
        .navigationTitle("Account Deletion")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Permanently delete your FireVault account?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account and Data", role: .destructive) {
                Task { await authentication.deleteAccount(store: store) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. If cloud deletion fails, local data will remain on this iPhone.")
        }
    }
}
