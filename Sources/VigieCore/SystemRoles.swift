import Foundation

/// Les services de macOS rangés par rôle : quelques familles qu'on ouvre si on veut le détail,
/// plutôt que des centaines de noms obscurs. Le rangement se fait par mots-clés dans le nom du service,
/// son identifiant et son chemin ; ce qui n'est reconnu nulle part va dans « Autres ».
public enum SystemRole: String, CaseIterable, Sendable, Identifiable {
    case virtualMachines, interface, search, intelligence, cloud, communication, network, security, media, updates, appleApps, core, other

    public var id: String { rawValue }

    public var title: L {
        switch self {
        case .virtualMachines: return L("Machines virtuelles", "Virtual machines")
        case .interface: return L("Affichage et fenêtres", "Display and windows")
        case .search: return L("Recherche et aperçus", "Search and previews")
        case .intelligence: return L("Siri et Apple Intelligence", "Siri and Apple Intelligence")
        case .cloud: return L("iCloud et comptes", "iCloud and accounts")
        case .communication: return L("Messages, appels et contacts", "Messages, calls and contacts")
        case .network: return L("Réseau, AirDrop et appareils", "Network, AirDrop and devices")
        case .security: return L("Sécurité et confidentialité", "Security and privacy")
        case .media: return L("Photos, son et vidéo", "Photos, sound and video")
        case .updates: return L("Mises à jour et App Store", "Updates and App Store")
        case .appleApps: return L("Apps et widgets d'Apple", "Apple apps and widgets")
        case .core: return L("Cœur de macOS", "macOS core")
        case .other: return L("Autres services", "Other services")
        }
    }

    /// Ce que fait la famille, en une phrase.
    public var explanation: L {
        switch self {
        case .virtualMachines: return L("Le moteur de virtualisation de macOS fait tourner Docker et les autres machines virtuelles : souvent le plus gros en mémoire.",
                                        "macOS's virtualization engine runs Docker and other virtual machines: often the biggest in memory.")
        case .interface: return L("Dessine l'écran : fenêtres, Dock, barre des menus, Centre de contrôle, fonds d'écran.",
                                  "Draws the screen: windows, Dock, menu bar, Control Center, wallpapers.")
        case .search: return L("Spotlight indexe tes fichiers et prépare les aperçus et les miniatures.",
                               "Spotlight indexes your files and prepares previews and thumbnails.")
        case .intelligence: return L("Siri, la dictée, les suggestions et Apple Intelligence, souvent même sans que tu t'en serves.",
                                     "Siri, dictation, suggestions and Apple Intelligence, often even when you don't use them.")
        case .cloud: return L("Synchronise iCloud Drive, les photos et les réglages, et garde tes comptes connectés.",
                              "Syncs iCloud Drive, photos and settings, and keeps your accounts signed in.")
        case .communication: return L("Messages, FaceTime, les appels et les contacts, prêts à recevoir.",
                                      "Messages, FaceTime, calls and contacts, ready to receive.")
        case .network: return L("Wi-Fi, téléchargements en arrière-plan, AirDrop, AirPlay, Bluetooth et Localiser.",
                                "Wi-Fi, background downloads, AirDrop, AirPlay, Bluetooth and Find My.")
        case .security: return L("Vérifie les apps et les certificats, protège le trousseau et les autorisations.",
                                 "Checks apps and certificates, protects the keychain and permissions.")
        case .media: return L("Le son, la vidéo, l'analyse des photos et la musique.",
                              "Sound, video, photo analysis and music.")
        case .updates: return L("Cherche les mises à jour de macOS et des apps, et télécharge leurs ressources.",
                                "Looks for macOS and app updates, and downloads their resources.")
        case .appleApps: return L("Les apps intégrées d'Apple et leurs widgets, gardés en veille pour s'ouvrir vite.",
                                  "Apple's built-in apps and their widgets, kept ready to open quickly.")
        case .core: return L("Les rouages de base : réglages, notifications, presse-papiers, journaux.",
                             "The basic machinery: settings, notifications, clipboard, logs.")
        case .other: return L("Les services que Vigie ne sait pas encore ranger.", "Services Vigie can't sort yet.")
        }
    }

    public var symbol: String {
        switch self {
        case .virtualMachines: return "shippingbox"
        case .interface: return "macwindow"
        case .search: return "magnifyingglass"
        case .intelligence: return "sparkles"
        case .cloud: return "icloud"
        case .communication: return "message"
        case .network: return "wifi"
        case .security: return "lock.shield"
        case .media: return "photo"
        case .updates: return "arrow.down.circle"
        case .appleApps: return "square.grid.2x2"
        case .core: return "gearshape.2"
        case .other: return "ellipsis.circle"
        }
    }

