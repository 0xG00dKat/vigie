import AppKit
import SwiftUI
import VigieCore

/// « Comprendre mon Mac » : une famille à part dans la colonne d'icônes. L'accueil (« Par où commencer ») part de ce
/// qui arrive au Mac : chaque question ouvre quelques explications à lire dans l'ordre. Les thèmes sont dans le sous-menu.
struct LearnPage: View {
    @Environment(AppModel.self) private var model
    let lesson: String?
    @Binding var page: WindowPage?
    /// La recherche de Comprendre : explications et mots du glossaire.
    @State private var search = ""

    init(lesson: String? = nil, page: Binding<WindowPage?>) {
        self.lesson = lesson
        _page = page
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let id = lesson, let lesson = Lessons.lesson(id) {
                    LessonArticle(lesson: lesson, page: $page)
                } else {
                    home
                }
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
        }
    }

    /// L'accueil de Comprendre : la recherche, l'explication du moment, les questions, les thèmes, la fiche et le glossaire.
    @ViewBuilder private var home: some View {
        let featured = LessonLive.featured(model)
        PageHeader(title: tr("Comprendre mon Mac", "Understand my Mac"),
                   subtitle: tr("Pars de ce qui t'arrive : quelques explications courtes, avec tes vrais chiffres.",
                                "Start from what's happening: a few short explanations, with your real numbers.")) { EmptyView() }
            .padding(.horizontal, -VigieTheme.pagePadding)
            .padding(.bottom, -16)
        LearnSearchField(text: $search, placeholder: tr("Rechercher une explication ou un mot (swap, cache, iCloud…)",
                                                        "Search an explanation or a word (swap, cache, iCloud…)"))
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            LearnSearchResults(search: search, page: $page)
        } else {
            homeSections(featured)
        }
    }

    @ViewBuilder private func homeSections(_ featured: String) -> some View {
        if let lesson = Lessons.lesson(featured) {
            FeaturedLessonCard(lesson: lesson, page: $page)
        }
        LearnSectionTitle(tr("Qu'est-ce qui t'arrive ?", "What's happening?"))
        let questions = LessonQuestions.visible(developer: model.isDeveloper)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: WindowGrid.gap, alignment: .top), count: 3), spacing: WindowGrid.gap) {
            ForEach(questions.filter { !$0.isDeveloper }) { question in
                QuestionCard(question: question, concerned: question.lessonIDs.contains(featured), page: $page)
            }
        }
        // Mode Développeur : sa question en bandeau, sous la grille de six.
        ForEach(questions.filter(\.isDeveloper)) { question in
            QuestionCard(question: question, concerned: question.lessonIDs.contains(featured), wide: true, page: $page)
        }
        // Les thèmes : toutes les explications, rangées ; des cartes de même taille sur une seule rangée.
        let topics = LessonTopic.allCases.filter { model.isDeveloper || $0 != .developer }
        LearnSectionTitle(tr("Par thème", "By topic"))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: WindowGrid.gap, alignment: .top), count: topics.count), spacing: WindowGrid.gap) {
            ForEach(topics, id: \.self) { topic in
                let count = Lessons.visible(developer: model.isDeveloper).filter { $0.topic == topic }.count
                LearnLinkCard(symbol: topic.symbol, title: topic.title.text,
                              detail: tr("\(count) explications", "\(count) explanations"), height: 112) {
                    page = .learnTopic(topic)
                }
            }
        }
        // Pour aller plus loin : la fiche du Mac et le glossaire, côte à côte.
        LearnSectionTitle(tr("Aller plus loin", "Go further"))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: WindowGrid.gap, alignment: .top), count: 2), spacing: WindowGrid.gap) {
            LearnLinkCard(symbol: "person.crop.circle", title: tr("Mon Mac en fiche", "My Mac at a glance"),
                          detail: tr("Puce, mémoire, disque, macOS, batterie : ce qu'il a sous le capot.",
                                     "Chip, memory, disk, macOS, battery: what's under the hood."), height: 96) {
                page = .macProfile
            }
            LearnLinkCard(symbol: "doc.text", title: tr("Glossaire", "Glossary"),
                          detail: tr("\(Glossary.visible(developer: model.isDeveloper).count) mots de Vigie et de macOS, en une phrase.",
                                     "\(Glossary.visible(developer: model.isDeveloper).count) Vigie and macOS words, in one sentence."), height: 96) {
                page = .glossary
            }
        }
    }
}

/// La recherche de Comprendre : un grand champ arrondi.
struct LearnSearchField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 13.5, weight: .medium)).foregroundStyle(DS.secondaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DS.tertiaryText) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .panelSurface(radius: 14)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(focused ? DS.accent.opacity(0.6) : .clear, lineWidth: 1.5))
    }
}

/// Une carte-lien de Comprendre : icône, titre, une phrase, chevron ; même hauteur dans sa rangée.
struct LearnLinkCard: View {
    let symbol: String
    let title: String
    let detail: String
    var height: CGFloat = 96
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(VigieMotion.standard) { action() }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VigieTile(symbol: symbol, size: 30)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(hovering ? DS.accent : DS.tertiaryText)
                }
                Spacer(minLength: 0)
                Text(title).font(.system(size: 13.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(DS.secondaryText).lineLimit(2).multilineTextAlignment(.leading)
            }
            .padding(WindowGrid.cardPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: height)
            .panelSurface()
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DS.accent.opacity(hovering ? 0.5 : 0), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(VigieMotion.quick, value: hovering)
    }
}

