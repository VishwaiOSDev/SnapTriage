//
//  SettingsRouter.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import PhotosUI
import UIKit

@MainActor
protocol SettingsRouter {
    func openSystemSettings()
    func presentLimitedLibraryPicker()
}

@MainActor
final class SystemSettingsRouter: SettingsRouter {

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
