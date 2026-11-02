import SwiftUI
#if canImport(CoreImage.CIFilterBuiltins) && canImport(UIKit)
import CoreImage.CIFilterBuiltins
import UIKit

private func generateQRCodeImage(for string: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: cg)
}
#endif

/// Add-ons installed on your account, read live from the engine. You can remove a non-default addon
/// here; install new ones manually, via QR phone companion, or from the Stremio web app.
struct AddonsView: View {
    @EnvironmentObject private var account: StremioAccount
    @EnvironmentObject private var core: CoreBridge
    @EnvironmentObject private var theme: ThemeManager

    @State private var showQRModal = false
    @State private var showManualAlert = false
    @State private var manualURL = ""
    @State private var isInstalling = false
    @State private var installError: String? = nil

    private var companionAddonsURL: String {
        #if os(tvOS)
        return IPTVWebServer.shared.serverURLString + "/addons"
        #else
        return "http://127.0.0.1:9898/addons"
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    #if os(tvOS)
                    NavigationPillButton(title: "Add-ons")
                    #endif
                    HStack(alignment: .firstTextBaseline) {
                        Text("Add-ons").screenTitleStyle()
                        Spacer()
                    }

                    HStack(spacing: Theme.Space.md) {
                        Button {
                            showQRModal = true
                        } label: {
                            Label("Manage on Phone (QR)", systemImage: "qrcode")
                        }
                        .buttonStyle(PrimaryActionStyle())

                        Button {
                            showManualAlert = true
                        } label: {
                            Label("Add Add-on (URL)", systemImage: "plus.circle")
                        }
                        .buttonStyle(ChipButtonStyle(selected: false))
                    }
                    .padding(.bottom, Theme.Space.xs)

                    if !account.isSignedIn {
                        hint("Sign in to sync your add-ons automatically, or manage them locally from your phone.")
                    } else if core.addons.isEmpty {
                        hint("No add-ons found on your account yet. Tap 'Manage on Phone (QR)' or 'Add Add-on' to get started.")
                    } else {
                        ForEach(core.addons) { addon in addonRow(addon) }
                    }
                }
                .padding(.horizontal, Theme.Space.screenInset)
                .padding(.vertical, Theme.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Palette.canvas.ignoresSafeArea())
        }
        .alert("Add Stremio Add-on", isPresented: $showManualAlert) {
            TextField("https://.../manifest.json", text: $manualURL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            Button("Install") {
                let toInstall = manualURL
                manualURL = ""
                Task {
                    do {
                        isInstalling = true
                        try await core.installAddon(manifestURL: toInstall)
                        isInstalling = false
                    } catch {
                        isInstalling = false
                        installError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                manualURL = ""
            }
        } message: {
            Text("Enter or paste the manifest URL of the add-on you want to install.")
        }
        .alert("Add-on Installation Failed", isPresented: Binding(
            get: { installError != nil },
            set: { if !$0 { installError = nil } }
        )) {
            Button("OK", role: .cancel) { installError = nil }
        } message: {
            Text(installError ?? "")
        }
        .sheet(isPresented: $showQRModal) {
            addonsQRSheet
        }
    }

    private var addonsQRSheet: some View {
        ZStack {
            Theme.Palette.canvas.ignoresSafeArea()
            VStack(spacing: Theme.Space.lg) {
                Text("Manage Add-ons on Phone")
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)

                #if canImport(CoreImage.CIFilterBuiltins) && canImport(UIKit)
                if let image = generateQRCodeImage(for: companionAddonsURL) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 360, height: 360)
                        .padding(Theme.Space.md)
                        .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                #endif

                VStack(spacing: 6) {
                    Text(companionAddonsURL)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.Palette.accent)

                    Text("Scan with your phone camera to install, uninstall add-ons, or configure integrations in your mobile browser.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 750)
                }

                Button("Done") {
                    showQRModal = false
                }
                .buttonStyle(ChipButtonStyle(selected: false))
            }
            .padding(Theme.Space.xl)
        }
    }

    private func addonRow(_ addon: CoreDescriptor) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: addon.providesStreams ? "play.rectangle.on.rectangle.fill" : "puzzlepiece.extension.fill")
                .font(.system(size: 36))
                .foregroundStyle(addon.providesStreams ? Theme.Palette.accent : Theme.Palette.textTertiary)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 8) {
                Text(addon.manifest.name).font(Theme.Typography.cardTitle).foregroundStyle(Theme.Palette.textPrimary)
                Text(addon.capabilities).font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
                Text(addon.host).font(.system(size: 16, design: .monospaced)).foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: Theme.Space.sm)
            if !addon.isProtected {
                Button { core.uninstallAddon(addon) } label: { Label("Remove", systemImage: "trash") }
                    .buttonStyle(ChipButtonStyle(selected: true, accent: Theme.Palette.danger, accentText: Theme.Palette.danger))
                    .fixedSize()   // keep the Remove chip at its intrinsic width so a narrow phone row can't squeeze the label to one glyph per line
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.textSecondary)
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.top, Theme.Space.sm)
    }
}
