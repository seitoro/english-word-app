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
    @Query(sort: \WordEntry.createdAt, order: .forward) private var entries: [WordEntry]
    @StateObject private var subscriptionManager = SubscriptionManager()
    @StateObject private var usageQuotaManager = UsageQuotaManager()
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
    @FocusState private var focusedField: FocusedField?
#if os(iOS)
    @State private var isKeyboardVisible = false
#endif

    private let generator: any WordEntryGenerating
    private let isGeneratorAvailable = WordEntryGeneratorFactory.isAvailable
    private let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    init(generator: any WordEntryGenerating = WordEntryGeneratorFactory.makeGenerator()) {
        self.generator = generator
    }

    var body: some View {
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
        .sheet(isPresented: $isShowingSettings) {
            settingsSheet
        }
        .task {
            guard isPreview == false else {
                seedPreviewQuotaIfNeeded()
                return
            }

            await subscriptionManager.prepare()
            usageQuotaManager.refresh()
            rewardedAdManager.prepare()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                usageQuotaManager.refresh()
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
                Section("Premium") {
                    settingsValueRow(
                        title: "利用プラン",
                        value: subscriptionManager.hasPremiumAccess ? "Premium" : "無料"
                    )

                    Button("Premiumの詳細") {
                        isShowingPremiumDetails = true
                    }

                    Button(subscriptionManager.isRestoring ? "復元中..." : "購入を復元") {
                        Task {
                            await subscriptionManager.restorePurchases()
                        }
                    }
                    .disabled(subscriptionManager.isRestoring || subscriptionManager.isLoading)
                }

                Section("利用状況") {
                    settingsValueRow(title: "残り作成回数", value: remainingCreationCountText)
                    settingsValueRow(title: "登録済み単語", value: "\(wordEntryCount)件")
                    settingsValueRow(title: "登録済み熟語", value: "\(phraseEntryCount)件")
                }

                Section("サポート") {
                    settingsValueRow(title: "AI生成", value: "OpenAI")
                    settingsValueRow(title: "広告追加", value: "1回で3回追加")
                    settingsValueRow(title: "Premium内容", value: "広告なし・AI自動テスト")
                }

                Section("法務・お問い合わせ") {
                    settingsLegalRow(title: "利用規約", path: "terms.html")
                    settingsLegalRow(title: "プライバシーポリシー", path: "privacy.html")
                    settingsLegalRow(title: "お問い合わせ", path: "contact.html")
                }

                Section("アプリ情報") {
                    settingsValueRow(title: "アプリ名", value: "English word app")
                    settingsValueRow(title: "バージョン", value: appVersionText)
                    settingsValueRow(title: "ビルド", value: appBuildText)
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
            .sheet(item: $selectedLegalPage) { legalPage in
#if os(iOS)
                LegalPageSafariView(url: legalPage.url)
                    .ignoresSafeArea()
#else
                EmptyView()
#endif
            }
        }
    }

    private var testTab: some View {
        NavigationStack {
            Color.clear
                .ignoresSafeArea()
                .navigationTitle("テスト")
                .toolbar {
                    settingsToolbarButton
                }
        }
    }

    private var createTab: some View {
        NavigationStack {
            List {
                inputSection

                if let generatedDraft {
                    generatedSection(
                        draft: generatedDraft,
                        visibleSenses: visibleSenses(for: generatedDraft)
                    )
                }
            }
#if os(iOS)
            .scrollDismissesKeyboard(.immediately)
            .background(KeyboardDismissOnTapView {
                dismissKeyboard()
            })
            .safeAreaInset(edge: .bottom, spacing: 0) {
                keyboardDismissBar
            }
#endif
            .navigationTitle("作成")
            .toolbar {
                settingsToolbarButton
            }
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
            List {
                listCategoryTabs
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 0, trailing: 4))
                .listRowBackground(Color.clear)

                savedWordsSection
            }
#if os(iOS)
            .listSectionSpacing(8)
#endif
            .navigationTitle("一覧")
            .toolbar {
                settingsToolbarButton
            }
        }
    }

    private var listCategoryTabs: some View {
        HStack(spacing: 0) {
            listCategoryTabButton(title: "単語", category: .word)
            listCategoryTabButton(title: "熟語", category: .phrase)
        }
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
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(isSelected ? Color.white : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var searchTab: some View {
        NavigationStack {
            List {
                Section {
                    TextField("英単語または熟語を検索", text: searchBinding)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .searchInput)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.asciiCapable)
#endif
                }

                if searchResults.isEmpty {
                    if searchText.isEmpty {
                        Text("保存した単語や熟語を検索できます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("一致する単語や熟語はありません。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    searchResultsSection
                }
            }
#if os(iOS)
            .listSectionSpacing(8)
#endif
#if os(iOS)
            .scrollDismissesKeyboard(.immediately)
            .background(KeyboardDismissOnTapView {
                dismissKeyboard()
            })
            .safeAreaInset(edge: .bottom, spacing: 0) {
                keyboardDismissBar
            }
#endif
            .navigationTitle("検索")
            .toolbar {
                settingsToolbarButton
            }
            .onAppear {
                restoreFocusIfNeeded(.searchInput)
            }
        }
    }

    @ToolbarContentBuilder
    private var settingsToolbarButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
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
                    description: "英単語や熟語から意味と例文を作成します。",
                    systemImage: "sparkles"
                )
            }
            .buttonStyle(.plain)

            Button {
                selectedTab = .search
            } label: {
                homeShortcutCard(
                    title: "検索",
                    description: "保存済みの単語や熟語をすぐに探せます。",
                    systemImage: "magnifyingglass"
                )
            }
            .buttonStyle(.plain)

            Button {
                selectedTab = .list
            } label: {
                homeShortcutCard(
                    title: "一覧",
                    description: "英単語と熟語を分けてまとめて見られます。",
                    systemImage: "list.bullet"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var inputSection: some View {
        Section {
            TextField("英単語または熟語を入力", text: $inputWord)
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
            .disabled(isGenerating || isGeneratorAvailable == false)

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

                Button(rewardedAdManager.isLoading ? "広告を読み込み中..." : "広告を見て3回追加") {
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
                .disabled(rewardedAdManager.isLoading)
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
#if os(iOS)
        .fullScreenCover(isPresented: $isShowingPremiumDetails) {
            premiumDetailsSheet
        }
#else
        .sheet(isPresented: $isShowingPremiumDetails) {
            premiumDetailsSheet
        }
#endif
    }

    private var premiumDetailsSheet: some View {
        NavigationStack {
            List {
                Section {
                    Label("広告なしで利用", systemImage: "checkmark.circle.fill")
                    Label("AI自動テスト機能", systemImage: "checkmark.circle.fill")
                    Label("今後のPremium向け機能追加", systemImage: "checkmark.circle.fill")
                }

                Section {
                    Button(subscriptionManager.isPurchasing ? "購入中..." : "Premiumをはじめる") {
                        Task {
                            await subscriptionManager.purchasePremium()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(subscriptionManager.isPurchasing || subscriptionManager.isLoading)
                }
            }
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

    private var availabilityMessage: String {
        WordEntryGeneratorFactory.availabilityMessage
    }

    private var wordEntryCount: Int {
        entries.filter { entry in
            entryKind(for: entry.word, senses: entry.senses) == .word
        }.count
    }

    private var phraseEntryCount: Int {
        entries.filter { entry in
            entryKind(for: entry.word, senses: entry.senses) == .phrase
        }.count
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
            let primarySense = visibleSenses.first ?? draft.primarySense
            let entry = WordEntry(
                word: draft.word,
                meaningJapanese: primarySense.meaningJapanese,
                exampleSentence: primarySense.exampleSentence,
                exampleTranslation: primarySense.exampleTranslation,
                senses: visibleSenses,
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

    private func hasSavedEntry(for word: String) -> Bool {
        let normalizedWord = normalizedEntryText(word)
        guard normalizedWord.isEmpty == false else {
            return false
        }

        return entries.contains { entry in
            normalizedEntryText(entry.word) == normalizedWord
        }
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

    private func categorizedEntriesSection(kind: EntryKind) -> some View {
        let filteredEntries = entries.enumerated().filter { _, entry in
            entryKind(for: entry.word, senses: entry.senses) == kind
        }

        return Section {
            if filteredEntries.isEmpty {
                Text(kind == .word ? "英単語はまだありません" : "熟語はまだありません")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredEntries, id: \.element.persistentModelID) { index, entry in
                    NavigationLink {
                        WordEntryDetailView(entry: entry)
                    } label: {
                        entryRow(index: index, entry: entry)
                    }
                }
                .onDelete { offsets in
                    let indexesToDelete = IndexSet(offsets.map { filteredEntries[$0].offset })
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

    private var searchResults: [(offset: Int, entry: WordEntry)] {
        let normalizedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedQuery.isEmpty == false else {
            return []
        }

        return entries.enumerated().compactMap { index, entry in
            guard entrySearchText(for: entry).contains(normalizedQuery) else {
                return nil
            }
            return (offset: index, entry: entry)
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
            .simultaneousGesture(TapGesture().onEnded {
                dismissKeyboard()
            })
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
            return "熟語"
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
            return "単語を保存"
        case .phrase:
            return "熟語を保存"
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
            guard let touchedView = touch.view else {
                return true
            }

            var currentView: UIView? = touchedView
            while let view = currentView {
                if view is UIControl || view is UITextField || view is UITextView {
                    return false
                }
                currentView = view.superview
            }

            return true
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

    return URL(string: "https://ryuseiokada.github.io/english-word-app/")!
}()

private func settingsValueRow(title: String, value: String) -> some View {
    HStack {
        Text(title)
        Spacer()
        Text(value)
            .foregroundStyle(.secondary)
    }
}

private func settingsRowLabel(title: String) -> some View {
    HStack {
        Text(title)
            .foregroundStyle(.primary)
        Spacer()
        Image(systemName: "arrow.up.right.square")
            .foregroundStyle(.secondary)
    }
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
            Section("単語情報") {
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
            return "熟語"
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
            return "熟語"
        }
    }
}

func entryKind(for word: String, senses: [WordSense]) -> EntryKind {
    let normalizedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalizedWord.contains(where: \.isWhitespace) {
        return .phrase
    }

    let phrasePartsOfSpeech = Set(["phrase", "idiom", "phrasal verb", "expression"])
    if senses.contains(where: { phrasePartsOfSpeech.contains($0.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }) {
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
