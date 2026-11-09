import CoreLocation
import ImpactEngine
import MapKit
import SwiftUI

extension ActionKind {
    /// Opens the action outside the app (PRODUCT.md → Action catalog); `completion` gets whether the system
    /// accepted it (it cannot see a call the user then cancels).
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

/// A `tel:` URL for a phone number from the engine's detector: the ASCII digits, plus a leading `+`; nil
/// when it has letters (e.g. 1-800-FLOWERS) or no digits.
/// shortcut: the detector puts an extension or a pause after `;` or `,`, and only the number before it is
/// dialed; pass the rest as a `,` pause once a device shows the Phone app accepts it (step 10).
func telURL(_ number: String) -> URL? {
    let main = number.prefix { $0 != ";" && $0 != "," }
    let digits = main.filter { $0.isASCII && $0.isNumber }
    guard !digits.isEmpty, !main.contains(where: \.isLetter) else { return nil }
    let plus = main.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" : ""
    return URL(string: "tel:\(plus)\(digits)")
}

extension View {
    /// Says which action did not open, so a failed tap is never silent; the card stays not done.
    func actionFailureAlert(_ failed: Binding<ActionKind?>) -> some View {
        alert(failed.wrappedValue?.failureTitle ?? "",
              isPresented: Binding(get: { failed.wrappedValue != nil }, set: { if !$0 { failed.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open it from the event in your calendar instead.")
        }
    }
}