    /// Mots-clés (en minuscules), cherchés dans le nom, l'identifiant et le chemin du service.
    /// L'ordre des familles compte : la première qui reconnaît le service l'emporte.
    static let keywords: [(SystemRole, [String])] = [
        (.virtualMachines, ["virtual machine", "virtualization", "virtualmachine"]),
        (.intelligence, ["mlhost", "aned", "anestorage", "aneuserd", "modelmanager", "modelcatalog", "contextservice", "textcontext", "textcomposer", "ospredictiond", "siri", "assistant", "intelligence", "knowledge", "generativeexperiences", "imageplayground", "corespeech",
                         "synthesizer", "ausp", "tts", "translation", "naturallanguage", "textunderstanding", "voicebanking",
                         "suggest", "duetexpert", "biome", "contextstore", "appprediction", "privatecloudcompute", "ciphermld",
                         "intelligentrouting", "speech", "dictation", "proactive", "peopled", "inferenc", "embeddedspeech"]),
        (.search, ["spotlight", "parsecd", "mds", "mdworker", "mdbulkimport", "hybridsearch", "quicklook", "thumbnail", "qlpreview",
                   "media-indexer", "managedcorespotlight", "corespotlight", "searchd"]),
        (.security, ["subscriber", "managedsettings", "managedconfiguration", "managedpreferences", "remotemanagement", "deviceconfiguration", "classroom", "familycontrols", "assessment", "activation", "authd", "securityd", "keybag", "applekeystore", "gsscred", "opendirectory", "ctkd", "ctkahp", "seserviced", "seputil", "frauddefense", "devicecheck", "dprivacy", "webprivacy", "codesigning", "taskgated", "socketfilterfw", "online-auth", "logind", "misagent", "appsso", "eligibility", "adid", "cryptexd", "moonlock", "swcd", "mdremote", "ssh-agent", "fairplay", "trustd", "secd", "secinit", "tccd", "xprotect", "syspolicy", "coreauth", "filevault", "transparency",
                     "trustedpeers", "keychain", "passwordbreach", "authenticationservices", "single sign-on",
                     "cdpd", "escrow", "adprivacy", "pkd", "amfid", "securityagent", "screentime", "screen time", "familycircle",
                     "studentd", "dmd", "usagetracking", "sandbox", "endpointsecurity", "biometrickit", "launchservices.trust",
                     "communicationtrust", "coreautha", "credential"]),
        (.updates, ["asset", "installd", "installcoordination", "updater", "betaenroll", "nrd", "sucore", "uarp", "accessoryupdater", "eaupdater", "migration", "softwareupdate", "appstore", "storekit", "amsaccounts", "amsengagement", "amsondevice", "setstoreupdate",
                    "managedappdistribution", "jetpackasset", "axassets", "mobileasset", "triald", "installer", "commerce",
                    "mobiledeviceupdater"]),
        (.cloud, ["dataaccess", "cksharing", "protectedcloud", "fpck", "backupd", "bird", "cloudd", "fileprovider", "clouddocs", "cloudphoto", "syncdefaults", "icloud", "akd", "accountsd",
                  "appleaccount", "replicator", "cloudkit", "syncagent", "sync helper", "synchelper", "cmfsync", "mapssync",
                  "postersync", "findmydevice", "fmfd"]),
        (.communication, ["sociallayer", "businessservices", "menotification", "followup", "imagent", "imdpersistence", "identityservices", "callservices", "callhistory", "facetime", "avconference",
                          "messages", "mobilesms", "contacts", "peopleview", "statuskit", "commcenter", "maild", "telephony",
                          "imtransfer", "imautomatic", "imklaunch"]),
        (.network, ["btle", "airport", "nfc", "usbmux", "coredevice", "companion", "neagent", "nehelper", "nesession", "wirelessradio", "networkserviceproxy", "nsurlsession", "rapportd", "sharingd", "airdrop", "airplay", "universal control",
                    "continuity", "wi-fi", "wifi", "bluetooth", "remotepairing", "audioaccessory", "configd", "mdnsresponder",
                    "apsd", "findmy", "searchparty", "corelocation", "locationd", "routined", "geod", "netbios", "network",
                    "sidecar", "nearby", "wirelessproxd"]),
        (.media, ["icdd", "ampdevice", "podcast", "mtl", "systemsound", "colorsync", "corebrightness", "coreaudio", "audio", "vtencoder", "vtdecoder", "replayd", "photolibrary", "photoanalysis", "mediaanalysis",
                  "photos", "amplibrary", "ampartwork", "ampdevices", "itunescloud", "mediaremote", "mtlcompiler", "cgpdf", "imageconversion", "heard",
                  "powerchime", "podcasts", "voicememos", "music", "screencapture", "screenshot", "camera", "videoconference",
                  "graphics", "metal"]),
        (.interface, ["fontworker", "viewbridge", "characterpicker", "hidd", "windowserver", "windowmanager", "systemuiserver", "control centre", "control center",
                      "controlcenter", "notification centre", "notification center", "notificationcenter", "loginwindow",
                      "menubar", "textinput", "cursorui", "uikitsystem", "wallpaper", "poster", "widgetrenderer",
                      "springboard", "viewservice", "uiservice", "uiserver", "inputui", "pressandhold", "universalaccess",
                      "accessibility", "themewidget", "fontd", "coreservicesui", "open and save panel", "sharesheet",
                      "emoji", "inputmethod", "keyboard", "trackpad", "mouse", "desktop", "chronod", "applespell",
                      "nsattributedstring", "screensaver", "aerial", "menuextra", "batteries"]),
        (.appleApps, ["homed", "homeenergy", "home widget", "homewidget", "mobiletimer", "gamecontroller", "helpd", "feedbackd", "prefpane", "simlaunch", "calendar", "mobilecal", "calaccess", "reminders", "remindd", "notes", "weather", "stocks", "news", "home",
                      "health", "journal", "clock", "tips", "maps", "shortcuts", "safari", "mobilesafari", "financed", "passd",
                      "gamed", "gamepolicy", "books", "intents", "extension", "widget", "linkd", "print center", "printtool",
                      "liveactivities", "stickers", "freeform", "preview", "facetime", "wallet", "fitness", "translate",
                      "linkednotes", "categoriesservice", "promotedcontent"]),
        (.core, ["apfs", "fskit", "diskunmount", "diskmanagement", "storagekit", "deleted", "dirhelper", "filecoordination", "revisiond", "autofs", "automount", "hdieject", "fpassetmanager", "containermanager", "scopedbookmark", "progressd", "mdwrite", "containermetadata", "remoted", "runningboard", "dasd", "coreduet", "kernel", "corekdld", "sysextd", "smd", "launchservicesd", "timed", "tzd", "countryd", "localization", "watchdog", "sysmond", "systemstats", "systemstatus", "diagnosticd", "sysdiagnose", "crashreporter", "submitdiag", "microstackshot", "coresymbolication", "rtcreporting", "telemetry", "metrickit", "perfpower", "powerexperience", "peakpower", "powerui", "liquiddetection", "aslmanager", "carrylog", "reportsystemmemory", "mmaintenance", "oahd", "usermanager", "writeconfig", "appleevents", "griddata", "ecosystem", "recentsd", "pbs", "corerepair", "mobilerepair", "iomfb", "cvmserver", "driverkit", "userhiddrivers", "ifdreader", "streamingunzip", "fpsd", "datadetectors", "automationmode", "launchd", "kernel_task", "cfprefsd", "distnoted", "lsd", "usereventagent", "usernoted", "usernotifications",
                 "pboard", "diskimages", "iconservices", "sharedfilelist", "useractivity", "coreservicesd", "logd", "notifyd",
                 "analytics", "diagnostics", "backgroundtaskmanagement", "xpc", "timestamp", "donotdisturb", "featureaccess",
                 "cmextensionbroker", "milod", "sbd", "guidedbrowsing", "agentstore", "talagent", "powerd", "thermal",
                 "loginitems", "backgroundshortcut", "virtual machine", "virtualization", "diskarbitration", "fseventsd",
                 "spindump", "reportcrash", "symptomsd", "trialarchiving", "contextual", "inputanalytics", "parsecd",
                 "nsurlstoraged", "secinit"]),
    ]

