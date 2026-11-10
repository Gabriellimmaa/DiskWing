import XCTest
@testable import CacheSSDCore

final class LocalizationTests: XCTestCase {
    override func tearDown() { L10n.preference = "system" }
    func testCatalogLoadsAndKeepsInterpolationArgumentsVerbatim() {
        XCTAssertNotNil(L10n.resourceBundle)
        XCTAssertGreaterThan(L10n.english.count,400)
        for (key,value) in L10n.english {
            XCTAssertEqual(key.components(separatedBy:"%@").count,value.components(separatedBy:"%@").count,key)
            XCTAssertFalse(value.isEmpty,key)
        }
        L10n.preference = "en"
        let name = "Nome — Ajustes % arquivo.txt"
        XCTAssertEqual(L10n.text("Retomar análise de \(name)"),"Resume scan of " + name)
        L10n.preference = "pt-BR"
        XCTAssertEqual(L10n.text("Retomar análise de \(name)"),"Retomar análise de " + name)
    }
    func testErrorsAndHistoricalMessagesUseChosenLanguage() {
        L10n.preference = "en"
        XCTAssertEqual(CacheSSDError.message("O item está em uso.").localizedDescription,"The item is in use.")
        XCTAssertEqual(L10n.message("npm migrado"),"npm migrated")
        XCTAssertEqual(L10n.message("Origem preservada"),"Original preserved")
        XCTAssertEqual(L10n.message("A validação de Nome %@ falhou. A origem foi preservada; código 4."),"Nome %@ validation failed. The original was preserved; exit code 4.")
        L10n.preference = "pt-BR"
        XCTAssertEqual(L10n.text("Nome"),"Nome")
    }
    func testUnknownLanguageFallsBackAndBytesUseSelectedLocale() {
        L10n.preference = "en"; XCTAssertEqual(L10n.locale.identifier,"en_US")
        XCTAssertFalse(ByteText.format(1500).isEmpty)
        L10n.preference = "pt-BR"; XCTAssertEqual(L10n.locale.identifier,"pt_BR")
        L10n.preference = "unsupported"; XCTAssertEqual(L10n.preference,"system")
    }
}