/// Résultats de la recherche : les explications puis les mots du glossaire.
struct LearnSearchResults: View {
    @Environment(AppModel.self) private var model
    let search: String
    @Binding var page: WindowPage?

    var body: some View {
        let needle = search.trimmingCharacters(in: .whitespaces)
        let lessons = Lessons.visible(developer: model.isDeveloper).filter { lesson in
            ([lesson.title, lesson.summary, lesson.takeaway] + lesson.paragraphs).contains { $0.text.localizedStandardContains(needle) }
        }
        let terms = Glossary.visible(developer: model.isDeveloper).filter {
            $0.term.text.localizedStandardContains(needle) || $0.definition.text.localizedStandardContains(needle)
        }
        if lessons.isEmpty && terms.isEmpty {
            Text(tr("Rien ne correspond à « \(needle) ».", "Nothing matches “\(needle)”."))
                .font(.system(size: 13)).foregroundStyle(DS.secondaryText)
                .padding(.top, 8)
        }
        if !lessons.isEmpty {
            LearnSectionTitle(tr("Explications · \(lessons.count)", "Explanations · \(lessons.count)"))
            VStack(spacing: WindowGrid.gap) {
                ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                    QuestionStepRow(number: index + 1, lesson: lesson) {
                        model.learnPath = nil
                        withAnimation(VigieMotion.standard) { page = .lesson(lesson.id) }
                    }
                }
            }
        }
        if !terms.isEmpty {
            LearnSectionTitle(tr("Glossaire · \(terms.count)", "Glossary · \(terms.count)"))
            GlossaryList(terms: terms, page: $page)
        }
    }
}

/// Petit titre de section en capitales, comme sur les autres pages.
struct LearnSectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold)).tracking(0.6)
            .foregroundStyle(DS.secondaryText)
            .padding(.top, WindowGrid.sectionTop)
    }
}

/// Une question (« Mon Mac est lent ») : ce qu'on va comprendre, combien d'explications, et un repère quand
/// elle parle de ce qui se passe sur le Mac en ce moment.
struct QuestionCard: View {
    @Environment(AppModel.self) private var model
    let question: LessonQuestion
    let concerned: Bool
    /// En bandeau sur toute la largeur (la question du mode Développeur).
    var wide = false
    @Binding var page: WindowPage?
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(VigieMotion.standard) { page = .learnQuestion(question.id) }
        } label: {
            Group {
                if wide { wideLabel } else { label }
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(VigieTheme.accent.opacity(hovering ? 0.5 : 0), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(VigieMotion.quick, value: hovering)
    }

    private var count: Int { question.lessons(developer: model.isDeveloper).count }

    private var read: Int { question.lessons(developer: model.isDeveloper).filter { model.readLessons.contains($0.id) }.count }

    /// « 6 explications · 6 min », puis « 2 sur 6 lues », puis « Tout lu ».
    private var countText: some View {
        HStack(spacing: 5) {
            if read == count {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(VigieTheme.accent)
                Text(tr("Tout lu", "All read"))
            } else if read > 0 {
                Text(tr("\(read) sur \(count) lues", "\(read) of \(count) read"))
            } else {
                Text(tr("\(count) explications · \(count) min", "\(count) explanations · \(count) min"))
            }
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(DS.tertiaryText)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(hovering ? VigieTheme.accent : DS.tertiaryText)
    }

    private var wideLabel: some View {
        HStack(spacing: 14) {
            VigieTile(symbol: question.symbol, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(question.title.text).font(.system(size: 15, weight: .semibold))
                Text(question.subtitle.text).font(.system(size: 12.5)).foregroundStyle(DS.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 12)
            countText
            chevron
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelSurface()
    }

    private var label: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VigieTile(symbol: question.symbol, size: 40)
                    Spacer()
                    if concerned {
                        Text(tr("En ce moment", "Right now"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(VigieTheme.accent)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(VigieTheme.accent.opacity(0.14)))
                    }
                }
                Text(question.title.text)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 4)
                Text(question.subtitle.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                HStack {
                    countText
                    Spacer()
                    chevron
                }
            }
            .padding(WindowGrid.heroPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 184)
            .panelSurface()
    }
}

extension LessonTopic {
    var symbol: String {
        switch self {
        case .basics: return "book"
        case .speed: return "gauge.with.needle"
        case .disk: return "internaldrive"
        case .battery: return "bolt"
        case .developer: return "terminal"
        }
    }
}

/// En-tête des pages de Comprendre : l'icône, le titre, une phrase, et le retour à droite.
struct LearnHeader: View {
    let symbol: String
    var eyebrow: String? = nil
    let title: String
    let subtitle: String
    let back: String
    let onBack: () -> Void

    var body: some View {
        // Le titre en premier, sur la même ligne de base que les autres pages ; l'étape en cours dessous.
        HStack(alignment: .top, spacing: 16) {
            PageIconTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 22, weight: .semibold))
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(DS.secondaryText)
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10.5, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(VigieTheme.accent)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 16)
            Button {
                withAnimation(VigieMotion.standard) { onBack() }
            } label: {
                Label(back, systemImage: "chevron.left").lineLimit(1)
            }
            .buttonStyle(HUDPillButtonStyle())
        }
        .padding(.top, WindowGrid.top(forTitle: 22))
    }
}

