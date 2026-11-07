
import Foundation
import Supabase

enum SupabaseManager {
    static let client = SupabaseClient(
        supabaseURL: URL(
            string: "https://pnqnzulkrpdnuuaafqtx.supabase.co"
        )!,
        supabaseKey: "sb_publishable_OW0eoBpXj-V0L1n6cfV1kg_eBl9nuIZ"
    )
}

