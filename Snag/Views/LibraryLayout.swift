import SwiftUI

/// How the library is laid out, as in Moodboard: even tiles or Pinterest-style
/// columns, at one of three sizes. Stored in user defaults.
enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid, masonry

    static let key = "libraryLayout"

    var id: Self { self }

    var title: String {
        switch self {
        case .grid: "Grid"
        case .masonry: "Masonry"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: "square.grid.3x3"
        case .masonry: "rectangle.3.group"
        }
    }
}

enum LibraryDensity: String, CaseIterable, Identifiable {
    case compact, regular, spacious

    static let key = "libraryDensity"

    var id: Self { self }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .regular: "Regular"
        case .spacious: "Spacious"
        }
    }

    /// The narrowest a tile gets. On iPhone: four, three or two across.
    var minimumWidth: CGFloat {
        #if os(iOS)
        switch self {
        case .compact: 80
        case .regular: 108
        case .spacious: 160
        }
        #else
        switch self {
        case .compact: 120
        case .regular: 160
        case .spacious: 240
        }
        #endif
    }

    var spacing: CGFloat {
        switch self {
        case .compact: 3
        case .regular: 6
        case .spacious: 12
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact: 8
        case .regular: 14
        case .spacious: 20
        }
    }
}

enum LibraryLayoutKey {
    static let showsInfo = "libraryShowsInfo"
}

/// The toolbar menu that changes the library's layout.
struct LibraryLayoutMenu: View {
    @AppStorage(LibraryLayout.key) private var layout = LibraryLayout.masonry
    @AppStorage(LibraryDensity.key) private var density = LibraryDensity.regular
    @AppStorage(LibraryLayoutKey.showsInfo) private var showsInfo = true

    var body: some View {
        Menu {
            Picker("Layout", selection: animated($layout)) {
                ForEach(LibraryLayout.allCases) { layout in
                    Label(layout.title, systemImage: layout.systemImage).tag(layout)
                }
            }
            .pickerStyle(.inline)

            Section("Size") {
                Picker("Size", selection: animated($density)) {
                    ForEach(LibraryDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Toggle("Show Info", systemImage: "text.below.photo", isOn: animated($showsInfo))
        } label: {
            Label("Layout", systemImage: layout.systemImage)
        }
        #if os(iOS)
        // Stays open, so you can try layouts and sizes and see them change behind it.
        .menuActionDismissBehavior(.disabled)
        #endif
    }

    private func animated<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        binding.animation(.snappy)
    }
}
