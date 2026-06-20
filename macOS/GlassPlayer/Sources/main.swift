import Cocoa

if let resourcePath = Bundle.main.resourcePath {
    let icdPath = (resourcePath as NSString).appendingPathComponent("vulkan/icd.d/MoltenVK_icd.json")
    setenv("VK_ICD_FILENAMES", icdPath, 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
