import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: 1)
    }
}

/// Same eight looks as the web version.
struct PaperTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let paper: UIColor
    let line: UIColor
    let border: UIColor
    let header: UIColor
    let accent: UIColor
    let ink: UIColor
    let muted: UIColor
    let chrome: UIColor
    let desk: UIColor
    let fontName: String
    let boldFontName: String
    let dark: Bool

    static func == (a: PaperTheme, b: PaperTheme) -> Bool { a.id == b.id }

    func font(_ size: CGFloat, bold: Bool = false) -> UIFont {
        UIFont(name: bold ? boldFontName : fontName, size: size)
            ?? (bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size))
    }

    static let all: [PaperTheme] = [
        PaperTheme(id: "classic", name: "Classic", paper: UIColor(hex: 0xfffdf8), line: UIColor(hex: 0xd8d3c6), border: UIColor(hex: 0x2b3a4a),
                   header: UIColor(hex: 0xe9edf2), accent: UIColor(hex: 0x2f5d8a), ink: UIColor(hex: 0x1b2a41), muted: UIColor(hex: 0x6b7685),
                   chrome: UIColor(hex: 0x2b3a4a), desk: UIColor(hex: 0xbfc6d0), fontName: "Georgia", boldFontName: "Georgia-Bold", dark: false),
        PaperTheme(id: "blush", name: "Blush", paper: UIColor(hex: 0xfffafb), line: UIColor(hex: 0xf1d3dc), border: UIColor(hex: 0xb04870),
                   header: UIColor(hex: 0xfde6ee), accent: UIColor(hex: 0xd9537f), ink: UIColor(hex: 0x4a2335), muted: UIColor(hex: 0x9a6f80),
                   chrome: UIColor(hex: 0xc0426c), desk: UIColor(hex: 0xf0cfd9), fontName: "Didot", boldFontName: "Didot-Bold", dark: false),
        PaperTheme(id: "lavender", name: "Lavender", paper: UIColor(hex: 0xfcfaff), line: UIColor(hex: 0xe0d7f2), border: UIColor(hex: 0x5f4796),
                   header: UIColor(hex: 0xece5fa), accent: UIColor(hex: 0x7a59c9), ink: UIColor(hex: 0x31214f), muted: UIColor(hex: 0x7d6f9b),
                   chrome: UIColor(hex: 0x5f4796), desk: UIColor(hex: 0xd6cdea), fontName: "AvenirNext-Regular", boldFontName: "AvenirNext-DemiBold", dark: false),
        PaperTheme(id: "sage", name: "Sage", paper: UIColor(hex: 0xfbfcf6), line: UIColor(hex: 0xd3dcc5), border: UIColor(hex: 0x43623f),
                   header: UIColor(hex: 0xe5eed9), accent: UIColor(hex: 0x5a8554), ink: UIColor(hex: 0x1f3320), muted: UIColor(hex: 0x66795f),
                   chrome: UIColor(hex: 0x43623f), desk: UIColor(hex: 0xc8d4bb), fontName: "AvenirNext-Regular", boldFontName: "AvenirNext-DemiBold", dark: false),
        PaperTheme(id: "ocean", name: "Ocean", paper: UIColor(hex: 0xfbfdff), line: UIColor(hex: 0xcddfec), border: UIColor(hex: 0x1c5a86),
                   header: UIColor(hex: 0xe0eef8), accent: UIColor(hex: 0x1f78b4), ink: UIColor(hex: 0x0b2c47), muted: UIColor(hex: 0x5f7f96),
                   chrome: UIColor(hex: 0x1c5a86), desk: UIColor(hex: 0xb9d0e0), fontName: "HelveticaNeue", boldFontName: "HelveticaNeue-Bold", dark: false),
        PaperTheme(id: "kraft", name: "Kraft", paper: UIColor(hex: 0xecdcbc), line: UIColor(hex: 0xcdb68b), border: UIColor(hex: 0x4e331a),
                   header: UIColor(hex: 0xdcc79c), accent: UIColor(hex: 0x8a5522), ink: UIColor(hex: 0x2b1a0b), muted: UIColor(hex: 0x7d6747),
                   chrome: UIColor(hex: 0x4e331a), desk: UIColor(hex: 0xb79f78), fontName: "AmericanTypewriter", boldFontName: "AmericanTypewriter-Bold", dark: false),
        PaperTheme(id: "charcoal", name: "Charcoal", paper: UIColor(hex: 0x1e2125), line: UIColor(hex: 0x363b42), border: UIColor(hex: 0x98a1ab),
                   header: UIColor(hex: 0x2a2f35), accent: UIColor(hex: 0x3dbba8), ink: UIColor(hex: 0xeef0f2), muted: UIColor(hex: 0x8c96a0),
                   chrome: UIColor(hex: 0x121417), desk: UIColor(hex: 0x0b0c0e), fontName: "AvenirNext-Regular", boldFontName: "AvenirNext-DemiBold", dark: true),
        PaperTheme(id: "mono", name: "Mono", paper: UIColor(hex: 0xffffff), line: UIColor(hex: 0xdedede), border: UIColor(hex: 0x111111),
                   header: UIColor(hex: 0xf1f1f1), accent: UIColor(hex: 0x111111), ink: UIColor(hex: 0x111111), muted: UIColor(hex: 0x707070),
                   chrome: UIColor(hex: 0x111111), desk: UIColor(hex: 0xd4d4d4), fontName: "HelveticaNeue", boldFontName: "HelveticaNeue-Bold", dark: false)
    ]
}
