import Foundation
import Supabase

enum SupabaseManager {
    // Replace only these public values from Supabase Dashboard > Project Settings > API.
    // Never put a service_role key in the app.
    private static let projectURL = "https://dgzriqqflbhioflblirm.supabase.co"
    private static let publishableKey = "sb_publishable_PXoixNhmmfQg4TcbIRWGjg_d-BvtYS5"
    static let authCallbackURL = URL(string: "firevault://auth-callback")!

    static let client = SupabaseClient(
        supabaseURL: URL(string: projectURL)!,
        supabaseKey: publishableKey
    )
}
