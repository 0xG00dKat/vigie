import ServiceManagement

/// Ouverture de Vigie à l'ouverture de session, via le mécanisme officiel de macOS
/// (visible et désactivable dans Réglages Système › Général › Ouverture).
@MainActor
enum LoginItem {
    enum State: Equatable {
        case enabled
        case disabled
        /// macOS attend ton accord dans Réglages Système.
        case needsApproval
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .needsApproval
        default: return .disabled
        }
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
