//
//  PhotoLibraryAuthorization.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Foundation

enum PhotoLibraryAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case limited
    case authorized

    var canAccessLibrary: Bool {
        self == .authorized || self == .limited
    }
}
