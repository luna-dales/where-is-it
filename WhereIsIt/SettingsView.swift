
import SwiftUI

struct SettingsView: View {

    @AppStorage("appearanceMode")
    private var appearanceMode = "system"

    @AppStorage("textSize")
    private var textSize = "standard"

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearanceMode) {
                    Label("System", systemImage: "iphone")
                        .tag("system")

                    Label("Light", systemImage: "sun.max")
                        .tag("light")

                    Label("Dark", systemImage: "moon")
                        .tag("dark")
                }
                .pickerStyle(.inline)
            } header: {
                Text("Display")
            } footer: {
                Text(
                    "System follows your iPhone's appearance. " +
                    "Light and Dark override the system setting."
                )
            }

            Section {
                Picker("Text Size", selection: $textSize) {
                    Text("Small").tag("small")
                    Text("Standard (iPhone Setting)").tag("standard")
                    Text("Large").tag("large")
                    Text("Extra Large").tag("extraLarge")
                    Text("Maximum").tag("maximum")
                }
                .pickerStyle(.navigationLink)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Text Size Preview")
                        .font(.headline)

                    Text("Find groceries more easily.")
                        .font(.body)

                    Text("Aisle 7, right side, second shelf.")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } header: {
                Text("Text Size")
            } footer: {
                Text(
                    "Standard follows your iPhone's text-size setting. " +
                    "Other choices apply a preferred text size " +
                    "within WhereIsIt."
                )
            }

            Section("Accessibility") {
                Label(
                    "Spoken product locations enabled",
                    systemImage: "speaker.wave.2"
                )

                Label(
                    "Voice product search enabled",
                    systemImage: "mic"
                )
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

