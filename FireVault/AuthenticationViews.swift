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
                .preferredColorScheme(.dark)
            case .signedOut:
                FireVaultAuthenticationView()
                    .preferredColorScheme(.dark)
            case .signedIn:
                ContentView()
            }
        }
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
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.08))
        }
    }

    private func fieldContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 11, content: content)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(0.09))
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

struct FireVaultAccountSettingsView: View {
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

    var body: some View {
        Form {
            Section("FireVault Account") {
                LabeledContent {
                    Text(accountEmail)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label("Signed in as", systemImage: "person.crop.circle.fill")
                }

                Label {
                    Text("This account securely connects your iPhone, CSV imports, and FireVault web portal.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(NativeShellPalette.green)
                }
            }

            Section("Cloud Sync") {
                LabeledContent {
                    Label(store.cloudSyncStatusText, systemImage: cloudSyncSymbol)
                        .foregroundStyle(cloudSyncTint)
                } label: {
                    Text("Status")
                }

                LabeledContent("Last successful sync") {
                    Text(lastSyncText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
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
                        if store.isCloudSyncing {
                            ProgressView()
                        }
                    }
                }
                .disabled(store.isCloudSyncing || store.demoMode)

                if let message = store.cloudSyncErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text(
                    store.demoMode
                        ? "Demo data stays on this iPhone."
                        : "FireVault checks your account data when the app opens or becomes active. Tap Sync Now after website changes to refresh immediately."
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
        .navigationTitle("Account & Sign-In")
        .navigationBarTitleDisplayMode(.inline)
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
}

