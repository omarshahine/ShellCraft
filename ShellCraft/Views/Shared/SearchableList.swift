import SwiftUI

struct SearchableList<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let searchText: Binding<String>
    let content: (Item) -> Content

    var body: some View {
        List {
            ForEach(items) { item in
                content(item)
            }
        }
        .searchable(text: searchText, placement: .toolbar)
    }
}