    /// La famille d'un service de macOS.
    public static func role(for group: ProcessGroup) -> SystemRole {
        role(name: group.title, bundleID: group.bundleID, path: group.executablePath ?? group.bundlePath)
    }

    public static func role(name: String, bundleID: String? = nil, path: String? = nil) -> SystemRole {
        let haystack = [name, bundleID ?? "", path.map { ($0 as NSString).lastPathComponent } ?? ""]
            .joined(separator: " ").lowercased()
        if name == "Dock" { return .interface }
        for (role, words) in keywords where words.contains(where: { haystack.contains($0) }) {
            return role
        }
        return .other
    }
}

/// Une famille de services, avec ce qu'elle pèse.
public struct SystemRoleGroup: Identifiable, Sendable {
    public var role: SystemRole
    /// Du plus gros au plus petit.
    public var groups: [ProcessGroup]
    public var id: String { role.rawValue }
    public var memory: UInt64 { groups.reduce(0) { $0 + $1.memory } }
    public var processCount: Int { groups.reduce(0) { $0 + $1.processes.count } }

    /// Les services rangés par famille ; les familles de la plus lourde à la plus légère, « Autres » toujours à la fin.
    public static func make(_ groups: [ProcessGroup]) -> [SystemRoleGroup] {
        Dictionary(grouping: groups, by: SystemRole.role(for:))
            .map { SystemRoleGroup(role: $0.key, groups: $0.value.sorted { $0.memory > $1.memory }) }
            .sorted {
                if ($0.role == .other) != ($1.role == .other) { return $1.role == .other }
                return $0.memory > $1.memory
            }
    }
}
