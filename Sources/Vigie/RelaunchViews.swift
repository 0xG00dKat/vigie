import SwiftUI
import VigieCore

/// Le bouton de fermeture d'un groupe : le × habituel, ou, si macOS relance ce programme dès qu'il s'arrête,
/// un menu qui propose ce qui marche vraiment (arrêter le service).
struct GroupCloseControl: View {
    @Environment(AppModel.self) private var model
    let group: ProcessGroup

    var body: some View {
        if let job = model.relauncher(for: group) {
            KeepAliveMenu(job: job, group: group)
        } else {
            CloseControl(key: group.id, verb: group.category == .dev ? tr("Arrêter", "Stop") : tr("Quitter", "Quit")) {
                model.confirmClose(group.id, methods: [group.close])
            }
        }
    }
}

/// Menu d'arrêt d'un service qui revient tout seul. Choisir dans le menu vaut confirmation.
struct KeepAliveMenu: View {
    @Environment(AppModel.self) private var model
    let job: KeepAliveJob
    var group: ProcessGroup?

    var body: some View {
        if model.closeState("launchd:" + job.label) != nil {
            ProgressView().controlSize(.small).frame(width: 22)
        } else {
            Menu {
                if job.isUser {
                    Button(tr("Arrêter jusqu'au prochain démarrage", "Stop until next startup")) { model.stopKeepAlive(job, forGood: false) }
                    Button(tr("Arrêter et ne plus lancer au démarrage", "Stop and don't start at login")) { model.stopKeepAlive(job, forGood: true) }
                    Divider()
                    Text(tr("Réversible : « Ce qui démarre avec ton Mac » (page Vitesse) le relance.",
                            "Reversible: “What starts with your Mac” (Speed page) turns it back on."))
                } else {
                    Button(tr("Ouvrir les réglages d'ouverture…", "Open login settings…")) { model.openLoginItemsSettings() }
                    if let group, group.close.isAllowed, !group.isProtected {
                        Button(tr("Quitter quand même (il reviendra)", "Quit anyway (it will come back)")) {
                            model.confirmClose(group.id, methods: [group.close])
                        }
                    }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.secondary)
            .fixedSize()
            .help(tr("macOS le relance dès qu'il s'arrête : choisir comment l'arrêter", "macOS restarts it as soon as it stops: choose how to stop it"))
        }
    }
}

/// « ↻ Relancé par macOS dès qu'il s'arrête » : sous le nom, pour qu'on le sache avant de cliquer.
struct RelaunchLine: View {
    let job: KeepAliveJob

    var body: some View {
        Label(tr("Relancé par macOS dès qu'il s'arrête (service « \(job.shortName) »)",
                 "Restarted by macOS as soon as it stops (service “\(job.shortName)”)"),
              systemImage: "arrow.clockwise")
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(job.plistPath)
    }
}

/// Après une fermeture qui n'a pas tenu : le dire clairement, et proposer l'arrêt qui marche.
struct RelaunchBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let notice = model.relaunchNotice {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.review)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("\(notice.title) a été relancé par macOS", "\(notice.title) was restarted by macOS"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(notice.job.map { job in
                        tr("La fermeture a marché, mais le service « \(job.shortName) » le relance \(job.throttle) s après chaque arrêt. Pour qu'il reste fermé, arrête le service.",
                           "Closing worked, but the “\(job.shortName)” service restarts it \(job.throttle) s after each stop. To keep it closed, stop the service.")
                    } ?? tr("La fermeture a marché, mais un autre programme l'a relancé juste après.",
                            "Closing worked, but another program restarted it right after."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let job = notice.job {
                        HStack(spacing: 8) {
                            if job.isUser {
                                Button(tr("Arrêter le service", "Stop the service")) { model.stopKeepAlive(job, forGood: false) }
                                    .buttonStyle(.borderedProminent).tint(VigieTheme.accent)
                                Button(tr("Et ne plus le lancer au démarrage", "And don't start it at login")) { model.stopKeepAlive(job, forGood: true) }
                                    .buttonStyle(.bordered)
                            } else {
                                Button(tr("Ouvrir les réglages d'ouverture…", "Open login settings…")) { model.openLoginItemsSettings() }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .controlSize(.small)
                        .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
                Button { model.dismissRelaunchNotice() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help(tr("Masquer", "Hide"))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.review.opacity(0.5), lineWidth: 0.5))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
