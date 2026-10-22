import AppKit

// `MyPhotoBooth --render in.jpg outDir` writes every effect applied to a still image,
// so the effects can be checked without a camera or any permission.
let arguments = CommandLine.arguments
if arguments.count == 4, arguments[1] == "--render" {
    exit(RenderTool.run(input: arguments[2], outputDirectory: arguments[3]))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
