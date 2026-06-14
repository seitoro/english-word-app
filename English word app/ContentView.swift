//
//  ContentView.swift
//  English word app
//
//  Created by 岡田瑠聖 on 2026/03/23.
//

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
import SafariServices
#endif

struct ContentView: View {
    private enum FocusedField: Hashable {
        case createInput
        case searchInput
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \WordEntry.createdAt, order: .forward) private var entries: [WordEntry]
    @StateObject private var subscriptionManager = SubscriptionManager()
    @StateObject private var usageQuotaManager = UsageQuotaManager()
    @StateObject private var aiTestQuotaManager = AITestQuotaManager()
    @StateObject private var rewardedAdManager = RewardedAdManager()

    @State private var inputWord = ""
    @State private var generatedDraft: WordEntryDraft?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var selectedTab: AppTab = .create
    @State private var searchText = ""
    @State private var isShowingPremiumDetails = false
    @State private var isShowingSettings = false
    @State private var selectedLegalPage: LegalPage?
    @State private var savedStatusMessage: String?
    @State private var hasSeededPreviewQuota = false
    @State private var selectedListCategory: EntryKind = .word
    @State private var selectedTestFilter: TestEntryFilter = .word
    @State private var testUsesPrimaryMeaningOnly = true
    @State private var testGeneratesExamplesOnTheFly = false
    @State private var testRangeStart = 1
    @State private var testRangeEnd = 1
    @State private var premiumTestQuestionCount = 10
    @State private var activeTestSession: AITestSession?
    @State private var testMessage: String?
    @State private var isPreparingTest = false
    @FocusState private var focusedField: FocusedField?
#if os(iOS)
    @State private var isKeyboardVisible = false
#endif

    private let generator: any WordEntryGenerating
    private let aiTestGenerator: any AITestGenerating
    private let isGeneratorAvailable = WordEntryGeneratorFactory.isAvailable
    private let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    init(
        generator: any WordEntryGenerating = WordEntryGeneratorFactory.makeGenerator(),
        aiTestGenerator: any AITestGenerating = BackendAITestGenerator()
    ) {
        self.generator = generator
        self.aiTestGenerator = aiTestGenerator
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                createTab
                    .tabItem {
                        Label("作成", systemImage: "sparkles")
                    }
                    .tag(AppTab.create)

                searchTab
                    .tabItem {
                        Label("検索", systemImage: "magnifyingglass")
                    }
                    .tag(AppTab.search)

                listTab
                    .tabItem {
                        Label("一覧", systemImage: "list.bullet")
                    }
                    .tag(AppTab.list)

                testTab
                    .tabItem {
                        Label("テスト", systemImage: "text.book.closed")
                    }
                    .tag(AppTab.test)
            }

        }
        .sheet(isPresented: $isShowingSettings) {
            settingsSheet
        }
        .sheet(item: $selectedLegalPage) { legalPage in
#if os(iOS)
            LegalPageSafariView(url: legalPage.url)
                .ignoresSafeArea()
#else
            EmptyView()
#endif
        }
        .fullScreenCover(isPresented: $rewardedAdManager.isShowingSimulationAd) {
            rewardedAdSimulationView
        }
#if os(iOS)
        .fullScreenCover(isPresented: $isShowingPremiumDetails) {
            premiumDetailsSheet
        }
#else
        .sheet(isPresented: $isShowingPremiumDetails) {
            premiumDetailsSheet
        }
#endif
        .task {
            guard isPreview == false else {
                seedPreviewQuotaIfNeeded()
                return
            }

            await subscriptionManager.prepare()
            usageQuotaManager.refresh()
            aiTestQuotaManager.refresh()
            await TrackingPermissionManager.requestIfNeeded()
            rewardedAdManager.prepare()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                usageQuotaManager.refresh()
                aiTestQuotaManager.refresh()
            }
        }
#if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
            focusedField = nil
        }
