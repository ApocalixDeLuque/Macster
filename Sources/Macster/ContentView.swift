import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: PowerController

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.08),
                    Color(red: 0.10, green: 0.11, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                AppLogo()

                VStack(spacing: 10) {
                    Text("Macster")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(controller.status.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                StatusPill(status: controller.status)

                VStack(spacing: 10) {
                    Button {
                        controller.toggle()
                    } label: {
                        HStack(spacing: 9) {
                            if controller.isBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.black)
                            } else {
                                Image(systemName: controller.status.isEnabled ? "moon.zzz.fill" : "bolt.fill")
                                    .font(.system(size: 16, weight: .semibold))
                            }

                            Text(controller.primaryActionTitle)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: !controller.isBusy))
                    .disabled(controller.isBusy)

                    Button {
                        controller.refresh()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                        .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .disabled(controller.isBusy)
                }

                if let message = controller.message {
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(controller.messageIsError ? Color(red: 1.0, green: 0.45, blue: 0.42) : Color.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(minHeight: 44, alignment: .top)
                } else {
                    Color.clear
                        .frame(height: 24)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.top, 78)
            .padding(.bottom, 24)
        }
    }
}

private struct AppLogo: View {
    var body: some View {
        Group {
            if let image = Bundle.main.url(forResource: "macster", withExtension: "png").flatMap(NSImage.init(contentsOf:)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "macbook.and.iphone")
                    .resizable()
                    .scaledToFit()
                    .padding(22)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 96, height: 96)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.26), radius: 15, x: 0, y: 10)
    }
}

private struct StatusPill: View {
    let status: PowerStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.tint)
                .frame(width: 9, height: 9)

            Text(status.badge)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(status.tint.opacity(0.18), in: Capsule())
        .overlay(Capsule().stroke(status.tint.opacity(0.34), lineWidth: 1))
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(enabled ? Color.white.opacity(configuration.isPressed ? 0.82 : 0.96) : Color.white.opacity(0.45))
            )
    }
}
