//
//  OverviewRouter.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import PhotosUI
import UIKit

@MainActor
protocol OverviewRouter {
    /// Deep link to the system Settings app. Reserved for the one thing the app
    /// genuinely cannot do itself: change a denied photo permission. Everything
    /// the app *can* configure lives on its own Settings screen.
    func openSystemSettings()
    /// Reopens the system picker for a limited photo selection, so a user who
    /// granted access to a handful of screenshots can widen it without leaving.
    func presentLimitedLibraryPicker()
}

@MainActor
final class SystemOverviewRouter: OverviewRouter {

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    func presentLimitedLibraryPicker() {
        guard let presenter = UIApplication.shared.topmostViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter)
    }
}

extension UIApplication {

    /// The view controller a system sheet should hang off. PhotoKit's limited
    /// picker needs a real presenter, and SwiftUI does not hand one out.
    @MainActor
    var topmostViewController: UIViewController? {
        let root = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?
            .rootViewController
        var presenter = root
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }
        return presenter
    }
}
