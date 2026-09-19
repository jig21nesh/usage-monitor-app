import Foundation

enum FixtureError: Error {
    case missing(String)
}

/// Loads `Fixtures/<subdirectory>/<name>.json` from the test bundle.
enum Fixtures {
    static func data(_ name: String, subdirectory: String? = nil) throws -> Data {
        let directory = subdirectory.map { "Fixtures/\($0)" } ?? "Fixtures"
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: directory) else {
            throw FixtureError.missing("\(directory)/\(name).json")
        }
        return try Data(contentsOf: url)
    }
}
