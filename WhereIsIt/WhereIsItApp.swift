
import SwiftUI

@main
struct WhereIsItApp: App {

    @AppStorage("appearanceMode")
    private var appearanceMode = "system"

    @AppStorage("textSize")
    private var textSize = "standard"

    private var selectedColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }

    private var selectedDynamicTypeSize: DynamicTypeSize? {
        switch textSize {
        case "small":
            return .small
        case "standard":
            return nil
        case "large":
            return .xxxLarge
        case "extraLarge":
            return .accessibility1
        case "maximum":
            return .accessibility3
        default:
            return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(selectedColorScheme)
                .modifier(
                    TextSizePreferenceModifier(
                        textSize: selectedDynamicTypeSize
                    )
                )
        }
    }
}

private struct TextSizePreferenceModifier: ViewModifier {
    let textSize: DynamicTypeSize?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let textSize {
            content.dynamicTypeSize(textSize)
        } else {
            content
        }
    }
}

