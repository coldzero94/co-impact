import CoreLocation
import ImpactEngine
import MapKit
import SwiftUI

extension ActionKind {
    /// Opens the action outside the app (PRODUCT.md → Action catalog); `completion` gets whether the system opened it.
    @MainActor
    func run(with openURL: OpenURLAction, completion: @escaping (Bool) -> Void) {
        switch self {
        case .joinMeeting(let url), .openLink(let url):
            openURL(url, completion: completion)
        case .call(let number):
            guard let url = telURL(number) else { return completion(false) }
            openURL(url, completion: completion)
        case .directions(let place):
            let item = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude),
                                 address: place.address.flatMap { MKAddress(fullAddress: $0, shortAddress: nil) })
            item.name = place.title
            completion(item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault]))
        }
    }
}

/// A `tel:` URL from a detected phone number: ASCII digits, plus a leading `+` if it had one; nil without digits.
func telURL(_ number: String) -> URL? {
    let digits = number.filter { $0.isASCII && $0.isNumber }
    guard !digits.isEmpty else { return nil }
    let plus = number.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" : ""
    return URL(string: "tel:\(plus)\(digits)")
}

extension View {
    /// Says which action did not open, so a failed tap is never silent; the card stays not done.
    func actionFailureAlert(_ failed: Binding<ActionKind?>) -> some View {
        alert(failed.wrappedValue.map { "\($0.label) didn't open" } ?? "",
              isPresented: Binding(get: { failed.wrappedValue != nil }, set: { if !$0 { failed.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try again, or open it from your calendar.")
        }
    }
}
