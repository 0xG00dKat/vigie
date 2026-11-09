import SwiftUI
import VigieCore

/// Alertes et règles : les alertes de vitesse, et les règles de l'utilisateur
/// (« préviens-moi si Slack dépasse 4 Go », « quitte Slack à 19 h »).
struct RulesPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: tr("Alertes et règles", "Alerts and rules"),
                           subtitle: tr("Vigie peut te prévenir, ou faire une chose simple à ta place. Tout reste sur ton Mac, et une app n'est jamais fermée de force.",
                                        "Vigie can warn you, or do one simple thing for you. Everything stays on your Mac, and an app is never force quit.")) { EmptyView() }
                    .padding(.horizontal, -VigieTheme.pagePadding)
                    .padding(.bottom, -16)
                AlertsCard(compact: false)
                // Tes règles à gauche, en ajouter une à droite : tout se voit sans défiler.
                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow(alignment: .top) {
                        BentoCell { RulesListCard() }
                        BentoCell { NewRuleCard() }
                    }
                }
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
        }
    }
}

struct RulesListCard: View {
    @Environment(AppModel.self) private var model

    /// « aujourd'hui à 19:00 », « demain à 19:00 », dans la langue de Vigie.
    static func when(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Localization.current == .fr ? "fr_FR" : "en_US")
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        VigieCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Tes règles", "Your rules")).font(.system(size: 14, weight: .semibold))
                if model.rules.isEmpty {
                    Text(tr("Aucune règle pour l'instant. Ajoute-en une à droite.", "No rule yet. Add one on the right."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(model.rules) { rule in
                    HStack(spacing: 10) {
                        Image(systemName: rule.kind.symbol)
                            .foregroundStyle(rule.isEnabled ? VigieTheme.accent : Color.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.summary.text).font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(rule.isEnabled ? Color.primary : Color.secondary)
                            if case .quitAt = rule.kind, rule.isEnabled, let next = RuleEngine.nextQuit(rule, after: Date()) {
                                Text(tr("Prochaine fois : \(Self.when(next))", "Next time: \(Self.when(next))"))
                                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { rule.isEnabled }, set: { model.setRule(rule.id, enabled: $0) }))
                            .toggleStyle(.switch).controlSize(.small).labelsHidden()
                        Button {
                            model.deleteRule(rule.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        // Gris, comme le × des lignes : la couleur d'accent est réservée à l'action principale.
                        .foregroundStyle(.secondary)
                        .help(tr("Supprimer cette règle", "Delete this rule"))
                    }
                    Divider()
                }
                Text(tr("Une alerte part une fois par dépassement. Une app quittée par une règle peut te demander d'enregistrer : Vigie ne force jamais. Vigie regarde une fois par minute tant qu'une règle est active, même fermée.",
                        "An alert is sent once per crossing. An app quit by a rule may ask you to save: Vigie never forces. Vigie checks once a minute while a rule is on, even when closed."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct NewRuleCard: View {
    @Environment(AppModel.self) private var model
    @State private var isQuit = false
    @State private var appName = ""
    @State private var gigabytes = 3
    @State private var time = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()

    var body: some View {
        let candidates = model.ruleCandidates
        VigieCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("Ajouter une règle", "Add a rule")).font(.system(size: 14, weight: .semibold))
                PageTabs(selection: $isQuit, tabs: [
                    (false, tr("Me prévenir", "Warn me"), "bell"),
                    (true, tr("Quitter à une heure", "Quit at a time"), "clock"),
                ])
                HStack(spacing: 10) {
                    Text(tr("App", "App")).frame(width: 90, alignment: .leading).foregroundStyle(.secondary)
                    Picker("", selection: $appName) {
                        Text(tr("Choisir…", "Choose…")).tag("")
                        ForEach(candidates, id: \.name) { candidate in Text(candidate.name).tag(candidate.name) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }
                if isQuit {
                    HStack(spacing: 10) {
                        Text(tr("Chaque jour à", "Every day at")).frame(width: 90, alignment: .leading).foregroundStyle(.secondary)
                        DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                    }
                } else {
                    HStack(spacing: 10) {
                        Text(tr("Au-delà de", "Above")).frame(width: 90, alignment: .leading).foregroundStyle(.secondary)
                        Stepper(tr("\(gigabytes) Go de mémoire", "\(gigabytes) GB of memory"), value: $gigabytes, in: 1...64)
                    }
                }
                Button(tr("Ajouter", "Add")) { add(candidates) }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(appName.isEmpty)
                Text(tr("Seules les apps ouvertes en ce moment sont proposées. macOS, le Finder et Vigie ne peuvent pas être quittés par une règle.",
                        "Only apps open right now are offered. macOS, the Finder and Vigie can't be quit by a rule."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .font(.system(size: 12.5))
        }
    }

    private func add(_ candidates: [(name: String, bundleID: String?)]) {
        guard let candidate = candidates.first(where: { $0.name == appName }) else { return }
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let kind: VigieRule.Kind = isQuit ? .quitAt(hour: components.hour ?? 19, minute: components.minute ?? 0)
                                          : .memoryAbove(bytes: UInt64(gigabytes) * 1_000_000_000)
        model.addRule(VigieRule(appName: candidate.name, bundleID: candidate.bundleID, kind: kind))
        appName = ""
    }
}

extension VigieRule.Kind {
    var symbol: String {
        switch self {
        case .memoryAbove: return "bell.badge"
        case .quitAt: return "clock.badge.xmark"
        }
    }
}
