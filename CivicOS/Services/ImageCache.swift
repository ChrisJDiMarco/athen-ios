import SwiftUI
import UIKit

/// Disk + memory cache for officials photos. SwiftUI's AsyncImage doesn't
/// cache to disk, so scrolling the directory of 536 federal legislators
/// re-fetches every photo every scroll. This wraps a shared URLSession that
/// holds 25 MB memory + 100 MB disk for image traffic.
///
/// Use `CachedAsyncImage(url:)` exactly like `AsyncImage` — same API,
/// drop-in replacement.
enum ImageCache {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 25 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024,
            diskPath: "athen-image-cache"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var phase: Phase = .loading

    enum Phase {
        case loading
        case success(UIImage)
        case failure
    }

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            switch phase {
            case .loading: placeholder()
            case .failure: placeholder()
            case .success(let image): content(Image(uiImage: image))
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            phase = .failure
            return
        }
        do {
            let (data, _) = try await ImageCache.session.data(from: url)
            if let img = UIImage(data: data) {
                phase = .success(img)
            } else {
                phase = .failure
            }
        } catch {
            phase = .failure
        }
    }
}
