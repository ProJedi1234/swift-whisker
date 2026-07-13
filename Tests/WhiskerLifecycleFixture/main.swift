import Foundation
import Whisker

let argument = CommandLine.arguments.dropFirst().first
if argument == "double-teardown" {
    do {
        let backend = ANSIBackend()
        try backend.setup()
        try backend.teardown()
        try backend.teardown()
        FileHandle.standardOutput.write(Data("double-teardown-complete".utf8))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("fixture failed: \(error)\n".utf8))
        exit(1)
    }
}

let mode: RenderMode = argument == "inline" ? .inline : .fullscreen
let app: Application
if argument == "mock" {
    app = Application(mode: mode, backend: TestBackend()) { Text("lifecycle-ready") }
} else {
    app = Application(mode: mode) { Text("lifecycle-ready") }
}

do {
    try app.run()
} catch {
    FileHandle.standardError.write(Data("fixture failed: \(error)\n".utf8))
    exit(1)
}
