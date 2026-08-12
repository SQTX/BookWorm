import SwiftUI

/// A cover, by hash, at whatever size the caller needs.
///
/// A book with no cover is normal, and the placeholder occupies exactly the
/// same box as an image so a card does not change shape depending on whether
/// the cover has arrived.
struct CoverThumbnail: View {
    let hash: String?
    var width: CGFloat = 46
    var height: CGFloat = 69

    @Environment(AppModel.self) private var model
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "book.closed")
                    .font(.system(size: height * 0.3))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.tertiarySystemFill))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: hash) {
            guard let hash, let store = model.coverLoader() else { return }
            image = await store.thumbnail(hash: hash)
        }
    }
}