#endif
    }

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isShowingSettings = false
                        DispatchQueue.main.async {
                            isShowingPremiumDetails = true
                        }
                    } label: {
                        settingsActionRow(
                            title: "Premiumプラン",
                            systemImage: "sparkles"
                        )
                    }
                    .buttonStyle(.plain)

                    Button(subscriptionManager.isRestoring ? "復元中..." : "購入を復元") {
                        Task {
                            await subscriptionManager.restorePurchases()
                        }
                    }
                    .disabled(subscriptionManager.isRestoring || subscriptionManager.isLoading)
                }

                Section("ヘルプ") {
                    settingsLegalRow(title: "利用規約", path: "terms.html")
                    settingsLegalRow(title: "プライバシーポリシー", path: "privacy.html")
                    settingsLegalRow(title: "お問い合わせ", path: "contact.html")
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingSettings = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                    }
                }
            }
        }
    }

    private var testTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                testFilterTabs
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 0)

                if filteredTestEntries.isEmpty {
                    listEmptyStateCard(message: "保存した英単語や英熟語がまだありません。")
                        .padding(.horizontal, 16)

                    Spacer(minLength: 0)
                } else {
                    List {
                        if let activeTestSession {
                            testSessionSection(activeTestSession)
                        } else {
                            Section {
                                VStack(alignment: .leading, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(spacing: 8) {
                                            Text("左")
                                                .foregroundStyle(.secondary)
                                                .frame(width: 28, alignment: .leading)

                                            testRangeInlineSummary(
                                                number: testRangeStart,
                                                word: testRangeEntryTitle(for: testRangeStart)
                                            )

                                            Spacer(minLength: 0)
                                        }

                                        HStack(spacing: 10) {
                                            Spacer(minLength: 0)
                                            rangeAdjustButton(title: "-100", action: { adjustTestRangeStart(by: -100) })
                                            rangeAdjustButton(title: "-10", action: { adjustTestRangeStart(by: -10) })
                                            rangeAdjustButton(title: "-", action: { adjustTestRangeStart(by: -1) })
                                            rangeAdjustButton(title: "+", action: { adjustTestRangeStart(by: 1) })
                                            rangeAdjustButton(title: "+10", action: { adjustTestRangeStart(by: 10) })
                                            rangeAdjustButton(title: "+100", action: { adjustTestRangeStart(by: 100) })
                                            Spacer(minLength: 0)
                                        }
                                    }

                                    Divider()

                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(spacing: 8) {
                                            Text("右")
                                                .foregroundStyle(.secondary)
                                                .frame(width: 28, alignment: .leading)

                                            testRangeInlineSummary(
                                                number: testRangeEnd,
                                                word: testRangeEntryTitle(for: testRangeEnd)
                                            )

                                            Spacer(minLength: 0)
                                        }

                                        HStack(spacing: 10) {
                                            Spacer(minLength: 0)
                                            rangeAdjustButton(title: "-100", action: { adjustTestRangeEnd(by: -100) })
                                            rangeAdjustButton(title: "-10", action: { adjustTestRangeEnd(by: -10) })
                                            rangeAdjustButton(title: "-", action: { adjustTestRangeEnd(by: -1) })
                                            rangeAdjustButton(title: "+", action: { adjustTestRangeEnd(by: 1) })
                                            rangeAdjustButton(title: "+10", action: { adjustTestRangeEnd(by: 10) })
                                            rangeAdjustButton(title: "+100", action: { adjustTestRangeEnd(by: 100) })
                                            Spacer(minLength: 0)
                                        }
                                    }

                                    Divider()

                                    HStack {
                                        Text("出題範囲")
                                        Spacer()
                                        Text("\(testRangeStart) 〜 \(testRangeEnd)")
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.body.weight(.medium))

                                    Divider()

                                    Toggle(isOn: $testUsesPrimaryMeaningOnly) {
                                        Text("主な意味のみ")
                                    }

                                    Divider()

                                    Toggle(isOn: $testGeneratesExamplesOnTheFly) {
                                        Text("その場で作成")
                                    }
                                    .disabled(subscriptionManager.hasPremiumAccess == false)

                                    Divider()

                                    Group {
                                        if subscriptionManager.hasPremiumAccess {
                                            Stepper(
                                                value: premiumQuestionCountBinding,
                                                in: 1...max(availableQuestionSourceCount, 1)
                                            ) {
                                                HStack {
                                                    Text("問題数")
                                                    Spacer()
                                                    Text("\(effectiveQuestionCount)問")
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        } else {
                                            VStack(alignment: .leading, spacing: 8) {
                                                HStack {
                                                    Text("問題数")
                                                    Spacer()
                                                    Text("\(effectiveQuestionCount)問")
                                                        .foregroundStyle(.secondary)
                                                }

                                                if availableSelectedEntryCount < 10 {
                                                    Text(freeTestRangeRequirementMessage)
                                                        .font(.footnote)
                                                        .foregroundStyle(.red)
                                                }
                                            }
                                        }
                                    }

                                    if subscriptionManager.hasPremiumAccess == false {
                                        Divider()

                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("テスト回数: 残り\(aiTestQuotaManager.remainingTests)回")
                                                .font(.footnote.weight(.semibold))

                                            if aiTestQuotaManager.remainingTests == 0 {
                                                Text("無料テスト回数を使い切りました。広告を視聴するとテスト回数が2回追加されます。")
                                                    .font(.footnote)
                                                    .foregroundStyle(.secondary)

                                                Button("広告を見て2回追加") {
                                                    Task {
                                                        let isRewardEarned = await rewardedAdManager.showRewardedAd()
                                                        if isRewardEarned {
                                                            aiTestQuotaManager.addRewardedTest()
                                                            testMessage = nil
                                                        }
                                                    }
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .tint(.blue)
                                            }
                                        }
                                    }

                                    Divider()

                                    Button(isPreparingTest ? "テスト準備中..." : "テスト開始") {
                                        Task {
                                            await startAITest()
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(canStartAITest == false || isPreparingTest)
                                }
                            }

                            if let testMessage {
                                Section {
                                    Text(testMessage)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if shouldShowBannerAd, activeTestSession != nil {
                            Section {
                                NativeAdPlacement(
                                    outerHorizontalPadding: 20,
                                    topSpacing: 4,
                                    bottomSpacing: 4
                                )
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
#if os(iOS)
            .listSectionSpacing(0)
#endif
            .safeAreaInset(edge: .top, spacing: 0) {
                topBarHeader(title: "テスト")
                    .padding(.bottom, 8)
                    .background(Color(uiColor: .systemGroupedBackground))
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                syncTestRangeSelection(resetToFullRange: true)
            }
            .onChange(of: selectedTestFilter) { _, _ in
                syncTestRangeSelection(resetToFullRange: true)
            }
            .onChange(of: entries.count) { _, _ in
                syncTestRangeSelection(resetToFullRange: false)
            }
        }
    }

    private var testFilterTabs: some View {
        HStack(spacing: 0) {
            testFilterTabButton(title: TestEntryFilter.word.label, filter: .word)
            testFilterTabButton(title: TestEntryFilter.phrase.label, filter: .phrase)
        }
        .frame(maxWidth: .infinity)
        .padding(1)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func testFilterTabButton(title: String, filter: TestEntryFilter) -> some View {
        let isSelected = selectedTestFilter == filter

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTestFilter = filter
            }
        } label: {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    isSelected
                    ? (colorScheme == .dark ? Color.white.opacity(0.96) : Color.black)
                    : (colorScheme == .dark ? Color.white.opacity(0.82) : Color.secondary)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            isSelected
                            ? (colorScheme == .dark
                                ? Color.secondary.opacity(0.08)
                                : Color.white)
                            : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var createTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    inputSection

                    if shouldShowBannerAd {
                        Section {
                            NativeAdPlacement(
                                outerHorizontalPadding: 20,
                                topSpacing: 0,
                                bottomSpacing: 4
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .listSectionSeparator(.hidden, edges: .top)
                    }

                    if let generatedDraft {
                        generatedSection(
                            draft: generatedDraft,
                            visibleSenses: visibleSenses(for: generatedDraft)
                        )
                    }
                }
                .listSectionSpacing(4)
            }
#if os(iOS)
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .top, spacing: 0) {
                topBarHeader(title: "作成")
                    .padding(.bottom, 0)
                    .background(Color(uiColor: .systemGroupedBackground))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                keyboardDismissBar
            }
#endif
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if isPreview {
                    seedPreviewQuotaIfNeeded()
                } else {
                    usageQuotaManager.refresh()
                }

                restoreFocusIfNeeded(.createInput)
            }
        }
    }

    private var listTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                listCategoryTabs
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 18)

                if filteredListEntries.isEmpty {
                    listEmptyStateCard(
                        message: selectedListCategory == .word
                        ? "英単語はまだありません"
                        : "英熟語はまだありません"
                    )
                    .padding(.horizontal, 16)

                    Spacer(minLength: 0)
                } else {
                    List {
                        savedWordsSection
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
#if os(iOS)
            .listSectionSpacing(8)
            .safeAreaInset(edge: .top, spacing: 0) {
                topBarHeader(title: "一覧")
                    .padding(.bottom, 8)
                    .background(Color(uiColor: .systemGroupedBackground))
            }
#endif
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var listCategoryTabs: some View {
        HStack(spacing: 0) {
            listCategoryTabButton(title: "英単語", category: .word)
            listCategoryTabButton(title: "英熟語", category: .phrase)
        }
        .frame(maxWidth: .infinity)
        .padding(1)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func listCategoryTabButton(title: String, category: EntryKind) -> some View {
        let isSelected = selectedListCategory == category

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedListCategory = category
            }
        } label: {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    isSelected
                    ? (colorScheme == .dark ? Color.white.opacity(0.96) : Color.black)
                    : (colorScheme == .dark ? Color.white.opacity(0.82) : Color.secondary)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            isSelected
                            ? (colorScheme == .dark
                                ? Color.secondary.opacity(0.08)
                                : Color.white)
                            : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var searchTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        TextField("", text: searchBinding, prompt: Text("英単語または英熟語を検索").foregroundStyle(emptyStateTextColor))
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .searchInput)
#if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.asciiCapable)
#endif
                    }

                    if searchResults.isEmpty {
                        if searchText.isEmpty {
                            Text("保存した英単語や英熟語を検索できます。")
                                .font(.footnote)
                                .foregroundStyle(emptyStateTextColor)
                        } else {
                            Text("一致する英単語や英熟語はありません。")
                                .font(.footnote)
                                .foregroundStyle(emptyStateTextColor)
                        }
                    } else {
                        searchResultsSection
                    }

                    if shouldShowBannerAd {
                        Section {
                            NativeAdPlacement(
                                outerHorizontalPadding: 20,
                                topSpacing: 0,
                                bottomSpacing: 4
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                }

            }
#if os(iOS)
            .listSectionSpacing(8)
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .top, spacing: 0) {
                topBarHeader(title: "検索")
                    .padding(.bottom, 0)
                    .background(Color(uiColor: .systemGroupedBackground))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                keyboardDismissBar
            }
#endif
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                restoreFocusIfNeeded(.searchInput)
            }
        }
    }

    private func rangeAdjustButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(minWidth: 42, minHeight: 34)
                .background(
                    Capsule()
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .overlay(
                    Capsule()
                        .stroke(Color(uiColor: .separator).opacity(0.22), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: 6, y: 2)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func topBarHeader(title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button {
                    isShowingPremiumDetails = true
                } label: {
                    premiumSparklesIcon(size: 44, iconSize: 20, cornerRadius: 16)
                }
                .accessibilityLabel("Premiumプラン")

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .darkGray))
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("設定")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func testRangeInlineSummary(number: Int, word: String) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(colorScheme == .dark ? 0.18 : 0.12))
                )

            Text(word)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var topHeaderSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            subscriptionSection
        }
        .padding(.top, 8)
    }

    private var homeShortcutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("使いたい機能を選択")
                .font(.headline)

            Button {
                selectedTab = .create
            } label: {
                homeShortcutCard(
                    title: "作成",
                    description: "英単語や英熟語から意味と例文を作成します。",
                    systemImage: "sparkles"
                )
            }
            .buttonStyle(.plain)

            Button {
                selectedTab = .search
            } label: {
                homeShortcutCard(
                    title: "検索",
                    description: "保存済みの英単語や英熟語をすぐに探せます。",
                    systemImage: "magnifyingglass"
                )
            }
            .buttonStyle(.plain)

            Button {
                selectedTab = .list
            } label: {
                homeShortcutCard(
                    title: "一覧",
                    description: "英単語と英熟語を分けてまとめて見られます。",
                    systemImage: "list.bullet"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var inputSection: some View {
        Section {
            TextField("", text: $inputWord, prompt: Text("英単語または英熟語を入力").foregroundStyle(emptyStateTextColor))
                .autocorrectionDisabled()
                .focused($focusedField, equals: .createInput)
#if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
#endif

            Button {
                focusedField = nil
                Task {
                    await generateWordEntry()
                }
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text(isGenerating ? "作成中..." : "作成")
                }
            }
            .disabled(
                isGenerating ||
                inputWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                isGeneratorAvailable == false ||
                (subscriptionManager.hasPremiumAccess == false && usageQuotaManager.remainingCreations <= 0)
            )

            Text(availabilityMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if subscriptionManager.hasPremiumAccess == false {
                creationAllowanceSection
            }

            if let rewardedAdErrorMessage = rewardedAdManager.errorMessage,
               usageQuotaManager.remainingCreations == 0 {
                Text(rewardedAdErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let savedStatusMessage {
                Text(savedStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var creationAllowanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("作成回数: 残り\(usageQuotaManager.remainingCreations)回")
                .font(.footnote.weight(.semibold))

            if usageQuotaManager.remainingCreations == 0 {
                Text("無料作成回数を使い切りました。広告を視聴すると作成回数が3回追加されます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("広告を見て3回追加") {
                    Task {
                        let isRewardEarned = await rewardedAdManager.showRewardedAd()
                        if isRewardEarned {
                            usageQuotaManager.addRewardedCreations()
                            errorMessage = nil
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
    }

    private var rewardedAdSimulationView: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.08, blue: 0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button {
                        rewardedAdManager.dismissSimulationAd()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                VStack(spacing: 18) {
                    Text("テスト用リワード広告")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.95), Color.yellow.opacity(0.82)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 220)
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 54))
                                    .foregroundStyle(.white)
                                Text("広告動画")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        }

                    Text("シミュレータではこのテスト広告画面を表示しています。視聴完了で回数が追加されます。")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.84))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                Spacer()

                Button("視聴完了して回数追加") {
                    rewardedAdManager.completeSimulationAd()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if subscriptionManager.hasPremiumAccess {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("プレミアム利用中")
                            .font(.subheadline.weight(.semibold))
                        Text(subscriptionManager.upgradeMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button {
                    isShowingPremiumDetails = true
                } label: {
                    VStack(spacing: 8) {
                        Text(subscriptionManager.isPurchasing ? "購入中..." : "Premiumをはじめる")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: Color.black.opacity(0.22), radius: 0, x: 0, y: 2)
                            .shadow(color: Color.white.opacity(0.18), radius: 0, x: 0, y: -1)

                        HStack(spacing: 0) {
                            Text("広告なしやAI自動テストなど")
                                .foregroundStyle(Color.white.opacity(0.86))
                            Text("詳細はこちら")
                                .foregroundStyle(Color.white.opacity(0.92))
                                .underline()
                        }
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, minHeight: 118, alignment: .center)
                }
                .buttonStyle(.plain)
                .disabled(subscriptionManager.isPurchasing || subscriptionManager.isLoading)
            }

            if subscriptionManager.isSimulationEnabled {
                Button(subscriptionManager.hasPremiumAccess ? "シミュレーションを無料状態に戻す" : "シミュレーションを有効化する") {
                    if subscriptionManager.hasPremiumAccess {
                        subscriptionManager.disablePremiumSimulation()
                    } else {
                        Task {
                            await subscriptionManager.purchasePremium()
                        }
                    }
                }
                .buttonStyle(.bordered)
            }

            if let errorMessage = subscriptionManager.errorMessage,
               errorMessage.contains("サブスク商品が見つかりません") == false {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    subscriptionManager.hasPremiumAccess
                    ? AnyShapeStyle(Color.orange.opacity(0.10))
                    : AnyShapeStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 1.00, green: 0.78, blue: 0.18),
                                Color(red: 1.00, green: 0.42, blue: 0.02),
                                Color(red: 1.00, green: 0.18, blue: 0.06),
                                Color(red: 1.00, green: 0.62, blue: 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay {
                    if subscriptionManager.hasPremiumAccess == false {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.36),
                                        Color.yellow.opacity(0.16),
                                        Color.clear,
                                        Color.red.opacity(0.18)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .overlay {
                    if subscriptionManager.hasPremiumAccess == false {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.24), lineWidth: 10)
                                .blur(radius: 8)
                                .mask(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    .white,
                                                    .white.opacity(0.75),
                                                    .clear,
                                                    .white.opacity(0.55)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                )

                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.34),
                                            Color.yellow.opacity(0.14),
                                            Color.clear
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(height: 34)
                                .rotationEffect(.degrees(-14))
                                .offset(x: -120, y: -52)

                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.clear,
                                            Color.white.opacity(0.14),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 16, height: 150)
                                .rotationEffect(.degrees(18))
                                .offset(x: 132, y: -30)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
        )
    }

    private var premiumDetailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    premiumFeatureCard
                    premiumPurchaseCard
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingPremiumDetails = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                    }
                }
            }
        }
    }

    private var premiumFeatureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            premiumFeatureRow(
                iconName: "eye.slash.fill",
                title: "広告非表示",
                description: "作成・検索・一覧・テストを広告なしで使えます。"
            )
            premiumFeatureRow(
                iconName: "slider.horizontal.3",
                title: "問題数の調整",
                description: "テストで出したい問題数を自由に調整しながら、自分に合ったペースで学習できます。"
            )
            premiumFeatureRow(
                iconName: "sparkles.rectangle.stack.fill",
                title: "その場で作成の利用",
                description: "保存済みの意味をもとに、新しい例文と和訳をその場で作成するテストが使えます。"
            )
        }
    }

    private var premiumPurchaseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            premiumPlanButton(
                badge: "オススメ",
                title: "年プラン",
                trailingTop: "",
                trailingBottom: subscriptionManager.yearlyPriceDisplay,
                isPrimary: true
            ) {
                await subscriptionManager.purchasePremiumYearly()
            }

            premiumPlanButton(
                badge: nil,
                title: "月プラン",
                trailingTop: "",
                trailingBottom: subscriptionManager.monthlyPriceDisplay,
                isPrimary: false
            ) {
                await subscriptionManager.purchasePremiumMonthly()
            }

            Text("登録が確定した時点でApple IDに請求されます。購読は自動更新され、現在の購読期間が終了する24時間前以内にアカウントへ次の請求が行われます。購入後の変更またはキャンセルは、App Storeのアカウントで行えます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .padding(.top, 6)

            Button(subscriptionManager.isRestoring ? "復元中..." : "購入を復元") {
                Task {
                    await subscriptionManager.restorePurchases()
                }
            }
            .buttonStyle(.plain)
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .disabled(subscriptionManager.isRestoring || subscriptionManager.isLoading)

            VStack(spacing: 18) {
                premiumLegalLink(title: "利用規約", path: "terms.html")
                premiumLegalLink(title: "個人情報保護方針", path: "privacy.html")
                premiumLegalLink(title: "お問い合わせ", path: "contact.html")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            if let errorMessage = subscriptionManager.errorMessage,
               errorMessage.contains("サブスク商品が見つかりません") == false {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func premiumPlanButton(
        badge: String?,
        title: String,
        trailingTop: String,
        trailingBottom: String,
        isPrimary: Bool,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if let badge {
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.blue)
                    }

                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.blue)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 6) {
                    if trailingTop.isEmpty == false {
                        Text(trailingTop)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.blue.opacity(0.7))
                    }

                    Text(trailingBottom)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.blue)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.blue.opacity(isPrimary ? 0.95 : 0.7), lineWidth: 1.4)
            )
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing || subscriptionManager.isLoading || subscriptionManager.hasPremiumAccess)
    }

    @ViewBuilder
    private func premiumLegalLink(title: String, path: String) -> some View {
        let url = legalPageURL(path: path)

#if os(iOS)
        Button(title) {
            selectedLegalPage = LegalPage(title: title, url: url)
        }
        .buttonStyle(.plain)
        .font(.body.weight(.medium))
        .foregroundStyle(.primary)
#else
        Button(title) {
            openURL(url)
        }
        .buttonStyle(.plain)
        .font(.body.weight(.medium))
        .foregroundStyle(.primary)
#endif
    }

    private func premiumFeatureRow(iconName: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(Color.orange)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }


    private func generatedSection(draft: WordEntryDraft, visibleSenses: [WordSense]) -> some View {
        let isSaved = hasSavedEntry(for: draft.word)

        return Section("単語帳プレビュー") {
            compactHeaderRow(title: "番号", value: nextEntryNumberText)
            compactHeaderRow(title: termLabel(for: draft.word, senses: draft.senses), value: draft.word)

            ForEach(Array(visibleSenses.enumerated()), id: \.offset) { index, sense in
                compactSenseCard(
                    index: index + 1,
                    partOfSpeech: sense.partOfSpeech,
                    meaningJapanese: sense.meaningJapanese,
                    exampleSentence: sense.exampleSentence,
                    exampleTranslation: sense.exampleTranslation
                )
            }

            Button(saveButtonTitle(for: draft)) {
                saveDraft(draft, visibleSenses: visibleSenses)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaved)
        }
    }

    private var savedWordsSection: some View {
        Group {
            categorizedEntriesSection(
                kind: selectedListCategory
            )
        }
    }

    private var partitionedEntries: (words: [WordEntry], phrases: [WordEntry], normalizedWords: Set<String>) {
        entries.reduce(into: (words: [WordEntry](), phrases: [WordEntry](), normalizedWords: Set<String>())) { partialResult, entry in
            switch entryKind(for: entry.word, senses: entry.senses) {
            case .word:
                partialResult.words.append(entry)
            case .phrase:
                partialResult.phrases.append(entry)
            }

            let normalizedWord = normalizedEntryText(entry.word)
            if normalizedWord.isEmpty == false {
                partialResult.normalizedWords.insert(normalizedWord)
            }
        }
    }

    private var filteredListEntries: [WordEntry] {
        selectedListCategory == .word ? partitionedEntries.words : partitionedEntries.phrases
    }

    private var nextEntryNumberText: String {
        "\(entries.count + 1)"
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { searchText },
            set: { newValue in
                guard let firstCharacter = newValue.first else {
                    searchText = newValue
                    return
                }

                searchText = firstCharacter.lowercased() + newValue.dropFirst()
            }
        )
    }

    private var filteredTestEntries: [WordEntry] {
        selectedTestFilter == .word ? partitionedEntries.words : partitionedEntries.phrases
    }

    private var selectedTestEntries: [WordEntry] {
        guard filteredTestEntries.isEmpty == false else {
            return []
        }

        let lowerBound = min(max(testRangeStart, 1), filteredTestEntries.count) - 1
        let upperBound = min(max(testRangeEnd, testRangeStart), filteredTestEntries.count) - 1
        guard lowerBound <= upperBound else {
            return []
        }

        return Array(filteredTestEntries[lowerBound...upperBound])
    }

    private var effectiveQuestionCount: Int {
        let availableCount = availableQuestionSourceCount
        guard availableCount > 0 else {
            return 0
        }

        if subscriptionManager.hasPremiumAccess {
            return min(premiumTestQuestionCount, availableCount)
        }

        return min(10, availableCount)
    }

    private var canStartAITest: Bool {
        guard availableQuestionSourceCount > 0 else {
            return false
        }

        if subscriptionManager.hasPremiumAccess {
            return true
        }

        guard aiTestQuotaManager.remainingTests > 0 else {
            return false
        }

        return availableSelectedEntryCount >= 10
    }

    private var freeTestRangeRequirementMessage: String {
        switch selectedTestFilter {
        case .word:
            return "英単語を10個以上選んでください。"
        case .phrase:
            return "英熟語を10個以上選んでください。"
        }
    }

    private var premiumQuestionCountBinding: Binding<Int> {
        Binding(
            get: { premiumTestQuestionCount },
            set: { newValue in
                let upperBound = max(availableQuestionSourceCount, 1)
                premiumTestQuestionCount = min(max(newValue, 1), upperBound)
            }
        )
    }

    private var availabilityMessage: String {
        WordEntryGeneratorFactory.availabilityMessage
    }

    private var availableEntriesForCurrentTestSettings: [WordEntry] {
        selectedTestEntries
    }

    private var availableSelectedEntryCount: Int {
        availableEntriesForCurrentTestSettings.count
    }

    private var availableQuestionSourceCount: Int {
        selectionQuestionSources(
            from: availableEntriesForCurrentTestSettings,
            primaryOnly: testUsesPrimaryMeaningOnly
        ).count
    }

    private var shouldGenerateAITestExamplesOnTheFly: Bool {
        subscriptionManager.hasPremiumAccess && testGeneratesExamplesOnTheFly
    }

    private var shouldShowBannerAd: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        subscriptionManager.hasPremiumAccess == false
        #endif
    }

    private var wordEntryCount: Int {
        partitionedEntries.words.count
    }

    private var phraseEntryCount: Int {
        partitionedEntries.phrases.count
    }

    private var remainingCreationCountText: String {
        subscriptionManager.hasPremiumAccess ? "無制限" : "\(usageQuotaManager.remainingCreations)回"
    }

    private func legalPageURL(path: String) -> URL {
        appLegalBaseURL.appending(path: path)
    }

    @ViewBuilder
    private func settingsLegalRow(title: String, path: String) -> some View {
        let url = legalPageURL(path: path)

#if os(iOS)
        Button {
            selectedLegalPage = LegalPage(title: title, url: url)
        } label: {
            settingsRowLabel(title: title)
        }
        .buttonStyle(.plain)
#else
        Button {
            openURL(url)
        } label: {
            settingsRowLabel(title: title)
        }
        .buttonStyle(.plain)
#endif
    }

    @MainActor
    private func generateWordEntry() async {
        guard inputWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            errorMessage = nil
            return
        }

        let canGenerate = subscriptionManager.hasPremiumAccess || usageQuotaManager.remainingCreations > 0
        guard canGenerate else {
            errorMessage = "無料作成回数を使い切りました。広告を視聴すると作成回数が3回追加されます。"
            return
        }

        isGenerating = true
        errorMessage = nil
        savedStatusMessage = nil

        do {
            let draft = try await generator.generateDraft(from: inputWord)

            if hasSavedEntry(for: draft.word) {
                generatedDraft = nil
                savedStatusMessage = "もうすでに保存済みです。"
            } else {
                generatedDraft = draft
                if subscriptionManager.hasPremiumAccess == false {
                    usageQuotaManager.consumeCreation()
                }
            }
        } catch {
            generatedDraft = nil
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }

    private func saveDraft(_ draft: WordEntryDraft, visibleSenses: [WordSense]) {
        withAnimation {
            let normalizedSenses = normalizeSensesForStorage(visibleSenses)
            let primarySense = normalizedSenses.first ?? draft.primarySense
            let entry = WordEntry(
                word: draft.word,
                meaningJapanese: primarySense.meaningJapanese,
                exampleSentence: primarySense.exampleSentence,
                exampleTranslation: primarySense.exampleTranslation,
                senses: normalizedSenses,
                contextualMeanings: visibleContextualMeanings(for: draft),
                generatedBy: draft.generatedBy
            )
            modelContext.insert(entry)
            generatedDraft = nil
            inputWord = ""
            errorMessage = nil
            savedStatusMessage = nil
        }
    }

    @MainActor
    private func startAITest() async {
        syncTestRangeSelection(resetToFullRange: false)

        let availableEntries = availableEntriesForCurrentTestSettings

        guard availableEntries.isEmpty == false else {
            testMessage = "出題できる保存データがありません。"
            activeTestSession = nil
            return
        }

        guard subscriptionManager.hasPremiumAccess || availableSelectedEntryCount >= 10 else {
            testMessage = freeTestRangeRequirementMessage
            activeTestSession = nil
            return
        }

        if subscriptionManager.hasPremiumAccess == false, aiTestQuotaManager.remainingTests <= 0 {
            testMessage = "無料テスト回数を使い切りました。広告を視聴するとテスト回数が2回追加されます。"
            activeTestSession = nil
            return
        }

        isPreparingTest = true
        defer { isPreparingTest = false }

        do {
            let questions = try await buildAITestQuestions(
                from: availableEntries,
                questionCount: effectiveQuestionCount
            )

            guard questions.isEmpty == false else {
                testMessage = "問題を作るための候補が足りません。出題範囲を広げてください。"
                activeTestSession = nil
                return
            }

            activeTestSession = AITestSession(
                questions: questions,
                usesPrimaryMeaningOnly: testUsesPrimaryMeaningOnly
            )
            testMessage = nil
            if subscriptionManager.hasPremiumAccess == false {
                aiTestQuotaManager.consumeTest()
            }
        } catch {
            activeTestSession = nil
            testMessage = error.localizedDescription
        }
    }

    private func buildAITestQuestions(from sourceEntries: [WordEntry], questionCount: Int) async throws -> [AITestQuestion] {
        if shouldGenerateAITestExamplesOnTheFly {
            return try await buildGeneratedAITestQuestions(from: sourceEntries, questionCount: questionCount)
        }

        return buildSelectionQuestions(from: sourceEntries, questionCount: questionCount)
    }

    private func buildSelectionQuestions(from sourceEntries: [WordEntry], questionCount: Int) -> [AITestQuestion] {
        let questionSources = selectionQuestionSources(
            from: sourceEntries,
            primaryOnly: testUsesPrimaryMeaningOnly
        )
        let desiredCount = min(questionCount, questionSources.count)
        guard desiredCount > 0 else {
            return []
        }

        let selectedSources = Array(questionSources.shuffled().prefix(desiredCount))

        return selectedSources.compactMap { source in
            let meaningJapanese = source.sense.meaningJapanese.trimmingCharacters(in: .whitespacesAndNewlines)
            let exampleSentence = source.sense.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)
            let exampleTranslation = source.sense.exampleTranslation.trimmingCharacters(in: .whitespacesAndNewlines)

            guard meaningJapanese.isEmpty == false, exampleSentence.isEmpty == false else {
                return nil
            }

            return AITestQuestion(
                term: source.entry.word,
                termLabel: source.promptSubtitle,
                meaningJapanese: meaningJapanese,
                exampleSentence: exampleSentence,
                exampleTranslation: exampleTranslation
            )
        }
    }

    private func buildGeneratedAITestQuestions(from sourceEntries: [WordEntry], questionCount: Int) async throws -> [AITestQuestion] {
        let questionSources = selectionQuestionSources(
            from: sourceEntries,
            primaryOnly: testUsesPrimaryMeaningOnly
        )
        let desiredCount = min(questionCount, questionSources.count)
        guard desiredCount > 0 else {
            return []
        }

        let selectedSources = Array(questionSources.shuffled().prefix(desiredCount))
        let promptInputs = selectedSources.map { source in
            AITestPromptInput(
                word: source.entry.word,
                meaningJapanese: source.sense.meaningJapanese.trimmingCharacters(in: .whitespacesAndNewlines),
                partOfSpeech: source.sense.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let generatedPrompts = try await aiTestGenerator.generateOriginalInputQuestions(from: promptInputs)

        return zip(selectedSources, generatedPrompts).compactMap { source, generatedPrompt in
            let meaningJapanese = generatedPrompt.meaningJapanese.trimmingCharacters(in: .whitespacesAndNewlines)
            let exampleSentence = generatedPrompt.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)
            let exampleTranslation = generatedPrompt.exampleTranslation.trimmingCharacters(in: .whitespacesAndNewlines)

            guard meaningJapanese.isEmpty == false, exampleSentence.isEmpty == false else {
                return nil
            }

            return AITestQuestion(
                term: source.entry.word,
                termLabel: source.promptSubtitle,
                meaningJapanese: meaningJapanese,
                exampleSentence: exampleSentence,
                exampleTranslation: exampleTranslation
            )
        }
    }

    private func selectionQuestionSources(from sourceEntries: [WordEntry], primaryOnly: Bool) -> [AITestQuestionSource] {
        sourceEntries.reduce(into: [AITestQuestionSource]()) { result, entry in
            let senses: [WordSense] = primaryOnly ? Array(entry.senses.prefix(1)) : entry.senses

            for sense in senses {
                let meaning = sense.meaningJapanese.trimmingCharacters(in: .whitespacesAndNewlines)
                let exampleSentence = sense.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)

                guard meaning.isEmpty == false, exampleSentence.isEmpty == false else {
                    continue
                }

                result.append(
                    AITestQuestionSource(
                        entry: entry,
                        sense: sense,
                        promptSubtitle: termLabel(for: entry.word, senses: entry.senses)
                    )
                )
            }
        }
    }

    private func revealTestCard() {
        guard var session = activeTestSession else {
            return
        }

        session.revealCurrentCard()
        activeTestSession = session
    }

    private func moveToNextTestQuestion() {
        guard var session = activeTestSession else {
            return
        }

        session.advance()
        activeTestSession = session
    }

    private func syncTestRangeSelection(resetToFullRange: Bool) {
        let entryCount = filteredTestEntries.count

        guard entryCount > 0 else {
            testRangeStart = 1
            testRangeEnd = 1
            premiumTestQuestionCount = 10
            return
        }

        if resetToFullRange {
            testRangeStart = 1
            testRangeEnd = entryCount
        } else {
            testRangeStart = min(max(testRangeStart, 1), entryCount)
            testRangeEnd = min(max(testRangeEnd, testRangeStart), entryCount)
        }

        clampPremiumQuestionCount()
    }

    private func clampPremiumQuestionCount() {
        let maxQuestionCount = max(availableQuestionSourceCount, 1)
        premiumTestQuestionCount = min(max(premiumTestQuestionCount, 1), maxQuestionCount)
    }

    private func adjustTestRangeStart(by delta: Int) {
        let maxStart = max(testRangeEnd - 1, 1)
        testRangeStart = min(max(testRangeStart + delta, 1), maxStart)
        clampPremiumQuestionCount()
    }

    private func adjustTestRangeEnd(by delta: Int) {
        let maxEnd = max(filteredTestEntries.count, 1)
        let minEnd = min(testRangeStart + 1, maxEnd)
        testRangeEnd = min(max(testRangeEnd + delta, minEnd), maxEnd)
        clampPremiumQuestionCount()
    }

    private func testRangeEntryTitle(for index: Int) -> String {
        guard filteredTestEntries.indices.contains(max(index - 1, 0)) else {
            return ""
        }

        return filteredTestEntries[index - 1].word
    }

    @ViewBuilder
    private func testSessionSection(_ session: AITestSession) -> some View {
        Section(session.isCompleted ? "完了" : "テスト") {
            if session.isCompleted {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(session.questions.count)枚のカードを確認しました。")
                        .font(.headline)
                    Text(session.resultMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("もう一度同じ条件で出題") {
                    Task {
                        await startAITest()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else if let currentQuestion = session.currentQuestion {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(session.usesPrimaryMeaningOnly ? "主な意味のみ" : "複数の意味を含む")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemBackground))
                            )

                        Spacer(minLength: 0)
                    }

                    Text("\(session.currentQuestionNumber) / \(session.questions.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Button {
                        revealTestCard()
                    } label: {
                        flashCardView(
                            question: currentQuestion,
                            isRevealed: session.isAnswerRevealed
                        )
                    }
                    .buttonStyle(.plain)

                    Text(session.isAnswerRevealed ? "カードをタップすると表面に戻れます。" : "カードをタップして裏面を見ます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Button(session.isLastQuestion ? "終了" : "次へ") {
                    if session.isLastQuestion {
                        activeTestSession = nil
                    } else {
                        moveToNextTestQuestion()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func flashCardView(question: AITestQuestion, isRevealed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isRevealed ? "裏面" : "表面")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(question.termLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if isRevealed {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("意味")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(question.meaningJapanese)
                            .font(.body.weight(.semibold))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("日本語訳")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(question.exampleTranslation)
                            .font(.body)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("例文")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    highlightedTermText(
                        sentence: question.exampleSentence,
                        term: question.term
                    )
                        .font(.title3.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
        }
    }

    private func highlightedTermText(sentence: String, term: String) -> Text {
        let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedSentence.isEmpty == false else {
            return Text("")
        }

        guard trimmedTerm.isEmpty == false else {
            return Text(trimmedSentence)
        }

        let loweredSentence = trimmedSentence.lowercased()
        let loweredTerm = trimmedTerm.lowercased()

        guard
            let loweredRange = loweredSentence.range(of: loweredTerm),
            let start = String.Index(loweredRange.lowerBound, within: trimmedSentence),
            let end = String.Index(loweredRange.upperBound, within: trimmedSentence)
        else {
            return Text(trimmedSentence)
        }

        let prefix = String(trimmedSentence[..<start])
        let match = String(trimmedSentence[start..<end])
        let suffix = String(trimmedSentence[end...])

        return Text(prefix) + Text(match).foregroundStyle(.red) + Text(suffix)
    }

    private func hasSavedEntry(for word: String) -> Bool {
        let normalizedWord = normalizedEntryText(word)
        guard normalizedWord.isEmpty == false else {
            return false
        }

        return partitionedEntries.normalizedWords.contains(normalizedWord)
    }

    private func normalizedEntryText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func visibleSenses(for draft: WordEntryDraft) -> [WordSense] {
        draft.senses
    }

    private func visibleContextualMeanings(for draft: WordEntryDraft) -> [ContextualMeaning] {
        draft.contextualMeanings
    }

    private func deleteEntries(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(entries[index])
            }
        }
    }

    private var emptyStateTextColor: Color {
        Color(red: 0.50, green: 0.50, blue: 0.54)
    }

    private func categorizedEntriesSection(kind: EntryKind) -> some View {
        let filteredEntries = kind == .word ? partitionedEntries.words : partitionedEntries.phrases

        return Group {
            if filteredEntries.isEmpty {
                Text(kind == .word ? "英単語はまだありません" : "英熟語はまだありません")
                    .font(.footnote)
                    .foregroundStyle(emptyStateTextColor)
            } else {
                ForEach(Array(filteredEntries.enumerated()), id: \.element.persistentModelID) { visibleIndex, entry in

                    NavigationLink {
                        WordEntryDetailView(entry: entry)
                    } label: {
                        entryRow(index: visibleIndex, entry: entry)
                    }

                    if shouldShowBannerAd && shouldInsertBanner(afterVisibleIndex: visibleIndex, totalCount: filteredEntries.count) {
                        NativeAdPlacement(topSpacing: 4, bottomSpacing: 4)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .onDelete { offsets in
                    let indexesToDelete = IndexSet(
                        offsets.compactMap { filteredIndex in
                            let entryID = filteredEntries[filteredIndex].persistentModelID
                            return entries.firstIndex { $0.persistentModelID == entryID }
                        }
                    )
                    deleteEntries(offsets: indexesToDelete)
                }
            }
        }
    }

    private func entryRow(index: Int, entry: WordEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(index + 1). \(entry.word)")
                .font(.headline)
            Text(entry.senses.first?.meaningJapanese ?? entry.meaningJapanese)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(entry.senses.first?.exampleSentence ?? entry.exampleSentence)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private func listEmptyStateCard(message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(emptyStateTextColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func shouldInsertBanner(afterVisibleIndex visibleIndex: Int, totalCount: Int) -> Bool {
        guard totalCount > 1 else {
            return false
        }

        if totalCount <= 4 {
            return visibleIndex == 0
        }

        return visibleIndex > 0 && (visibleIndex + 1).isMultiple(of: 4)
    }

    private var searchResults: [(offset: Int, entry: WordEntry)] {
        let normalizedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedQuery.isEmpty == false else {
            return []
        }

        return entries.enumerated().compactMap { index, entry in
            guard entryMatchesSearchQuery(entry, query: normalizedQuery) else {
                return nil
            }
            return (offset: index, entry: entry)
        }
    }

    private func entryMatchesSearchQuery(_ entry: WordEntry, query: String) -> Bool {
        let normalizedWord = entry.word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if queryUsesLatinPrefixMatching(query) {
            return normalizedWord.hasPrefix(query)
        }

        return entrySearchText(for: entry).contains(query)
    }

    private func queryUsesLatinPrefixMatching(_ query: String) -> Bool {
        query.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == " " || scalar == "-" || scalar == "'"
        }
    }

    private var searchResultsSection: some View {
        ForEach(searchResults, id: \.entry.persistentModelID) { index, entry in
            NavigationLink {
                WordEntryDetailView(entry: entry)
                    .onAppear {
                        dismissKeyboard()
                    }
            } label: {
                entryRow(index: index, entry: entry)
            }
        }
    }

    private func entrySearchText(for entry: WordEntry) -> String {
        let sensesText = entry.senses.map {
            [$0.meaningJapanese, $0.exampleSentence, $0.exampleTranslation, $0.partOfSpeech]
                .joined(separator: " ")
        }
        .joined(separator: " ")

        let contextText = entry.contextualMeanings.map {
            [$0.sentence, $0.meaningJapanese, $0.explanationJapanese]
                .joined(separator: " ")
        }
        .joined(separator: " ")

        return [
            entry.word,
            entry.meaningJapanese,
            entry.exampleSentence,
            entry.exampleTranslation,
            sensesText,
            contextText
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func homeShortcutCard(title: String, description: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func compactHeaderRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private func infoRow(number: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(number)
                .font(.body)
        }
        .padding(.vertical, 2)
    }

    private func compactSenseCard(
        index: Int,
        partOfSpeech: String,
        meaningJapanese: String,
        exampleSentence: String,
        exampleTranslation: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("意味\(index)")
                    .font(.subheadline.weight(.semibold))
                if partOfSpeech.isEmpty == false {
                    Text(localizedPartOfSpeech(partOfSpeech))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.7), in: Capsule())
                }
            }

            compactValueBlock(title: "日本語訳", text: meaningJapanese)
            compactValueBlock(title: "例文", text: exampleSentence)
            compactValueBlock(title: "和訳", text: exampleTranslation)
        }
        .padding(.vertical, 6)
    }

    private func compactValueBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
        }
    }

    private func localizedPartOfSpeech(_ partOfSpeech: String) -> String {
        switch partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "noun":
            return "名詞"
        case "verb":
            return "動詞"
        case "adjective":
            return "形容詞"
        case "adverb":
            return "副詞"
        case "preposition":
            return "前置詞"
        case "pronoun":
            return "代名詞"
        case "conjunction":
            return "接続詞"
        case "interjection":
            return "間投詞"
        case "auxiliary verb":
            return "助動詞"
        case "phrase":
            return "英熟語"
        case "idiom":
            return "慣用句"
        case "phrasal verb":
            return "句動詞"
        case "expression":
            return "表現"
        default:
            return partOfSpeech
        }
    }

    private func termLabel(for word: String, senses: [WordSense]) -> String {
        entryKind(for: word, senses: senses).label
    }

    private func saveButtonTitle(for draft: WordEntryDraft) -> String {
        switch entryKind(for: draft.word, senses: draft.senses) {
        case .word:
            return "英単語を保存"
        case .phrase:
            return "英熟語を保存"
        }
    }

    private func restoreFocusIfNeeded(_ field: FocusedField) {
#if os(iOS)
        guard field == .createInput else {
            return
        }

        guard isKeyboardVisible, focusedField == nil else {
            return
        }

        DispatchQueue.main.async {
            focusedField = field
        }
#endif
    }

    private func seedPreviewQuotaIfNeeded() {
        guard hasSeededPreviewQuota == false else {
            return
        }

        usageQuotaManager.setPreviewRemainingCreations(5)
        aiTestQuotaManager.setPreviewRemainingTests(3)
        hasSeededPreviewQuota = true
    }

    private func dismissKeyboard() {
#if os(iOS)
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
#endif
    }

}

#if os(iOS)
extension ContentView {
    @ViewBuilder
    private var keyboardDismissBar: some View {
        if isKeyboardVisible || focusedField != nil {
            HStack {
                Spacer()
                Button {
                    dismissKeyboard()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("キーボードを閉じる")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color(uiColor: .systemGray6))
            .overlay(alignment: .top) {
                Divider()
            }
        }
    }
}
#endif

#if os(iOS)
private struct KeyboardDismissOnTapView: UIViewRepresentable {
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear

        let recognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap() {
            onTap()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            touch.view === gestureRecognizer.view
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
#endif

private enum AppTab {
    case create
    case search
    case list
    case test
}

private enum TestEntryFilter: String, CaseIterable, Identifiable {
    case word
    case phrase

    var id: String { rawValue }

    var label: String {
        switch self {
        case .word:
            return "英単語"
        case .phrase:
            return "英熟語"
        }
    }
}

private struct AITestQuestionSource: Identifiable {
    let entry: WordEntry
    let sense: WordSense
    let promptSubtitle: String

    var id: String {
        "\(entry.persistentModelID)-\(sense.id)"
    }
}

private struct AITestQuestion: Identifiable {
    let id = UUID()
    let term: String
    let termLabel: String
    let meaningJapanese: String
    let exampleSentence: String
    let exampleTranslation: String
}

private struct AITestSession {
    let questions: [AITestQuestion]
    let usesPrimaryMeaningOnly: Bool
    var currentIndex = 0
    var isAnswerRevealed = false

    var currentQuestion: AITestQuestion? {
        guard isCompleted == false, questions.indices.contains(currentIndex) else {
            return nil
        }

        return questions[currentIndex]
    }

    var currentQuestionNumber: Int {
        min(currentIndex + 1, questions.count)
    }

    var isLastQuestion: Bool {
        currentIndex == questions.count - 1
    }

    var isCompleted: Bool {
        currentIndex >= questions.count
    }

    var resultMessage: String {
        "例文と意味をセットで見直せたので、そのままもう一度流すと覚えやすいです。"
    }

    mutating func revealCurrentCard() {
        guard isCompleted == false else {
            return
        }

        isAnswerRevealed.toggle()
    }

    mutating func advance() {
        currentIndex += 1
        isAnswerRevealed = false
    }
}

private let appVersionText: String = {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
}()

private let appBuildText: String = {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
}()

private let appLegalBaseURL: URL = {
    if let configuredURLString = ProcessInfo.processInfo.environment["LEGAL_PAGES_BASE_URL"],
       let configuredURL = URL(string: configuredURLString) {
        return configuredURL
    }

    if let configuredURLString = Bundle.main.object(forInfoDictionaryKey: "LEGAL_PAGES_BASE_URL") as? String,
       let configuredURL = URL(string: configuredURLString) {
        return configuredURL
    }

    return URL(string: "https://seitoro.github.io/english-word-app/")!
}()

private func settingsRowLabel(title: String) -> some View {
    HStack {
        Text(title)
            .foregroundStyle(.primary)
        Spacer()
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
    }
    .contentShape(Rectangle())
}

private func settingsActionRow(title: String, systemImage: String) -> some View {
    HStack(spacing: 12) {
        premiumSparklesIcon(size: 28, iconSize: 14, cornerRadius: 10)

        Text(title)
            .foregroundStyle(.primary)

        Spacer()

        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
    }
    .contentShape(Rectangle())
}

private func premiumSparklesIcon(size: CGFloat, iconSize: CGFloat, cornerRadius: CGFloat) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.84, blue: 0.35),
                        Color(red: 0.98, green: 0.70, blue: 0.18),
                        Color(red: 0.94, green: 0.54, blue: 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.38),
                                Color.white.opacity(0.10),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: cornerRadius,
                            bottomLeadingRadius: 6,
                            bottomTrailingRadius: 6,
                            topTrailingRadius: cornerRadius
                        )
                    )
                    .scaleEffect(x: 0.92, y: 0.52, anchor: .top)
                    .offset(y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
            }
            .shadow(color: Color(red: 0.95, green: 0.62, blue: 0.10).opacity(0.22), radius: 6, y: 2)

        Image(systemName: "gift.fill")
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .white.opacity(0.55), radius: 3)
            .shadow(color: Color(red: 1.00, green: 0.97, blue: 0.78).opacity(0.45), radius: 8)
    }
    .frame(width: size, height: size)
}

