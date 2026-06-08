//
//  ContentView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = TriageComposition.make(router: SystemTriageRouter())

    var body: some View {
        TriageView(viewModel: viewModel)
    }
}

#Preview {
    ContentView()
}
