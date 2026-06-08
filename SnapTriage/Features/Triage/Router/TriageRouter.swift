//
//  TriageRouter.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import UIKit

@MainActor
protocol TriageRouter {
    func openSettings()
}

@MainActor
final class SystemTriageRouter: TriageRouter {
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}