/// Une question : ses explications, numérotées, à lire dans l'ordre.
struct LearnQuestionPage: View {
    @Environment(AppModel.self) private var model
    let questionID: String
    @Binding var page: WindowPage?

    var body: some View {
        ScrollView {
            if let question = LessonQuestions.question(questionID) {
                let lessons = question.lessons(developer: model.isDeveloper)
                VStack(alignment: .leading, spacing: 16) {
                    LearnHeader(symbol: question.symbol, title: question.title.text, subtitle: question.subtitle.text,
                                back: tr("Comprendre mon Mac", "Understand my Mac")) { page = .learn }
                    let read = lessons.filter { model.readLessons.contains($0.id) }.count
                    LearnSectionTitle(read == 0
                        ? tr("À lire dans l'ordre · une minute chacune", "Read in order · one minute each")
                        : tr("À lire dans l'ordre · \(read) sur \(lessons.count) lues", "Read in order · \(read) of \(lessons.count) read"))
                    VStack(spacing: WindowGrid.gap) {
                        ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                            QuestionStepRow(number: index + 1, lesson: lesson) {
                                model.learnPath = question.id
                                withAnimation(VigieMotion.standard) { page = .lesson(lesson.id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, VigieTheme.pagePadding)
                .padding(.bottom, WindowGrid.pageBottom)
            }
        }
    }
}

/// Une étape d'une question : son numéro, son titre, une phrase et le chiffre du Mac qui la concerne.
struct QuestionStepRow: View {
    @Environment(AppModel.self) private var model
    let number: Int
    let lesson: Lesson
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 16) {
                let read = model.readLessons.contains(lesson.id)
                Group {
                    if read {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(VigieTheme.accent)
                    } else {
                        Text("\(number)").font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(DS.primaryText)
                    }
                }
                .frame(width: 34, height: 34)
                .background(Circle().fill(read ? VigieTheme.accent.opacity(0.14) : DS.well))
                .help(read ? tr("Déjà lue", "Already read") : "")
                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.title.text).font(.system(size: 14.5, weight: .semibold))
                    Text(lesson.summary.text).font(.system(size: 12.5)).foregroundStyle(DS.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 12)
                if let live = LessonLive.headline(lesson.id, model) {
                    Text(live)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.secondaryText)
                        .lineLimit(1)
                        .frame(maxWidth: 260, alignment: .trailing)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hovering ? VigieTheme.accent : DS.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelSurface()
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(VigieTheme.accent.opacity(hovering ? 0.5 : 0), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(VigieMotion.quick, value: hovering)
    }
}

/// Un thème : toutes ses explications, en cartes.
struct LearnTopicPage: View {
    @Environment(AppModel.self) private var model
    let topic: LessonTopic
    @Binding var page: WindowPage?

    var body: some View {
        let lessons = Lessons.visible(developer: model.isDeveloper).filter { $0.topic == topic }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LearnHeader(symbol: topic.symbol, title: topic.title.text,
                            subtitle: tr("\(lessons.count) explications, une minute chacune.", "\(lessons.count) explanations, one minute each."),
                            back: tr("Comprendre mon Mac", "Understand my Mac")) { page = .learn }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: WindowGrid.gap, alignment: .top), count: 3), spacing: WindowGrid.gap) {
                    ForEach(lessons) { lesson in
                        LessonCard(lesson: lesson, page: $page)
                    }
                }
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
        }
    }
}

/// Une explication dans la grille : toutes les cartes ont la même taille, le texte se coupe proprement.
struct LessonCard: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson
    @Binding var page: WindowPage?
    @State private var hovering = false

    var body: some View {
        Button {
            model.learnPath = nil
            withAnimation(VigieMotion.standard) { page = .lesson(lesson.id) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VigieTile(symbol: lesson.symbol, size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.title.text)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(lesson.summary.text)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if let live = LessonLive.headline(lesson.id, model) {
                        Text(live)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(VigieTheme.accent)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 132)
            .overlay(alignment: .topTrailing) {
                if model.readLessons.contains(lesson.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(VigieTheme.accent)
                        .padding(12)
                        .help(tr("Déjà lue", "Already read"))
                }
            }
            .panelSurface()
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(VigieTheme.accent.opacity(hovering ? 0.5 : 0), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(VigieMotion.quick, value: hovering)
    }
}

/// En tête de « Comprendre » : l'explication qui parle de ce qui se passe sur ton Mac en ce moment.
struct FeaturedLessonCard: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson
    @Binding var page: WindowPage?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VigieTile(symbol: lesson.symbol, size: 48)
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("EN CE MOMENT SUR MON MAC", "RIGHT NOW ON MY MAC"))
                    .font(.system(size: 10.5, weight: .semibold)).tracking(0.6).foregroundStyle(DS.secondaryText)
                Text(lesson.title.text).font(.system(size: 19, weight: .semibold))
                if let live = LessonLive.headline(lesson.id, model) {
                    Text(live).font(.system(size: 13.5, weight: .medium)).foregroundStyle(VigieTheme.accent)
                }
                Text(lesson.summary.text).font(.system(size: 12.5)).foregroundStyle(DS.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(tr("Lire", "Read")) {
                model.learnPath = nil
                withAnimation(VigieMotion.standard) { page = .lesson(lesson.id) }
            }
                .buttonStyle(HUDPillButtonStyle(prominent: true))
        }
        .padding(WindowGrid.heroPadding)
        .panelSurface()
    }
}

