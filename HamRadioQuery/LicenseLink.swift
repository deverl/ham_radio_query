import Foundation

/// Where **Open This License** looks up the selected call sign.
enum LicenseLink: String, CaseIterable, Identifiable, Sendable {
    case fcc
    case qrz
    case radioid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fcc: "FCC"
        case .qrz: "QRZ"
        case .radioid: "RadioID"
        }
    }

    var menuTitle: String { "Open This License at \(title)" }

    private static let key = "HamRadioQuery.licenseLink"

    static func load() -> LicenseLink {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let link = LicenseLink(rawValue: raw)
        else { return .fcc }
        return link
    }

    static func save(_ link: LicenseLink) {
        UserDefaults.standard.set(link.rawValue, forKey: key)
    }

    /// A browser destination for one license. The FCC page is the license itself.
    /// `systemID` is the FCC unique system identifier, which the detail page calls `licKey`.
    func page(callSign: String, systemID: String) -> LicensePage? {
        switch self {
        case .qrz, .radioid:
            let call = callSign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard call.range(of: #"^[A-Z0-9]{1,10}$"#, options: .regularExpression) != nil else { return nil }
            let address = self == .qrz
                ? "https://www.qrz.com/db/\(call)"
                : "https://radioid.net/database/search?callsign=\(call)"
            guard let url = URL(string: address) else { return nil }
            return .url(url)
        case .fcc:
            let identifier = systemID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard identifier.range(of: #"^[0-9]{1,15}$"#, options: .regularExpression) != nil,
                  let url = URL(string: "https://wireless2.fcc.gov/UlsApp/UlsSearch/license.jsp?licKey=\(identifier)")
            else { return nil }
            return .url(url)
        }
    }
}

enum LicensePage: Equatable, Sendable {
    case url(URL)
}