private func settingsSelectionRow(title: String, isSelected: Bool) -> some View {
    HStack {
        Text(title)
            .foregroundStyle(.primary)

        Spacer()

        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(
                isSelected
                ? Color(red: 0.95, green: 0.58, blue: 0.08)
                : Color.secondary.opacity(0.7)
            )
    }
    .contentShape(Rectangle())
}

private struct LegalPage: Identifiable {
    let title: String
    let url: URL

    var id: URL { url }
}

#if os(iOS)
private struct LegalPageSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif

private struct WordEntryDetailView: View {
    let entry: WordEntry

    var body: some View {
        List {
            Section("英単語情報") {
                detailRow(title: termLabel(for: entry.word, senses: entry.senses), text: entry.word)
            }

            ForEach(Array(entry.senses.enumerated()), id: \.offset) { index, sense in
                Section("意味 \(index + 1)") {
                    if sense.partOfSpeech.isEmpty == false {
                        detailRow(title: "品詞", text: localizedPartOfSpeech(sense.partOfSpeech))
                    }
                    detailRow(title: "日本語訳", text: sense.meaningJapanese)
                    detailRow(title: "例文", text: sense.exampleSentence)
                    detailRow(title: "和訳", text: sense.exampleTranslation)
                }
            }
        }
        .navigationTitle(entry.word)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private func detailRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
        }
        .padding(.vertical, 2)
    }

    private func localizedPartOfSpeech(_ partOfSpeech: String) -> String {
        switch partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "noun":
            return "名詞"
        case "verb":
            return "動詞"
        case "adjective":
            return "形容詞"
        case "adverb":
            return "副詞"
        case "preposition":
            return "前置詞"
        case "pronoun":
            return "代名詞"
        case "conjunction":
            return "接続詞"
        case "interjection":
            return "間投詞"
        case "auxiliary verb":
            return "助動詞"
        case "phrase":
            return "英熟語"
        case "idiom":
            return "慣用句"
        case "phrasal verb":
            return "句動詞"
        case "expression":
            return "表現"
        default:
            return partOfSpeech
        }
    }

    private func termLabel(for word: String, senses: [WordSense]) -> String {
        entryKind(for: word, senses: senses).label
    }

}

