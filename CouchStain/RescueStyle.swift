import SwiftUI

enum Palette {
    static let paper = Color(red: 246/255, green: 244/255, blue: 238/255)
    static let surface = Color(red: 255/255, green: 254/255, blue: 250/255)
    static let ink = Color(red: 31/255, green: 35/255, blue: 38/255)
    static let muted = Color(red: 81/255, green: 96/255, blue: 106/255)
    static let line = Color(red: 214/255, green: 225/255, blue: 235/255)
    static let accent = Color(red: 46/255, green: 111/255, blue: 168/255)
    static let accentText = Color(red: 36/255, green: 93/255, blue: 143/255)
    static let tint = Color(red: 229/255, green: 239/255, blue: 249/255)
    static let caution = Color(red: 241/255, green: 238/255, blue: 228/255)
}

struct ChoiceGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let count: Int
    let compactCount: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        let columns = typeSize.isAccessibilitySize ? compactCount : count
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            content()
        }
    }
}

extension View {
    func rescuePanel(_ fill: Color = Palette.surface) -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.line) }
    }
}

func selectionButton<Label: View>(id: String, selected: Bool, enabled: Bool = true,
                                  action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
    Button(action: action) {
        label()
            .padding(.horizontal, 7)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .foregroundStyle(selected ? Color.white : (enabled ? Palette.ink : Palette.muted))
            .background(selected ? Palette.accent : (enabled ? Palette.surface : Palette.paper),
                        in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? Palette.accent : Palette.line)
            }
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier(id)
}

func actionButton(_ key: String, id: String, primary: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(L.t(key)).font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(primary ? Color.white : Palette.ink)
            .background(primary ? Palette.accent : Palette.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(primary ? Palette.accent : Palette.line) }
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
}

func quietButton(_ key: String, id: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(L.t(key)).font(.subheadline.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(Palette.accentText)
    .accessibilityIdentifier(id)
}

func rowButton(_ key: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack {
            Text(L.t(key)).font(.subheadline.weight(.semibold))
            Spacer()
            Image(systemName: icon).font(.caption.weight(.semibold)).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(Palette.accentText)
    .accessibilityIdentifier(id)
}
