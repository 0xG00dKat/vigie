import Foundation
import XCTest
@testable import VigieCore

final class LessonsTests: FrenchTestCase {
    func testLessonsAreComplete() {
        XCTAssertEqual(Set(Lessons.all.map(\.id)).count, Lessons.all.count, "identifiants uniques")
        for lesson in Lessons.all {
            XCTAssertFalse(lesson.paragraphs.isEmpty, lesson.id)
            for text in [lesson.title, lesson.summary, lesson.takeaway] + lesson.paragraphs {
                XCTAssertFalse(text.fr.isEmpty, lesson.id)
                XCTAssertFalse(text.en.isEmpty, lesson.id)
            }
        }
        // Les liens « En savoir plus » des écrans pointent vers des explications qui existent.
        for id in ["memoire", "swap", "processus", "disque-se-remplit", "caches", "donnees-systeme", "corbeille", "batterie", "demarrage", "ports"] {
            XCTAssertNotNil(Lessons.lesson(id), id)
        }
    }

    func testQuestionsPointToExistingLessons() {
        XCTAssertEqual(Set(LessonQuestions.all.map(\.id)).count, LessonQuestions.all.count, "identifiants uniques")
        for question in LessonQuestions.all {
            XCTAssertFalse(question.title.fr.isEmpty, question.id)
            XCTAssertFalse(question.subtitle.en.isEmpty, question.id)
            XCTAssertEqual(Set(question.lessonIDs).count, question.lessonIDs.count, "pas de doublon : \(question.id)")
            for id in question.lessonIDs {
                XCTAssertNotNil(Lessons.lesson(id), "\(question.id) → \(id)")
            }
            // Assez pour un petit parcours, pas trop pour rester lisible.
            XCTAssertTrue((3...7).contains(question.lessons(developer: question.isDeveloper).count), question.id)
        }
        // Chaque explication grand public est rangée sous au moins une question.
        let covered = Set(LessonQuestions.visible(developer: false).flatMap(\.lessonIDs))
        for lesson in Lessons.visible(developer: false) {
            XCTAssertTrue(covered.contains(lesson.id), "sans question : \(lesson.id)")
        }
    }

    func testDeveloperQuestionsStayInDeveloperMode() {
        XCTAssertFalse(LessonQuestions.visible(developer: false).contains { $0.id == "dev" })
        XCTAssertTrue(LessonQuestions.visible(developer: true).contains { $0.id == "dev" })
        // Hors mode Développeur, une question ne propose jamais une explication réservée.
        for question in LessonQuestions.visible(developer: false) {
            XCTAssertFalse(question.lessons(developer: false).contains(where: \.isDeveloper), question.id)
        }
    }

    func testDeveloperLessonsStayInDeveloperMode() {
        XCTAssertFalse(Lessons.visible(developer: false).contains { $0.id == "ports" })
        XCTAssertTrue(Lessons.visible(developer: true).contains { $0.id == "ports" })
    }
}
