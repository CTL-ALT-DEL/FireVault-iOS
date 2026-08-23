import SwiftUI
import Supabase
import Combine
import WebKit

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

    func signIn(email: String, password: String, captchaToken: String) async {
        guard !isWorking else { return }
        clearMessages()
        isWorking = true
        defer { isWorking = false }

        do {
            let session = try await SupabaseManager.client.auth.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                captchaToken: captchaToken
            )
            signedInEmail = session.user.email?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            phase = .signedIn
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func signUp(email: String, password: String, captchaToken: String) async {
        guard !isWorking else { return }
        clearMessages()
        isWorking = true
        defer { isWorking = false }

        do {
            let response = try await SupabaseManager.client.auth.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                redirectTo: SupabaseManager.authCallbackURL,
                captchaToken: captchaToken
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

    func requestPasswordReset(email: String, captchaToken: String) async {
        guard !isWorking else { return }
        clearMessages()
        isWorking = true
        defer { isWorking = false }

        do {
            try await SupabaseManager.client.auth.resetPasswordForEmail(
                email.trimmingCharacters(in: .whitespacesAndNewlines),
                redirectTo: Self.passwordResetURL,
                captchaToken: captchaToken
            )
            confirmationMessage = "Password reset email sent. Open the secure link to choose a new password."
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
        if message.range(of: "captcha", options: .caseInsensitive) != nil ||
            message.range(of: "challenge", options: .caseInsensitive) != nil {
            return "Security verification expired or could not be confirmed. Please try again."
        }
        return message.isEmpty ? "Something went wrong. Please try again." : message
    }

    private static let passwordResetURL: URL = {
        var components = URLComponents(string: "https://firevault.bannerman.us/auth-callback.html")!
        components.queryItems = [
            URLQueryItem(name: "type", value: "reset"),
            URLQueryItem(name: "next", value: "auth.html?mode=reset")
        ]
        return components.url!
    }()
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
    private enum ProtectedAuthAction: String, Identifiable {
        case login
        case signup
        case passwordReset

        var id: String { rawValue }

        var challengeDescription: String {
            switch self {
            case .login:
                return "Verify this sign-in request."
            case .signup:
                return "Verify this new account request."
            case .passwordReset:
                return "Verify this password reset request."
            }
        }
    }

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
    @State private var protectedAction: ProtectedAuthAction?
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
        .sheet(item: $protectedAction) { action in
            FireVaultTurnstileChallengeView(
                purpose: action.challengeDescription,
                onToken: { token in
                    protectedAction = nil
                    perform(action, captchaToken: token)
                },
                onCancel: {
                    protectedAction = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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

            if mode == .login {
                Button("Forgot password?") {
                    requestPasswordReset()
                }
                .font(.subheadline.weight(.semibold))
                .disabled(authentication.isWorking)
            }

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

        switch mode {
        case .login:
            protectedAction = .login
        case .signup:
            protectedAction = .signup
        }
    }

    private func requestPasswordReset() {
        authentication.clearMessages()
        focusedField = nil

        guard !normalizedEmail.isEmpty,
              normalizedEmail.contains("@"),
              normalizedEmail.contains(".") else {
            authentication.errorMessage = "Enter your email address first."
            return
        }

        protectedAction = .passwordReset
    }

    private func perform(_ action: ProtectedAuthAction, captchaToken: String) {
        Task {
            switch action {
            case .login:
                await authentication.signIn(
                    email: normalizedEmail,
                    password: password,
                    captchaToken: captchaToken
                )
            case .signup:
                await authentication.signUp(
                    email: normalizedEmail,
                    password: password,
                    captchaToken: captchaToken
                )
            case .passwordReset:
                await authentication.requestPasswordReset(
                    email: normalizedEmail,
                    captchaToken: captchaToken
                )
            }
        }
    }
}

private struct FireVaultTurnstileChallengeView: View {
    let purpose: String
    let onToken: (String) -> Void
    let onCancel: () -> Void

    @State private var challengeID = UUID()
    @State private var isReady = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(spacing: 7) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(NativeShellPalette.red)

                    Text("Security Verification")
                        .font(.title3.weight(.bold))

                    Text(purpose)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                ZStack {
                    FireVaultTurnstileWebView(
                        challengeID: challengeID,
                        onReady: {
                            isReady = true
                            errorMessage = nil
                        },
                        onToken: onToken,
                        onError: { message in
                            isReady = false
                            errorMessage = message
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if !isReady, errorMessage == nil {
                        ProgressView("Loading secure verification…")
                            .tint(NativeShellPalette.red)
                    }
                }
                .frame(minHeight: 150, maxHeight: 230)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                if let errorMessage {
                    VStack(spacing: 10) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)

                        Button("Try Again") {
                            isReady = false
                            self.errorMessage = nil
                            challengeID = UUID()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Text("Protected by Cloudflare Turnstile. No password or account data is shown in this verification window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .navigationTitle("FireVault PRO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

private struct FireVaultTurnstileWebView: UIViewRepresentable {
    let challengeID: UUID
    let onReady: () -> Void
    let onToken: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReady: onReady, onToken: onToken, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: Coordinator.messageHandlerName)
        contentController.addUserScript(
            WKUserScript(
                source: "document.documentElement.style.visibility='hidden';",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        context.coordinator.load(challengeID: challengeID, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateCallbacks(onReady: onReady, onToken: onToken, onError: onError)
        if context.coordinator.loadedChallengeID != challengeID {
            context.coordinator.load(challengeID: challengeID, in: webView)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.messageHandlerName
        )
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageHandlerName = "firevaultTurnstile"

        private var onReady: () -> Void
        private var onToken: (String) -> Void
        private var onError: (String) -> Void
        private var completed = false
        fileprivate var loadedChallengeID: UUID?

        init(
            onReady: @escaping () -> Void,
            onToken: @escaping (String) -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.onReady = onReady
            self.onToken = onToken
            self.onError = onError
        }

        func updateCallbacks(
            onReady: @escaping () -> Void,
            onToken: @escaping (String) -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.onReady = onReady
            self.onToken = onToken
            self.onError = onError
        }

        func load(challengeID: UUID, in webView: WKWebView) {
            loadedChallengeID = challengeID
            completed = false

            var components = URLComponents(string: "https://firevault.bannerman.us/auth.html")!
            components.queryItems = [
                URLQueryItem(name: "native_turnstile", value: "1"),
                URLQueryItem(name: "challenge", value: challengeID.uuidString)
            ]
            webView.load(URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(Self.bootstrapScript) { [weak self] _, error in
                if let error {
                    self?.reportError("Security verification could not start: \(error.localizedDescription)")
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            reportError("Unable to reach the security service. Check your connection and try again.")
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            reportError("The security verification page did not finish loading. Please try again.")
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame != false,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let allowedHosts = ["firevault.bannerman.us", "challenges.cloudflare.com"]
            let allowed = url.scheme == "https" && allowedHosts.contains(url.host ?? "")
            decisionHandler(allowed ? .allow : .cancel)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.messageHandlerName,
                  let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else { return }

            switch type {
            case "ready":
                onReady()
            case "success":
                guard !completed,
                      let token = payload["token"] as? String,
                      !token.isEmpty,
                      token.count <= 2_048 else {
                    reportError("The security verification returned an invalid response. Please try again.")
                    return
                }
                completed = true
                onToken(token)
            case "expired":
                reportError("Security verification expired. Please try again.")
            default:
                reportError((payload["message"] as? String) ?? "Security verification failed. Please try again.")
            }
        }

        private func reportError(_ message: String) {
            guard !completed else { return }
            onError(message)
        }

        private static let bootstrapScript = #"""
        (() => {
          if (window.__firevaultNativeTurnstileStarted) return;
          window.__firevaultNativeTurnstileStarted = true;

          const send = payload => {
            window.webkit.messageHandlers.firevaultTurnstile.postMessage(payload);
          };

          document.title = "FireVault PRO Security Verification";
          document.body.innerHTML = `
            <main id="firevault-native-shell">
              <div class="native-kicker">SECURE ACCOUNT ACCESS</div>
              <div id="firevault-native-turnstile"></div>
              <p id="firevault-native-status">Completing secure verification…</p>
            </main>`;

          const style = document.createElement("style");
          style.textContent = `
            :root { color-scheme: light; }
            html, body { margin: 0; min-height: 100%; background: #f7f9fc; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
            body { display: grid; place-items: center; color: #142033; }
            #firevault-native-shell { box-sizing: border-box; width: 100%; padding: 18px; text-align: center; }
            .native-kicker { margin-bottom: 14px; color: #d91f2d; font-size: 12px; font-weight: 800; letter-spacing: .08em; }
            #firevault-native-turnstile { display: flex; min-height: 70px; align-items: center; justify-content: center; }
            #firevault-native-status { margin: 12px 0 0; color: #64748b; font-size: 13px; }
          `;
          document.head.appendChild(style);
          document.documentElement.style.visibility = "visible";

          let attempts = 0;
          const start = () => {
            const sitekey = String(window.FIREVAULT_CONFIG?.turnstileSiteKey || "").trim();
            if (!sitekey || !window.turnstile?.render) {
              attempts += 1;
              if (attempts < 150) {
                window.setTimeout(start, 100);
                return;
              }
              send({ type: "error", message: "Security verification could not load. Check your connection and try again." });
              return;
            }

            try {
              window.turnstile.render("#firevault-native-turnstile", {
                sitekey,
                theme: "light",
                size: "flexible",
                appearance: "always",
                callback: token => send({ type: "success", token }),
                "expired-callback": () => send({ type: "expired" }),
                "timeout-callback": () => send({ type: "error", message: "Security verification timed out. Please try again." }),
                "error-callback": () => send({ type: "error", message: "Security verification failed to load. Please try another network or disable content blocking." })
              });
              send({ type: "ready" });
            } catch (error) {
              send({ type: "error", message: "Security verification could not start. Please try again." });
            }
          };
          start();
        })();
        """#
    }
}

struct FireVaultAccountSettingsView: View {
    @EnvironmentObject private var authentication: FireVaultAuthentication
    @State private var showsSignOutConfirmation = false

    private var accountEmail: String {
        let email = authentication.signedInEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? "Signed in" : email
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
