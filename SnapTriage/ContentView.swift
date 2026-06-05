import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.blue)

                VStack(spacing: 8) {
                    Text("SnapTriage")
                        .font(.largeTitle.bold())

                    Text("Triage screenshots fast: keep, delete, or act on them later.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                Button {
                    // Screenshot import flow will live here.
                } label: {
                    Label("Start Triage", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Screenshots")
        }
    }
}

#Preview {
    ContentView()
}