struct LessonArticle: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson
    @Binding var page: WindowPage?

    /// La question en cours de lecture, si l'explication en fait partie.
    private var path: (question: LessonQuestion, lessons: [Lesson], index: Int)? {
        guard let id = model.learnPath, let question = LessonQuestions.question(id) else { return nil }
        let lessons = question.lessons(developer: model.isDeveloper)
        guard let index = lessons.firstIndex(where: { $0.id == lesson.id }) else { return nil }
        return (question, lessons, index)
    }

    var body: some View {
        let path = path
        VStack(alignment: .leading, spacing: 16) {
            LearnHeader(symbol: lesson.symbol,
                        eyebrow: path.map { tr("\($0.question.title.text) · \($0.index + 1) sur \($0.lessons.count)",
                                               "\($0.question.title.text) · \($0.index + 1) of \($0.lessons.count)") },
                        title: lesson.title.text, subtitle: lesson.summary.text,
                        back: path?.question.title.text ?? lesson.topic.title.text) {
                if let path { page = .learnQuestion(path.question.id) } else { page = .learnTopic(lesson.topic) }
            }
            HStack(alignment: .top, spacing: 20) {
                // L'explication, en colonne de lecture.
                VStack(alignment: .leading, spacing: 14) {
                    // Un schéma vivant quand l'explication s'y prête : la mémoire ou le disque, avec tes chiffres.
                    LessonDiagram(lessonID: lesson.id)
                    ForEach(Array(lesson.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph.text)
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill").foregroundStyle(VigieTheme.accent)
                        Text(lesson.takeaway.text).font(.system(size: 13.5, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(VigieTheme.accent.opacity(0.1)))
                    if let path { next(path) }
                }
                .frame(maxWidth: 620, alignment: .leading)
                // À droite : tes chiffres, et ce que tu peux faire.
                LessonLiveCard(lessonID: lesson.id, page: $page)
                    .frame(width: 280)
            }
        }
        .onAppear { model.markLessonRead(lesson.id) }
    }

    /// Fin d'une étape : l'explication suivante, ou le retour aux questions à la dernière.
    @ViewBuilder
    private func next(_ path: (question: LessonQuestion, lessons: [Lesson], index: Int)) -> some View {
        HStack {
            Spacer()
            if path.index + 1 < path.lessons.count {
                let following = path.lessons[path.index + 1]
                Button {
                    withAnimation(VigieMotion.standard) { page = .lesson(following.id) }
                } label: {
                    Label(tr("Suivant : \(following.title.text)", "Next: \(following.title.text)"), systemImage: "arrow.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .lineLimit(1)
                }
                .buttonStyle(HUDPillButtonStyle(prominent: true))
            } else {
                Button {
                    model.learnPath = nil
                    withAnimation(VigieMotion.standard) { page = .learn }
                } label: {
                    Label(tr("Terminé · revenir aux questions", "Done · back to the questions"), systemImage: "checkmark")
                }
                .buttonStyle(HUDPillButtonStyle(prominent: true))
            }
        }
        .padding(.top, 4)
    }
}

/// Le texte d'abord, l'icône après (« Suivant → »).
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

/// « Sur mon Mac en ce moment » : les vrais chiffres liés à l'explication, et le bouton qui mène où agir.
struct LessonLiveCard: View {
    @Environment(AppModel.self) private var model
    let lessonID: String
    @Binding var page: WindowPage?

    var body: some View {
        let facts = LessonLive.facts(lessonID, model)
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("SUR MON MAC EN CE MOMENT", "ON MY MAC RIGHT NOW"))
                .font(.system(size: 10.5, weight: .semibold)).tracking(0.6).foregroundStyle(DS.secondaryText)
            if facts.isEmpty {
                Text(tr("Vigie n'a pas encore ces chiffres : fais le bilan (l'œil en haut à gauche).", "Vigie doesn't have these numbers yet: run the checkup (the eye at the top left)."))
                    .font(.system(size: 12)).foregroundStyle(DS.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                VStack(alignment: .leading, spacing: 2) {
                    Text(fact.value).font(.system(size: 20, weight: .bold).monospacedDigit())
                    Text(fact.label).font(.system(size: 11.5)).foregroundStyle(DS.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let action = LessonLive.action(lessonID) {
                Button(action.title) {
                    if let target = action.page {
                        withAnimation(VigieMotion.standard) { page = target }
                    } else {
                        model.openTrash()
                    }
                }
                .buttonStyle(HUDPillButtonStyle(prominent: true))
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelSurface()
    }
}

/// Les vrais chiffres de chaque explication.
@MainActor
enum LessonLive {
    /// Cœurs du processeur (12 sur le Mac de démo : les captures ne montrent jamais le vrai Mac).
    static func cores(_ model: AppModel) -> Int { model.isDemo ? 12 : ProcessInfo.processInfo.activeProcessorCount }

    struct Fact {
        let value: String
        let label: String
    }

    /// L'explication à mettre en avant : ce qui se passe en ce moment.
    static func featured(_ model: AppModel) -> String {
        if let pressure = model.performance?.memory.pressure, pressure != .normal { return "memoire" }
        if let disk = model.disk, disk.isTight || disk.isLow { return "disque-se-remplit" }
        if model.trashedByVigie >= 1_000_000_000 { return "corbeille" }
        if let report = model.storage, model.reclaimable(report) >= 5_000_000_000 { return "caches" }
        return "processus"
    }

    /// Une ligne sous le titre de la carte : le chiffre qui parle.
    static func headline(_ id: String, _ model: AppModel) -> String? {
        facts(id, model).first.map { "\($0.value) · \($0.label)" }
    }

    static func facts(_ id: String, _ model: AppModel) -> [Fact] {
        var result: [Fact] = []
        switch id {
        case "memoire":
            if let snapshot = model.snapshot {
                result.append(Fact(value: "\(Format.bytes(snapshot.memoryUsed)) / \(Format.bytes(snapshot.memoryTotal))", label: tr("de mémoire utilisée", "of memory used")))
            }
            if let pressure = model.performance?.memory.pressure {
                result.append(Fact(value: pressure == .normal ? tr("Assez", "Enough") : pressure == .warning ? tr("Un peu juste", "A bit tight") : tr("Il en manque", "Not enough"),
                                   label: tr("selon macOS (la « pression » sur la mémoire)", "according to macOS (memory “pressure”)")))
            }
            if let top = model.memoryGroups.first {
                result.append(Fact(value: top.title, label: tr("prend le plus : \(Format.bytes(top.memory))", "uses the most: \(Format.bytes(top.memory))")))
            }
        case "swap":
            if let memory = model.performance?.memory {
                result.append(Fact(value: Format.bytes(memory.swapUsed), label: tr("rangés sur le disque faute de place en mémoire", "stored on the disk for lack of memory")))
            }
        case "processus":
            if let snapshot = model.snapshot {
                result.append(Fact(value: "\(snapshot.processCount)", label: tr("processus en ce moment", "processes right now")))
                let apps = model.visibleGroups(in: .apps).count
                result.append(Fact(value: "\(apps)", label: tr("apps ouvertes : Vigie range tout le reste derrière elles", "open apps: Vigie groups everything else behind them")))
            }
        case "disque-se-remplit":
            if let disk = model.disk {
                result.append(Fact(value: Format.bytes(disk.available, decimal: true), label: tr("libres sur \(Format.bytes(disk.total, decimal: true))", "free of \(Format.bytes(disk.total, decimal: true))")))
            }
            if let report = model.visibleReport,
               let growth = DiskDiagnosis.make(report: report, previous: model.storageReference).growthLine() {
                result.append(Fact(value: tr("Ce qui a grossi", "What grew"), label: growth))
            }
        case "caches":
            if let report = model.storage {
                result.append(Fact(value: Format.bytes(model.reclaimable(report), decimal: true), label: tr("de caches sur ton Mac", "of caches on your Mac")))
                let safe = model.safeCleanItems.reduce(UInt64(0)) { $0 + $1.size }
                if safe > 0 { result.append(Fact(value: Format.bytes(safe, decimal: true), label: tr("se vident sans risque", "can be safely cleared"))) }
            }
        case "donnees-systeme":
            if let report = model.storage {
                let size = report.entries(of: .systemData).reduce(UInt64(0)) { $0 + $1.size }
                if size > 0 { result.append(Fact(value: Format.bytes(size, decimal: true), label: tr("de « Données système » que Vigie sait expliquer", "of “System Data” Vigie can explain"))) }
            }
        case "corbeille":
            result.append(Fact(value: Format.bytes(model.trashedByVigie, decimal: true), label: tr("mis à la corbeille par Vigie, pas encore libérés", "moved to the Trash by Vigie, not freed yet")))
        case "batterie":
            if let battery = model.performance?.battery {
                result.append(Fact(value: "\(battery.percent) %", label: battery.charging ? tr("en charge", "charging") : tr("de batterie", "battery")))
                if let health = battery.health { result.append(Fact(value: "\(health) %", label: tr("de sa capacité d'origine", "of its original capacity"))) }
                if let cycles = battery.cycles { result.append(Fact(value: "\(cycles)", label: tr("cycles de charge", "charge cycles"))) }
            }
        case "demarrage":
            let items = model.startupItems
            if !items.isEmpty {
                result.append(Fact(value: "\(items.filter(\.isEnabled).count)", label: tr("programmes se lancent avec ton Mac", "programs start with your Mac")))
            }
        case "ports":
            if !model.portEntries.isEmpty {
                result.append(Fact(value: "\(model.portEntries.count)", label: tr("ports en écoute", "listening ports")))
                let exposed = model.portEntries.filter(\.isExposed).count
                result.append(Fact(value: "\(exposed)", label: tr("visibles sur le réseau", "visible on the network")))
            }
        case "bases-mac":
            result.append(Fact(value: "\(cores(model))", label: tr("cœurs de processeur", "processor cores")))
            if let snapshot = model.snapshot { result.append(Fact(value: Format.bytes(snapshot.memoryTotal), label: tr("de mémoire", "of memory"))) }
            if let disk = model.disk { result.append(Fact(value: Format.bytes(disk.total, decimal: true), label: tr("de disque", "of disk"))) }
        case "memoire-vs-disque":
            if let snapshot = model.snapshot { result.append(Fact(value: Format.bytes(snapshot.memoryUsed), label: tr("de mémoire utilisée (ce qui est ouvert)", "of memory used (what's open)"))) }
            if let disk = model.disk { result.append(Fact(value: Format.bytes(disk.total - min(disk.total, disk.available), decimal: true), label: tr("de disque utilisé (ce qui est rangé)", "of disk used (what's stored)"))) }
        case "quitter-vs-fermer", "apps-web":
            let apps = model.visibleGroups(in: .apps)
            result.append(Fact(value: "\(apps.count)", label: tr("apps ouvertes en ce moment", "apps open right now")))
            if let top = apps.max(by: { $0.memory < $1.memory }) {
                result.append(Fact(value: top.title, label: tr("\(top.processes.count) processus · \(Format.bytes(top.memory))", "\(top.processes.count) processes · \(Format.bytes(top.memory))")))
            }
        case "redemarrer":
            let hours = Int(ProcessInfo.processInfo.systemUptime / 3600)
            if !model.isDemo {
                result.append(Fact(value: hours >= 48 ? tr("\(hours / 24) jours", "\(hours / 24) days") : tr("\(hours) h", "\(hours) h"), label: tr("depuis le dernier démarrage", "since the last restart")))
            } else {
                result.append(Fact(value: tr("9 jours", "9 days"), label: tr("depuis le dernier démarrage", "since the last restart")))
            }
        case "processeur", "chaleur":
            if let busiest = model.busiest {
                result.append(Fact(value: "\(Int(busiest.averageCPU.rounded())) %", label: tr("pour \(busiest.name), l'app la plus active", "for \(busiest.name), the busiest app")))
            }
            result.append(Fact(value: "\(cores(model))", label: tr("cœurs : jusqu'à \(cores(model) * 100) % au total", "cores: up to \(cores(model) * 100)% in total")))
            if id == "chaleur", let thermal = model.performance?.thermal {
                result.insert(Fact(value: thermal == .normal ? tr("Normale", "Normal") : thermal == .warm ? tr("Tiède", "Warm") : tr("Élevée", "High"), label: tr("température selon macOS", "temperature according to macOS")), at: 0)
            }
        case "veille":
            if let blockers = model.performance?.blockers.filter({ !$0.isSystem }) {
                result.append(Fact(value: "\(blockers.count)", label: blockers.isEmpty ? tr("app empêche la veille", "app prevents sleep")
                                                                                         : tr("empêche\(blockers.count > 1 ? "nt" : "") la veille : \(blockers.map(\.name).joined(separator: ", "))", "preventing sleep: \(blockers.map(\.name).joined(separator: ", "))")))
            }
        case "time-machine":
            if let report = model.storage {
                result.append(Fact(value: "\(report.localSnapshots)", label: tr("instantanés Time Machine sur ce Mac", "Time Machine snapshots on this Mac")))
            }
        case "onglets":
            let browsers = ["Safari", "Google Chrome", "Chrome", "Brave Browser", "Arc", "Firefox", "Opera", "Microsoft Edge"]
            if let browser = model.visibleGroups(in: .apps).first(where: { browsers.contains($0.title) }) {
                result.append(Fact(value: Format.bytes(browser.memory), label: tr("pour \(browser.title), en \(browser.processes.count) processus", "for \(browser.title), in \(browser.processes.count) processes")))
            }
        case "telechargements":
            if let report = model.storage {
                let downloads = report.entries(of: .largeFile).filter { ($0.path ?? "").contains("/Downloads/") }
                if !downloads.isEmpty {
                    result.append(Fact(value: Format.bytes(downloads.reduce(0) { $0 + $1.size }, decimal: true), label: tr("en \(downloads.count) gros fichier\(downloads.count > 1 ? "s" : "") dans Téléchargements", "in \(downloads.count) large file\(downloads.count > 1 ? "s" : "") in Downloads")))
                }
            }
        case "node-modules":
            if let report = model.storage {
                let projects = report.entries(of: .project)
                if !projects.isEmpty { result.append(Fact(value: Format.bytes(projects.reduce(0) { $0 + $1.size }, decimal: true), label: tr("de dépendances et compilations dans \(projects.count) projets", "of dependencies and builds in \(projects.count) projects"))) }
            }
        case "docker-disque":
            if let virtual = model.docker?.virtualDisk {
                result.append(Fact(value: Format.bytes(virtual.allocated, decimal: true), label: tr("pour le disque de Docker (maximum \(Format.bytes(virtual.maximum, decimal: true)))", "for Docker's disk (up to \(Format.bytes(virtual.maximum, decimal: true)))")))
            }
        default:
            break
        }
        return result
    }

    /// Le bouton qui mène où agir (`page` nil : ouvrir la corbeille).
    static func action(_ id: String) -> (title: String, page: WindowPage?)? {
        switch id {
        case "memoire", "swap", "batterie", "demarrage": return (tr("Voir Vitesse et batterie", "See Speed and battery"), .speed)
        case "processus": return (tr("Voir ce qui tourne", "See what's running"), .running)
        case "disque-se-remplit": return (tr("Faire le bilan", "Run the checkup"), .checkup)
        case "caches": return (tr("Voir les caches", "See caches"), .storage(.cache))
        case "donnees-systeme": return (tr("Voir les Données système", "See System Data"), .storage(.systemData))
        case "corbeille": return (tr("Ouvrir la corbeille", "Open the Trash"), nil)
        case "ports": return (tr("Voir les ports", "See ports"), .ports)
        case "processeur", "chaleur", "veille": return (tr("Voir Vitesse et batterie", "See Speed and battery"), .speed)
        case "quitter-vs-fermer", "apps-web", "onglets": return (tr("Voir ce qui tourne", "See what's running"), .running)
        case "bases-mac": return (tr("Faire le bilan", "Run the checkup"), .checkup)
        case "memoire-vs-disque": return (tr("Voir la vue d'ensemble", "See the overview"), .overview)
        case "telechargements": return (tr("Voir les gros fichiers", "See large files"), .storage(.largeFile))
        case "node-modules": return (tr("Voir les projets", "See projects"), .storage(.project))
        case "docker-disque": return (tr("Voir Docker", "See Docker"), .docker)
        default: return nil
        }
    }
}

/// « En savoir plus » : ouvre l'explication dans la fenêtre (depuis le panneau comme depuis la fenêtre).
struct LearnMoreLink: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let lesson: String

    var body: some View {
        if Lessons.lesson(lesson) != nil {
            Button {
                model.learnPath = nil
                model.windowPageRequest = .lesson(lesson)
                openWindow(id: VigieWindow.id)
                NSApp.activate()
            } label: {
                Label(tr("En savoir plus", "Learn more"), systemImage: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11.5, weight: .medium))
            .help(Lessons.lesson(lesson)?.summary.text ?? "")
        }
    }
}

/// Schéma vivant : la mémoire en barre (apps, macOS, libre) ou le disque par niveau de risque, avec tes chiffres.
struct LessonDiagram: View {
    @Environment(AppModel.self) private var model
    let lessonID: String

    var body: some View {
        switch lessonID {
        case "memoire", "swap", "memoire-vs-disque", "bases-mac":
            if let snapshot = model.snapshot {
                let total = Double(max(snapshot.memoryTotal, 1))
                let used = Double(snapshot.memoryUsed)
                let appsSum = Double(snapshot.groups.filter { $0.category != .system }.reduce(UInt64(0)) { $0 + $1.memory })
                let apps = min(appsSum, used)
                let system = max(0, used - apps)
                diagram(title: tr("La mémoire de mon Mac", "My Mac's memory"), segments: [
                    (apps / total, VigieTheme.accent, tr("Tes apps · \(Format.bytes(UInt64(apps)))", "Your apps · \(Format.bytes(UInt64(apps)))")),
                    (system / total, DS.keep, tr("macOS · \(Format.bytes(UInt64(system)))", "macOS · \(Format.bytes(UInt64(system)))")),
                    (max(0, 1 - used / total), DS.well, tr("Libre · \(Format.bytes(UInt64(max(0, total - used))))", "Free · \(Format.bytes(UInt64(max(0, total - used))))")),
                ], note: (model.performance?.memory.swapUsed ?? 0) > 0
                    ? tr("Et \(Format.bytes(model.performance?.memory.swapUsed ?? 0)) rangés sur le disque (swap).", "Plus \(Format.bytes(model.performance?.memory.swapUsed ?? 0)) moved to the disk (swap).") : nil)
            }
        case "disque-se-remplit", "caches", "donnees-systeme", "telechargements":
            if let disk = model.disk {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("Le disque de mon Mac", "My Mac's disk")).font(.system(size: 12.5, weight: .semibold))
                    RiskBar(report: model.storage, disk: disk, kinds: model.visibleKinds)
                    HStack(spacing: 14) {
                        legend(DS.safe, tr("Se vide sans risque", "Safe to clear"))
                        legend(DS.review, tr("À vérifier", "Review"))
                        legend(DS.keep, tr("À garder", "Keep"))
                        legend(DS.well, tr("Libre · \(Format.bytes(disk.available, decimal: true))", "Free · \(Format.bytes(disk.available, decimal: true))"))
                    }
                }
                .padding(16)
                .panelSurface()
            }
        default:
            EmptyView()
        }
    }

    private func diagram(title: String, segments: [(Double, Color, String)], note: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12.5, weight: .semibold))
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(segment.1)
                            .frame(width: max(2, geometry.size.width * segment.0 - 2))
                    }
                }
            }
            .frame(height: 14)
            HStack(spacing: 14) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in legend(segment.1, segment.2) }
            }
            if let note { Text(note).font(.system(size: 11.5)).foregroundStyle(DS.secondaryText) }
        }
        .padding(16)
        .panelSurface()
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(title).font(.system(size: 11.5)).foregroundStyle(DS.secondaryText)
        }
        .fixedSize()
    }
}

