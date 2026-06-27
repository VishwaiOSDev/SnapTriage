//
//  ReviewRouter.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import UIKit

@MainActor
protocol ReviewRouter {
    func openSettings()
}

@MainActor
final class SystemReviewRouter: ReviewRouter {
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}
