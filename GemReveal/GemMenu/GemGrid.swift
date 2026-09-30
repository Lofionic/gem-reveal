import SwiftUI

struct GemGridRow: Hashable, Identifiable {
    var id: GemDefinition { gemDefinition }
    let gemDefinition: GemDefinition
    let isLocked: Bool
    
    var assetName: String {
        isLocked ? "RockReveal" : gemDefinition.assetName
    }
}

struct GemGrid: View {
    let items: [GemGridRow]
    let onSelect: (GemDefinition) -> Void
    
    init(
        items: [GemGridRow],
        onSelect: @escaping (GemDefinition) -> Void
    ) {
        self.items = items
        self.onSelect = onSelect
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(items, id: \.self) { item in
                    Button(action: {
                        onSelect(item.gemDefinition)
                    }, label: {
                        GemCell(row: item)
                            .aspectRatio(1, contentMode: .fit)
                    })
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
    
    private struct GemCell: View {
        let row: GemGridRow
        
        var body: some View {
            RoundedRectangle(cornerRadius: 12)
                .fill(.clear)
                .overlay {
                    Image(row.assetName)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(style: .init(lineWidth: 1))
                        .foregroundStyle(.foreground.opacity(0.1))
                }
            
        }
    }
}

#Preview {
    let items: [GemGridRow] = [
        .init(gemDefinition: .amazonite, isLocked: true),
        .init(gemDefinition: .amethyst, isLocked: false),
        .init(gemDefinition: .jade, isLocked: true),
        .init(gemDefinition: .opal, isLocked: false),
    ]
    
    ZStack {
        BackgroundView(level: .full)
        GemGrid(items: items) { _ in }
    }
}
