import AppKit

// `--export-icon <dir>` reuses the live renderer to generate the app icon, so
// the icon can never drift out of sync with what the widget actually draws.
if let idx = CommandLine.arguments.firstIndex(of: "--export-icon"),
   idx + 1 < CommandLine.arguments.count {
    IconExporter.run(into: CommandLine.arguments[idx + 1])
    exit(0)
}

if let idx = CommandLine.arguments.firstIndex(of: "--export-preview"),
   idx + 1 < CommandLine.arguments.count {
    PreviewExporter.run(to: CommandLine.arguments[idx + 1])
    exit(0)
}

// `--export-docs <dir>` renders the images the README uses, from the live
// renderer, so they can't drift from what the app actually draws.
if let idx = CommandLine.arguments.firstIndex(of: "--export-docs"),
   idx + 1 < CommandLine.arguments.count {
    DocsExporter.run(into: CommandLine.arguments[idx + 1])
    exit(0)
}

if CommandLine.arguments.contains("--test-oath") {
    exit(OathMatchTests.run() == 0 ? 0 : 1)
}

// `--demo-shift [step-seconds] [speed]` plays the corps transitions on a loop
// in a window of its own, so they can be watched without draining a battery.
// Unlike the exporters above it needs a run loop, so it never returns.
if let idx = CommandLine.arguments.firstIndex(of: "--demo-shift") {
    func argument(_ offset: Int, _ fallback: Double) -> Double {
        let i = idx + offset
        guard i < CommandLine.arguments.count,
              let v = Double(CommandLine.arguments[i]) else { return fallback }
        return v
    }
    ShiftDemo.run(step: argument(1, 4), speed: argument(2, 1))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
