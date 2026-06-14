//
//  BannerAdView.swift
//  English word app
//
//  Created by Codex on 2026/03/31.
//

import SwiftUI
import Combine

#if os(iOS)
import UIKit
#endif

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct NativeAdConfiguration {
    let nativeAdUnitID: String?
    let isSimulationEnabled: Bool

    private static let debugTestNativeAdUnitID = "ca-app-pub-3940256099942544/3986624511"

    var isConfigured: Bool {
        guard let nativeAdUnitID else { return false }
        return nativeAdUnitID.isEmpty == false
    }

    static func load(bundle: Bundle = .main) -> NativeAdConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let simulationEnabledFromEnv = ["1", "true", "yes", "on"].contains(
            (environment["ENABLE_AD_SIMULATION"] ?? "").lowercased()
        )
        #if targetEnvironment(simulator)
        let simulationEnabled = true
        #elseif canImport(GoogleMobileAds)
        let simulationEnabled = simulationEnabledFromEnv
        #else
        let simulationEnabled = true
        #endif
        let configuredNativeAdUnitID = environment["ADMOB_NATIVE_AD_UNIT_ID"]
            ?? bundle.object(forInfoDictionaryKey: "ADMOB_NATIVE_AD_UNIT_ID") as? String

        #if DEBUG
        let nativeAdUnitID = debugTestNativeAdUnitID
        #else
        let nativeAdUnitID = configuredNativeAdUnitID
        #endif

        return NativeAdConfiguration(
            nativeAdUnitID: nativeAdUnitID,
            isSimulationEnabled: simulationEnabled
        )
    }
}

struct NativeAdPlacement: View {
    private let outerHorizontalPadding: CGFloat
    private let topSpacing: CGFloat
    private let bottomSpacing: CGFloat
    private let configuration: NativeAdConfiguration

    @StateObject private var loader: NativeAdLoader

    init(
        outerHorizontalPadding: CGFloat = 16,
        topSpacing: CGFloat = 6,
        bottomSpacing: CGFloat = 6,
        configuration: NativeAdConfiguration = .load()
    ) {
        self.outerHorizontalPadding = outerHorizontalPadding
        self.topSpacing = topSpacing
        self.bottomSpacing = bottomSpacing
        self.configuration = configuration
        _loader = StateObject(wrappedValue: NativeAdLoader(configuration: configuration))
    }

    var body: some View {
        Group {
            if configuration.isSimulationEnabled {
                adCard {
                    simulatedNativeAd
                }
            } else if let nativeAd = loader.nativeAd {
#if os(iOS) && canImport(GoogleMobileAds)
                adCard {
                    NativeAdContainerView(nativeAd: nativeAd)
                        .frame(height: 250)
                }
#else
                EmptyView()
#endif
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            loader.loadIfNeeded()
        }
    }

    private func adCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
            )
            .padding(.horizontal, outerHorizontalPadding)
            .padding(.top, topSpacing)
            .padding(.bottom, bottomSpacing)
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.orange.opacity(0.18))
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))
                        .frame(width: 140, height: 12)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 90, height: 10)
                }

                Spacer()
            }

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
                .frame(height: 132)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 104, height: 34)
        }
        .padding(16)
        .redacted(reason: .placeholder)
    }

    private var simulatedNativeAd: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.95), Color.yellow.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("広告")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.orange.opacity(0.12))
                            )

                        Text("おすすめ学習")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text("英語学習アプリをもっと続けやすく")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("ネイティブ広告は、まわりのカードに合わせた見た目で自然に表示できます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.18), Color.yellow.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 132)
                .overlay(
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.orange.opacity(0.8))
                )

            HStack {
                Spacer()

                Text("詳しく見る")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.orange)
                    )
            }
        }
        .padding(16)
    }
}

#if os(iOS) && canImport(GoogleMobileAds)
@MainActor
final class NativeAdLoader: NSObject, ObservableObject {
    @Published private(set) var nativeAd: NativeAd?

    private let configuration: NativeAdConfiguration
    private var adLoader: AdLoader?
    private var hasLoaded = false

    init(configuration: NativeAdConfiguration) {
        self.configuration = configuration
    }

    func loadIfNeeded() {
        guard hasLoaded == false else { return }
        hasLoaded = true

        guard configuration.isSimulationEnabled == false else { return }
        guard let adUnitID = configuration.nativeAdUnitID, adUnitID.isEmpty == false else {
            return
        }

        let loader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: Self.rootViewController(),
            adTypes: [.native],
            options: nil
        )
        loader.delegate = self
        adLoader = loader
        loader.load(Request())
    }

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

