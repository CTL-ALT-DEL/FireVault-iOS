import Foundation
import Supabase

#if !DEBUG
#error("Recovery test source must never be archived or distributed. Use the production main branch for releases.")
#endif

enum SupabaseManager {
    // Test-only public project values. Never put a service_role key in the app.
    private static let projectURL = "https://llfvzebabfkxslrlgwav.supabase.co"
    private static let publishableKey = "sb_publishable_D_Q1A5fityqkpjUcacCi5w__u-Vk0og"
    static let authCallbackURL = URL(string: "firevault://auth-callback")!

    static let client = SupabaseClient(
        supabaseURL: URL(string: projectURL)!,
        supabaseKey: publishableKey,
        options: .init(
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )
}