/// « Mon Mac en fiche » : ce qu'il est, en une page.
struct MacProfilePage: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?

    var body: some View {
        let info = MacInfo.read(demo: model.isDemo)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: tr("Mon Mac en fiche", "My Mac at a glance"),
                           subtitle: tr("Ce qu'il a sous le capot, en clair. Tout est lu sur ce Mac, rien n'est envoyé.",
                                        "What's under the hood, in plain words. Everything is read on this Mac, nothing is sent.")) {
                    LearnBackPill(page: $page)
                }
                    .padding(.horizontal, -VigieTheme.pagePadding)
                    .padding(.bottom, -16)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: WindowGrid.gap, alignment: .top), count: 3), spacing: WindowGrid.gap) {
                    tile("cpu", tr("Puce", "Chip"), info.chip, tr("\(info.cores) cœurs : ils travaillent en même temps.", "\(info.cores) cores working at the same time."), lesson: "processeur")
                    tile("memorychip", tr("Mémoire", "Memory"), Format.bytes(info.memory), tr("Le plan de travail : ce qui est ouvert y est posé.", "The workbench: whatever is open sits on it."), lesson: "memoire")
                    if let disk = model.disk {
                        tile("internaldrive", tr("Disque", "Disk"), Format.bytes(disk.total, decimal: true),
                             tr("\(Format.bytes(disk.available, decimal: true)) libres.", "\(Format.bytes(disk.available, decimal: true)) free."), lesson: "disque-se-remplit")
                    }
                    tile("gearshape", "macOS", info.system, tr("Garde-le à jour : les mises à jour corrigent des failles.", "Keep it updated: updates fix security holes."), lesson: "mises-a-jour")
                    tile("power", tr("Allumé depuis", "On since"), info.uptime, tr("Un redémarrage de temps en temps remet tout à zéro.", "A restart now and then resets everything."), lesson: "redemarrer")
                    if let battery = model.performance?.battery {
                        tile("battery.75percent", tr("Batterie", "Battery"), battery.health.map { tr("\($0) % de santé", "\($0)% health") } ?? "\(battery.percent) %",
                             battery.cycles.map { tr("\($0) cycles de charge.", "\($0) charge cycles.") } ?? tr("Elle s'use avec les cycles.", "It wears with cycles."), lesson: "batterie")
                    }
                }
                Text(tr("Modèle : \(info.model)", "Model: \(info.model)"))
                    .font(.system(size: 11.5)).foregroundStyle(DS.tertiaryText)
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
        }
    }

    private func tile(_ symbol: String, _ title: String, _ value: String, _ text: String, lesson: String) -> some View {
        Button {
            withAnimation(VigieMotion.standard) { page = .lesson(lesson) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VigieTile(symbol: symbol, size: 30)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.tertiaryText)
                }
                Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.6).foregroundStyle(DS.secondaryText)
                Text(value).font(.system(size: 20, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(text).font(.system(size: 12)).foregroundStyle(DS.secondaryText).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 168)
            .panelSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Ce que macOS dit de ce Mac (puce, mémoire, système, allumé depuis).
struct MacInfo {
    var chip: String
    var cores: Int
    var memory: UInt64
    var system: String
    var uptime: String
    var model: String

    static func read(demo: Bool) -> MacInfo {
        if demo {
            return MacInfo(chip: "Apple M3 Pro", cores: 12, memory: 32 * 1_073_741_824, system: "macOS 27.2", uptime: tr("9 jours", "9 days"), model: "Mac15,8")
        }
        func sysctl(_ name: String) -> String {
            var size = 0
            sysctlbyname(name, nil, &size, nil, 0)
            guard size > 0 else { return "" }
            var buffer = [CChar](repeating: 0, count: size)
            sysctlbyname(name, &buffer, &size, nil, 0)
            return String(cString: buffer)
        }
        let info = ProcessInfo.processInfo
        let version = info.operatingSystemVersion
        let hours = Int(info.systemUptime / 3600)
        return MacInfo(chip: sysctl("machdep.cpu.brand_string").isEmpty ? "Mac" : sysctl("machdep.cpu.brand_string"),
                       cores: info.activeProcessorCount,
                       memory: info.physicalMemory,
                       system: "macOS \(version.majorVersion).\(version.minorVersion)",
                       uptime: hours >= 48 ? tr("\(hours / 24) jours", "\(hours / 24) days") : tr("\(hours) heures", "\(hours) hours"),
                       model: sysctl("hw.model"))
    }
}

/// Le glossaire : les mots de Vigie et de macOS, en une phrase. La recherche filtre.
struct GlossaryPage: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?
    @State private var search = ""

    var body: some View {
        let needle = search.trimmingCharacters(in: .whitespaces)
        let terms = Glossary.visible(developer: model.isDeveloper).filter {
            needle.isEmpty || $0.term.text.localizedStandardContains(needle) || $0.definition.text.localizedStandardContains(needle)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: tr("Glossaire", "Glossary"),
                           subtitle: tr("Les mots de Vigie et de macOS, en une phrase.", "Vigie's and macOS's words, in one sentence.")) {
                    LearnBackPill(page: $page)
                }
                    .padding(.horizontal, -VigieTheme.pagePadding)
                    .padding(.bottom, -16)
                LearnSearchField(text: $search, placeholder: tr("Chercher un mot…", "Find a word…"))
                if terms.isEmpty {
                    Text(tr("Rien ne correspond à « \(needle) ».", "Nothing matches “\(needle)”.")).font(.system(size: 13)).foregroundStyle(DS.secondaryText)
                } else {
                    GlossaryList(terms: terms, page: $page)
                }
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
        }
    }
}

/// Les mots et leur définition, en une carte de lignes ; « Lire » ouvre l'explication liée.
struct GlossaryList: View {
    let terms: [GlossaryTerm]
    @Binding var page: WindowPage?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(terms.enumerated()), id: \.element.id) { index, term in
                if index > 0 { Divider().padding(.leading, 16) }
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(term.term.text).font(.system(size: 13.5, weight: .semibold)).frame(width: 190, alignment: .leading)
                    Text(term.definition.text).font(.system(size: 13)).foregroundStyle(DS.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let lesson = term.lesson {
                        Button(tr("Lire", "Read")) { withAnimation(VigieMotion.standard) { page = .lesson(lesson) } }
                            .buttonStyle(.borderless)
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .panelSurface()
    }
}

/// Retour à l'accueil de Comprendre, en pastille à droite du titre.
struct LearnBackPill: View {
    @Binding var page: WindowPage?

    var body: some View {
        Button {
            withAnimation(VigieMotion.standard) { page = .learn }
        } label: {
            Label(tr("Comprendre mon Mac", "Understand my Mac"), systemImage: "chevron.left").lineLimit(1)
        }
        .buttonStyle(HUDPillButtonStyle())
    }
}
