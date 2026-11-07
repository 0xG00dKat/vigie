# Vigie

App macOS de barre des menus qui rend lisible ce qui tourne sur le Mac : elle regroupe le millier de processus du Moniteur d'activité en quelques dizaines de lignes, explique chacune en français simple et permet de les fermer.

## Rubriques

- **Apps** : apps du Dock, chacune avec tous ses processus d'aide (helpers Chromium/Electron, services XPC dont macOS la dit « responsable »).
- **Dev & terminal** : outils lancés depuis un terminal, un éditeur ou Claude, rangés par dossier de projet (dossier de travail du processus). Un processus sans projet suit son parent de dev (les serveurs MCP suivent leur session Claude Code). Ports en écoute, durée et app de lancement affichés.
- **Arrière-plan** : utilitaires sans fenêtre (barre des menus, synchronisation, agents tiers).
- **Système** : macOS et les processus d'autres utilisateurs (root…). Repliée par défaut, jamais fermable.

## Structure

- `Sources/VigieCore` (sans AppKit, testé) :
  - `ProcessSampler.swift` : lecture par `sysctl` et `libproc` (chemin, mémoire « footprint » comme le Moniteur d'activité, % CPU, dossier de travail, arguments, ports TCP en écoute), plus `SystemMemory` et `ProcessSignals`.
  - `GroupBuilder.swift` : règles de regroupement. C'est le cœur ; chaque règle y est commentée.
  - `PathRules.swift` : classement par chemin (paquets `.app`, emplacements système ou dev).
  - `Explainer.swift` : textes intégrés (apps, outils de dev, services système) et masquage des secrets dans les arguments.
  - `ClaudeExplainer.swift` : bouton « Demander à Claude ». Appelle la commande `claude -p` installée (compte Claude Code de l'utilisateur), sans outils ni MCP. N'envoie que le nom, l'identifiant et le chemin, jamais les arguments. Réponses gardées dans `~/Library/Application Support/Vigie/explications-claude.json`.
- `Sources/Vigie` : app SwiftUI (`MenuBarExtra`), modèle (`AppModel.swift`), vues (`Views.swift`), point d'entrée et modes de vérification (`Main.swift`).
- `Support/Info.plist` : `LSUIElement` (pas d'icône dans le Dock), identifiant `io.github.0xg00dkat.vigie`.
- Logo : un œil de vigie dont la pupille est une liste triée (les processus rangés par taille). Dessiné en code par `scripts/make-icon.swift`, qui produit `Support/AppIcon.icns` (Finder, Spotlight) et `Support/MenuBarIcon.png` + `@2x` (modèle monochrome de la barre des menus). Relancer `swift scripts/make-icon.swift [aperçu.png]` après une modification, puis `./scripts/build-app.sh`.

## Commandes

```bash
swift build                    # compilation de développement
swift test                     # tests (VigieCoreTests)
./scripts/build-app.sh         # build release → build/Vigie.app (signature ad hoc)
open build/Vigie.app           # lancer l'app
```

Modes de vérification (binaire `build/Vigie.app/Contents/MacOS/Vigie` ou `.build/debug/Vigie`) :

- `--dump [--all]` : groupes en texte, avec la méthode de fermeture de chacun.
- `--render fichier.png [--lang fr|en] [--switch-lang fr|en] [--demo] [--dark] [--query texte] [--expand Titre] [--confirm Titre] [--collapse apps|dev|background] [--open-system]` : dessine le panneau dans une image, sans passer par la barre des menus. `--demo` utilise un Mac fictif (`DemoData.swift`, passé par la vraie logique de regroupement) : c'est ainsi que sont faites les captures de `docs/`. Ne jamais publier de capture du vrai Mac, elle montre des projets et des chemins personnels.
- `--debug-close Titre` : ferme un groupe avec le même code que le bouton (fermeture normale, puis forcée après 6 s).
- `--debug-ask Titre` : pose la question à Claude comme le bouton.
- `--login-item on|off|status` : ouverture au démarrage (même réglage que la case du panneau, via `SMAppService`).

## Installation et mise à jour

Pour mettre à jour une copie installée : quitter Vigie, `./scripts/build-app.sh`, remplacer `/Applications/Vigie.app` par `build/Vigie.app` (`ditto`), relancer. L'inscription au démarrage reste valable tant que le chemin et l'identifiant ne changent pas.

## Projet open source

- Licence MIT (`LICENSE`), auteur public : G00dKat. Documentation utilisateur : `README.md` (anglais) et `README.fr.md` (français), avec leurs captures (`docs/screenshot*.png`, `docs/apercu*.png`).
- Pas d'intégration continue : les machines macOS de GitHub coûtent cher en minutes. Vérifier en local (`swift test`, `./scripts/build-app.sh`).
- Les jetons des tests sont volontairement faux et marqués `FAUX`, pour ne pas déclencher la détection de secrets de GitHub.

## Mises à jour et publication

- `Updates.swift` : `Version` (comparaison numérique, « v » ignoré), lecture de `GET /repos/{dépôt}/releases/latest` (brouillons et préversions ignorés, 404 = aucune version publiée), règle « au plus une fois par jour ». Dépôt lu dans l'Info.plist (`VigieUpdateRepository`, `0xG00dKat/vigie` par défaut) pour qu'un fork pointe sur le sien.
- C'est la seule connexion réseau de Vigie : requête anonyme, User-Agent `Vigie/<version>`, rien sur le Mac. Désactivable dans le menu ⚙︎ (clé `verifierMisesAJour`). Première vérification 30 s après le lancement, puis toutes les 6 h si la dernière date de plus de 24 h.
- Interface (`UpdateViews.swift`) : menu ⚙︎ (langue, « Rechercher une mise à jour », « Vérifier chaque jour », numéro de version) et bandeau en tête de liste. Une vérification automatique qui échoue reste silencieuse ; une vérification manuelle affiche « à jour » ou l'erreur. « Ignorer cette version » masque le bandeau automatique pour cette version.
- Les notes de version sont bilingues (`**Français**` puis `**English**`) ; le bandeau n'affiche que la partie dans la langue courante (`ReleaseInfo.summary(in:)`).
- Publier : version dans `Support/Info.plist` (`CFBundleShortVersionString`, et `CFBundleVersion` +1), section `## X.Y.Z` dans `CHANGELOG.md`, commit sur `main`, puis `./scripts/release.sh X.Y.Z` (vérifie branche, propreté, version, étiquette libre, lance les tests, construit, crée `dist/Vigie-X.Y.Z.zip` et les notes) et `./scripts/release.sh X.Y.Z --publish` (étiquette `vX.Y.Z`, envoi, version GitHub avec le .zip). `dist/` est ignoré par Git.
- L'app n'est pas notarisée : le .zip téléchargé est bloqué par Gatekeeper à la première ouverture (« Ouvrir quand même » dans Réglages Système › Confidentialité et sécurité). Pour une mise à jour automatique complète (Sparkle), il faudra un compte Apple Developer.
- Vérifications : `--debug-update [--repo propriétaire/dépôt] [--pretend-version x.y.z]` ; `--render … --demo-update` pour le bandeau.

## Docker et disque

- `Disk.swift` : espace libre du disque de démarrage, mesure stricte (`volumeAvailableCapacity`, comme `df`, sans l'espace purgeable). Alerte sous 15 %, réarmée au-dessus de 17 % (`DiskAlertState`). Lu toutes les 2 minutes même panneau fermé (une seule lecture, coût nul).
- `Docker.swift` : lecture par la commande `docker` (`ps`, `stats --no-stream`, `inspect`, `system df`), toutes les 15 s seulement quand le panneau est ouvert. Trois états : absent, arrêté (le disque virtuel reste affiché : `Docker.raw` occupe de la place même Docker arrêté), en marche. Conteneurs regroupés par projet Compose (étiquettes `com.docker.compose.*`).
- Arrêt : `docker stop` (arrêt propre, puis forcé par Docker après 10 s). Nettoyage : Vigie affiche seulement les commandes (`docker builder prune`, `docker image prune -a`, `docker container prune`) avec un bouton « Copier » ; elle ne supprime rien et ne touche jamais aux volumes.
- Alerte : pourcentage libre à côté de l'œil dans la barre des menus (`MenuBarLabel`), bandeau rouge en tête du panneau, notification (`Notifier.swift`, autorisation demandée par macOS la première fois).
- Docker Desktop : sa fenêtre (« Docker Desktop.app », app du Dock) vit dans Docker.app ; la règle des apps imbriquées les range sous un seul groupe dont la fermeture quitte les deux. Après la fermeture, Docker Desktop laisse souvent un `docker-agent` qui apparaît dans « Arrière-plan ».
- Testé en vrai avec Docker Desktop 29.9 (conteneurs de test créés, lus, arrêtés par Vigie puis supprimés). OrbStack et Colima : chemins prévus, non testés.
- Vérifications : `--dump` affiche disque et Docker ; `--render … --demo [--demo-disk-low]` ; `--debug-close Titre` marche aussi pour un groupe Docker ; `--patient` attend sans jamais forcer ; `--debug-notify` envoie une notification de test.

## Langues (français et anglais)

- Chaque texte affiché est une paire : `L("français", "English")` pour les textes rangés dans des tables (`Explainer.swift`), `tr("français", "English")` dans le code. Le compilateur refuse un texte à qui il manque une langue ; pour en ajouter une, ajouter un champ à `L` (`Localization.swift`) et suivre les erreurs.
- `Localization.current` est la langue courante (protégée par un verrou : le regroupement tourne en arrière-plan). Les formats suivent (`Format.swift` : Mo/MB, virgule/point, « depuis 2 j 3 h » / « up 2d 3h »).
- Réglage dans le panneau (menu ⚙︎) : automatique (langue du système, anglais si ni français ni anglais), français ou anglais ; enregistré dans les préférences de Vigie (clé `langue`). Le panneau est reconstruit (`.id(model.language)`) et les données rechargées.
- « Demander à Claude » pose la question dans la langue courante ; les réponses anglaises sont mises en cache avec le préfixe `en|`.
- Le résumé d'un groupe de dev s'appuie sur `Explainer.DevKind` (serveur MCP, session Claude Code), jamais sur le texte affiché.
- Garde-fou : `TranslationTests` signale une traduction anglaise avec une ponctuation française (« : » précédé d'une espace, guillemets « ») ou l'inverse.
- Les messages des modes de vérification (`--dump`, `--debug-*`) restent en français : ils servent au développement. Les explications qu'ils affichent suivent le réglage de langue, comme l'app.

## Choix et garde-fous

- Fermeture en deux clics (× puis « Quitter ? »), confirmation annulée au bout de 4 s. Les apps reçoivent une fermeture normale (`NSRunningApplication.terminate`, comme ⌘Q) ; les processus sans interface reçoivent SIGTERM. « Forcer » n'apparaît qu'après 5 s sans effet.
- Jamais fermables : rubrique Système, processus d'autres utilisateurs, Finder, Dock, Centre de contrôle et Vigie elle-même.
- L'ordre des lignes est figé tant que le panneau est ouvert, pour que rien ne bouge sous le curseur ; « Actualiser » retrie.
- Actualisation toutes les 3 s seulement quand le panneau est visible ; au repos, Vigie ne consomme rien.
- Les noms d'apps viennent de macOS et suivent la langue du système, quel que soit le réglage de langue de Vigie.
- `responsibility_get_pid_responsible_for_pid` (non documentée) est chargée dynamiquement ; si elle disparaît, les services XPC restent simplement en Système.

## Limites connues

- La mémoire et le CPU des processus root ne sont pas lisibles sans droits administrateur (le Moniteur d'activité passe par un service privilégié).