extension NativeAdLoader: NativeAdLoaderDelegate, AdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        self.nativeAd = nativeAd
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: any Error) {
        nativeAd = nil
    }
}

private struct NativeAdContainerView: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> NativeAdCardView {
        NativeAdCardView()
    }

    func updateUIView(_ uiView: NativeAdCardView, context: Context) {
        uiView.apply(nativeAd: nativeAd)
    }
}

private final class NativeAdCardView: NativeAdView {
    private let adBadgeLabel = InsetLabel()
    private let iconImageView = UIImageView()
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()
    private let advertiserLabel = UILabel()
    private let mediaAssetView = MediaView()
    private let ctaLabel = InsetLabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    func apply(nativeAd: NativeAd) {
        headlineLabel.text = nativeAd.headline

        bodyLabel.text = nativeAd.body
        bodyLabel.isHidden = nativeAd.body == nil

        advertiserLabel.text = nativeAd.advertiser ?? "スポンサー"

        if let iconImage = nativeAd.icon?.image {
            iconImageView.image = iconImage
            iconImageView.isHidden = false
        } else {
            iconImageView.image = nil
            iconImageView.isHidden = true
        }

        mediaAssetView.mediaContent = nativeAd.mediaContent

        if let callToAction = nativeAd.callToAction, callToAction.isEmpty == false {
            ctaLabel.text = callToAction
            ctaLabel.isHidden = false
        } else {
            ctaLabel.text = nil
            ctaLabel.isHidden = true
        }

        nativeAd.delegate = self
        self.nativeAd = nativeAd
    }

    private func buildViewHierarchy() {
        backgroundColor = .clear

        adBadgeLabel.text = "広告"
        adBadgeLabel.font = .systemFont(ofSize: 11, weight: .bold)
        adBadgeLabel.textColor = .systemOrange
        adBadgeLabel.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        adBadgeLabel.layer.cornerRadius = 10
        adBadgeLabel.layer.masksToBounds = true
        adBadgeLabel.contentInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        iconImageView.contentMode = .scaleAspectFill
        iconImageView.clipsToBounds = true
        iconImageView.layer.cornerRadius = 12
        iconImageView.backgroundColor = UIColor.secondarySystemBackground
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 48),
            iconImageView.heightAnchor.constraint(equalToConstant: 48),
        ])

        headlineLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        headlineLabel.textColor = .label
        headlineLabel.numberOfLines = 2

        advertiserLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        advertiserLabel.textColor = .secondaryLabel

        bodyLabel.font = .systemFont(ofSize: 14)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 3

        mediaAssetView.translatesAutoresizingMaskIntoConstraints = false
        mediaAssetView.layer.cornerRadius = 18
        mediaAssetView.layer.masksToBounds = true
        mediaAssetView.backgroundColor = UIColor.secondarySystemBackground
        NSLayoutConstraint.activate([
            mediaAssetView.heightAnchor.constraint(equalToConstant: 132)
        ])

        ctaLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        ctaLabel.textColor = .white
        ctaLabel.backgroundColor = .systemBlue
        ctaLabel.layer.cornerRadius = 17
        ctaLabel.layer.masksToBounds = true
        ctaLabel.contentInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        ctaLabel.textAlignment = .center
        ctaLabel.isUserInteractionEnabled = false

        let titleStack = UIStackView(arrangedSubviews: [adBadgeLabel, advertiserLabel])
        titleStack.axis = .horizontal
        titleStack.spacing = 8
        titleStack.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [titleStack, headlineLabel, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 6

        let topRow = UIStackView(arrangedSubviews: [iconImageView, textStack])
        topRow.axis = .horizontal
        topRow.spacing = 12
        topRow.alignment = .top

        let ctaRow = UIStackView(arrangedSubviews: [UIView(), ctaLabel])
        ctaRow.axis = .horizontal
        ctaRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [topRow, mediaAssetView, ctaRow])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])

        headlineView = headlineLabel
        bodyView = bodyLabel
        iconView = iconImageView
        callToActionView = ctaLabel
        mediaView = mediaAssetView
        advertiserView = advertiserLabel
    }
}

extension NativeAdCardView: NativeAdDelegate {}

private final class InsetLabel: UILabel {
    var contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + contentInsets.left + contentInsets.right,
            height: size.height + contentInsets.top + contentInsets.bottom
        )
    }
}
#endif
