import Foundation

/// Resolves bundled resources whether the module is built as an SPM target
/// (`Bundle.module`) or as the Xcode application target (`Bundle.main`).
enum AppResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }
}
