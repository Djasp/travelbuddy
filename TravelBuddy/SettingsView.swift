import SwiftUI
import CoreLocation

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var monitor: TravelTimeMonitor

    @State private var addressInput = ""
    @State private var isGeocoding = false
    @State private var geocodeError: String?

    private let primaryText = Color(red: 0.10, green: 0.18, blue: 0.31)
    private let secondaryText = Color(red: 0.35, green: 0.43, blue: 0.55)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.98, blue: 1.0),
                    Color(red: 0.92, green: 0.95, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Instellingen", systemImage: "car.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(primaryText)

                    Text("Stel je bestemming, meetinterval en vertragingsdrempel in.")
                        .font(.subheadline)
                        .foregroundStyle(secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Bestemming", systemImage: "mappin.and.ellipse")
                            .font(.headline)
                            .foregroundStyle(primaryText)

                        HStack(spacing: 8) {
                            TextField("Adres of plaats, bijv. Stationsweg 1, Zwolle", text: $addressInput)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { lookupAddress() }

                            Button {
                                lookupAddress()
                            } label: {
                                if isGeocoding {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Instellen")
                                }
                            }
                            .disabled(isGeocoding || addressInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if let error = geocodeError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        if let name = preferences.destinationName {
                            Label(name, systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color(red: 0.12, green: 0.27, blue: 0.45))
                        } else {
                            Text("Nog geen bestemming ingesteld.")
                                .font(.caption)
                                .foregroundStyle(secondaryText)
                        }

                        Text("Bij een nieuwe bestemming wordt de opgebouwde referentie gereset.")
                            .font(.caption)
                            .foregroundStyle(secondaryText)
                    }
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Meting", systemImage: "timer")
                            .font(.headline)
                            .foregroundStyle(primaryText)

                        HStack {
                            Text("Controleer elke")
                                .foregroundStyle(primaryText)
                            Spacer()
                            Stepper("\(preferences.intervalMinutes) min", value: $preferences.intervalMinutes, in: 5...60, step: 5)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.blue)
                        }

                        Text("De reistijd wordt berekend met de actuele verkeerssituatie (Apple Kaarten).")
                            .font(.caption)
                            .foregroundStyle(secondaryText)
                    }
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Vertraging", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                            .foregroundStyle(primaryText)

                        HStack {
                            Text("Melding vanaf")
                                .foregroundStyle(primaryText)
                            Spacer()
                            Stepper("\(preferences.delayThresholdMinutes) min", value: $preferences.delayThresholdMinutes, in: 1...120, step: 1)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.blue)
                        }

                        Text("Je krijgt één melding zodra de vertraging deze drempel bereikt, en één zodra die weer voorbij is. De vertraging wordt bepaald t.o.v. de mediaan van je metingen (minimaal \(TravelStatistics.minimumSamplesForBaseline)).")
                            .font(.caption)
                            .foregroundStyle(secondaryText)

                        Text("Reistijden korter dan deze drempel tellen niet mee: dan ben je (bijna) op de bestemming, bijv. thuiswerken met bestemming thuis. Kies de drempel dus korter dan je normale reistijd.")
                            .font(.caption)
                            .foregroundStyle(secondaryText)

                        Divider()

                        HStack {
                            Text("Opgeslagen metingen: \(monitor.sampleCount)")
                                .font(.caption)
                                .foregroundStyle(secondaryText)
                            Spacer()
                            Button("Reset geschiedenis") {
                                monitor.resetHistory()
                            }
                            .disabled(monitor.sampleCount == 0)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .frame(minWidth: SettingsWindowMetrics.width, minHeight: SettingsWindowMetrics.height)
        .onAppear {
            addressInput = preferences.destinationName ?? ""
        }
    }

    private func lookupAddress() {
        let query = addressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isGeocoding else { return }

        isGeocoding = true
        geocodeError = nil

        CLGeocoder().geocodeAddressString(query) { placemarks, _ in
            DispatchQueue.main.async {
                isGeocoding = false
                guard let placemark = placemarks?.first, let location = placemark.location else {
                    geocodeError = "Adres niet gevonden. Probeer het specifieker, bijv. met straat en plaats."
                    return
                }

                let name = [placemark.name, placemark.locality]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                preferences.setDestination(
                    name: name.isEmpty ? query : name,
                    coordinate: location.coordinate
                )
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.95), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 3)
            )
    }
}