enum EntryKind: Hashable {
    case word
    case phrase

    var label: String {
        switch self {
        case .word:
            return "英単語"
        case .phrase:
            return "英熟語"
        }
    }
}

func entryKind(for word: String, senses: [WordSense]) -> EntryKind {
    let normalizedWord = word
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

    if normalizedWord.split(whereSeparator: \.isWhitespace).count > 1 {
        return .phrase
    }

    let phrasePartOfSpeechKeywords = ["phrase", "idiom", "phrasal verb", "expression"]
    if senses.contains(where: { sense in
        let normalizedPartOfSpeech = sense.partOfSpeech
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return phrasePartOfSpeechKeywords.contains(where: { normalizedPartOfSpeech.contains($0) })
    }) {
        return .phrase
    }

    return .word
}

#Preview {
    ContentView(generator: PreviewWordEntryGenerator())
        .modelContainer(previewContainer)
        .frame(width: 393, height: 852)
        .background(Color.white)
}

private let previewContainer: ModelContainer = {
    let schema = Schema([WordEntry.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [configuration])

    let sampleWordEntry = WordEntry(
        word: "run",
        meaningJapanese: "走る",
        exampleSentence: "She runs every morning.",
        exampleTranslation: "彼女は毎朝走ります。",
        senses: [
            WordSense(
                partOfSpeech: "verb",
                meaningJapanese: "走る",
                exampleSentence: "She runs every morning.",
                exampleTranslation: "彼女は毎朝走ります。"
            )
        ],
        contextualMeanings: [],
        generatedBy: "Preview"
    )

    let sampleEntry = WordEntry(
        word: "take off",
        meaningJapanese: "離陸する、脱ぐ",
        exampleSentence: "The plane will take off in ten minutes.",
        exampleTranslation: "飛行機は10分後に離陸します。",
        senses: [
            WordSense(
                partOfSpeech: "phrasal verb",
                meaningJapanese: "離陸する",
                exampleSentence: "The plane will take off in ten minutes.",
                exampleTranslation: "飛行機は10分後に離陸します。"
            )
        ],
        contextualMeanings: [],
        generatedBy: "Preview"
    )

    container.mainContext.insert(sampleWordEntry)
    container.mainContext.insert(sampleEntry)
    return container
}()

private struct PreviewWordEntryGenerator: WordEntryGenerating {
    func generateDraft(from input: String) async throws -> WordEntryDraft {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw WordGeneratorError.emptyInput
        }

        return WordEntryDraft(
            word: normalized,
            senses: [
                WordSense(
                    partOfSpeech: "noun",
                    meaningJapanese: "プレビュー用の日本語訳 1",
                    exampleSentence: "This is a preview sentence with \(normalized).",
                    exampleTranslation: "\(normalized) を使ったプレビュー用の例文です。"
                ),
                WordSense(
                    partOfSpeech: "verb",
                    meaningJapanese: "プレビュー用の日本語訳 2",
                    exampleSentence: "They preview how to use \(normalized) in context.",
                    exampleTranslation: "彼らは \(normalized) の使い方を文脈の中で確認します。"
                )
            ],
            contextualMeanings: [
                ContextualMeaning(
                    sentence: "I picked up the book from the desk.",
                    sentenceTranslation: "私は机の上からその本を手に取りました。",
                    meaningJapanese: "本",
                    explanationJapanese: "具体的な物としての book を表しています。"
                ),
                ContextualMeaning(
                    sentence: "I booked a room near the station.",
                    sentenceTranslation: "私は駅の近くの部屋を予約しました。",
                    meaningJapanese: "予約する",
                    explanationJapanese: "動詞として使われ、宿泊先を予約する意味になります。"
                )
            ],
            generatedBy: "Preview"
        )
    }
}
