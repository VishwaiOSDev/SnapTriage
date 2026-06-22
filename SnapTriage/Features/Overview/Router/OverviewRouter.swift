//
//  OverviewRouter.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import UIKit

@MainActor
protocol OverviewRouter {
    func openSettings()
}

@MainActor
final class SystemOverviewRouter: OverviewRouter {
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}
