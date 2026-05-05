import Foundation

enum AppConfig {
    static let supabaseURL = "https://puckyaxybgxipoqdrekt.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB1Y2t5YXh5Ymd4aXBvcWRyZWt0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk4MTAwMDAsImV4cCI6MjA4NTM4NjAwMH0.wuIuThvtz0eS5hJNSdhfdRemcdE8PmS-cWSIXKLziYs"
    // Use the www subdomain directly: seatbee.app → www.seatbee.app
    // returns a 307 redirect, and URLSession strips the Authorization
    // header on cross-origin redirects, so requests hit the API
    // unauthenticated. Hitting www directly avoids the redirect entirely.
    static let aiAPIBaseURL = "https://www.seatbee.app/api/ai"
    static let guestAPIBaseURL = "https://www.seatbee.app/api/guest"
    static let appScheme = "seatbee"
    static let universalLinkDomain = "seatbee.app"
    static let googlePlacesAPIKey = "" // Add your Google Places API key here
}
