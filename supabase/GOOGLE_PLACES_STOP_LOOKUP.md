# Google Places stop lookup

FireVault calls the authenticated `google-places-stop-lookup` Edge Function when a technician selects **Check Google Places** while reviewing an unclassified Trip Log stop. The Google API key remains server-side and is never included in the iOS application.

## One-time Supabase setup

1. In Google Cloud, enable **Places API (New)** for the FireVault project and create a server key restricted to that API.
2. In Supabase Dashboard, open **Edge Functions → Secrets** and add:

   ```text
   GOOGLE_PLACES_API_KEY=your_restricted_server_key
   ```

3. Deploy `supabase/functions/google-places-stop-lookup` with JWT verification enabled.

The function accepts only authenticated FireVault calls, validates coordinates, limits the search radius to 250 meters, requests only the required Google fields, excludes permanently closed places, and returns at most five distance-ranked matches. It does not log stop coordinates.
