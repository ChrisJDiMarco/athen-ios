import SwiftUI

/// Full bio + contact + socials for one elected official. Lets the user
/// bookmark them, call/email an office directly, jump to any social
/// account, open Wikipedia / Ballotpedia / OpenSecrets, and (where the
/// data is available) see the votes they cast and the user's own filings
/// directed at this official.
struct OfficialDetailView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let official: DirectoryOfficial

    @State private var presentedURL: SafariURL?

    private var isBookmarked: Bool {
        store.isOfficialBookmarked(official.id)
    }

    private var filingsForThisOfficial: [CivicOSStore.FilingHistoryEntry] {
        let target = official.name.lowercased()
        return store.filingHistory.filter { entry in
            entry.receipt.officialName.lowercased().contains(target)
                || target.contains(entry.receipt.officialName.lowercased())
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        hero
                        if let bio = official.bio, !bio.isEmpty {
                            bioCard(bio)
                        }
                        contactCard
                        if !official.offices.isEmpty {
                            officesCard
                        }
                        if official.socials.any {
                            socialsCard
                        }
                        externalLinksCard
                        if !filingsForThisOfficial.isEmpty {
                            yourFilingsCard
                        }
                        actionRow
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.selection()
                        store.toggleBookmarkOfficial(official.id)
                    } label: {
                        Image(systemName: isBookmarked ? "star.fill" : "star")
                            .foregroundStyle(isBookmarked ? CivicTheme.amber : CivicTheme.cyan)
                    }
                }
            }
            .sheet(item: $presentedURL) { wrapper in
                SafariSheet(url: wrapper.url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Cards

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                avatar
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 5) {
                    Text(official.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(official.role)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                    HStack(spacing: 6) {
                        if let party = official.party {
                            Text(party)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(official.partyTint, in: Capsule())
                        }
                        Text(official.displayDistrict)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CivicTheme.violet)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(CivicTheme.violet.opacity(0.10), in: Capsule())
                    }
                }
                Spacer()
            }
            if let start = official.termStartISO, let end = official.termEndISO {
                Text("Term: \(start.prefix(10)) → \(end.prefix(10))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            HStack {
                ReadAloudButton(text: { officialReadAloudScript() }, label: "Read profile")
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private func officialReadAloudScript() -> String {
        var parts: [String] = ["\(official.name), \(official.role)."]
        if let party = official.party {
            parts.append("\(party) party.")
        }
        if let bio = official.bio, !bio.isEmpty {
            parts.append(bio)
        }
        if !official.jurisdiction.isEmpty {
            parts.append("Jurisdiction: \(official.jurisdiction).")
        }
        return parts.joined(separator: " ")
    }

    private var avatar: some View {
        Group {
            if let urlString = official.photoURL, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholderAvatar
                }
            } else {
                placeholderAvatar
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(official.partyTint.opacity(0.5), lineWidth: 2))
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(official.partyTint.opacity(0.18))
            .overlay {
                Text(initials)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(official.partyTint)
            }
    }

    private var initials: String {
        let parts = official.name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }

    private func bioCard(_ bio: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("BIO", systemImage: "person.fill", tint: CivicTheme.violet)
            Text(bio)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.violet.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("CONTACT", systemImage: "person.text.rectangle.fill", tint: CivicTheme.cyan)
            if let primary = official.offices.first?.phone, let url = phoneURL(primary) {
                Link(destination: url) {
                    contactRow(label: "Call", value: primary, systemImage: "phone.fill", tint: CivicTheme.green)
                }
            }
            if let websiteString = official.websites.first, let url = URL(string: websiteString) {
                Button {
                    Haptics.selection()
                    presentedURL = SafariURL(url: url)
                } label: {
                    contactRow(label: "Official website", value: websiteString, systemImage: "globe.americas.fill", tint: CivicTheme.cyan)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private var officesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("OFFICES", systemImage: "building.2.fill", tint: CivicTheme.amber)
            ForEach(official.offices) { office in
                officeRow(office)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.amber.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func officeRow(_ office: DirectoryOfficial.Office) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(office.label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            if let address = office.address {
                Text(address)
                    .font(.system(size: 11))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if let phone = office.phone, let url = phoneURL(phone) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(phone)
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(CivicTheme.green)
                    }
                }
                if let address = office.address,
                   let mapsURL = URL(string: "https://maps.apple.com/?q=\(address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                    Link(destination: mapsURL) {
                        HStack(spacing: 4) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Maps")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(CivicTheme.cyan)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    private var socialsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SOCIAL", systemImage: "network", tint: CivicTheme.violet)
            FlowLayout(spacing: 6) {
                if let h = official.socials.twitter { socialChip("X", handle: h, url: "https://x.com/\(h)", tint: CivicTheme.ink) }
                if let h = official.socials.facebook { socialChip("Facebook", handle: h, url: "https://facebook.com/\(h)", tint: Color(red: 0.10, green: 0.36, blue: 0.78)) }
                if let h = official.socials.instagram { socialChip("Instagram", handle: h, url: "https://instagram.com/\(h)", tint: Color(red: 0.86, green: 0.21, blue: 0.50)) }
                if let h = official.socials.youtube { socialChip("YouTube", handle: h, url: "https://youtube.com/@\(h)", tint: Color(red: 0.85, green: 0.20, blue: 0.20)) }
                if let h = official.socials.linkedin { socialChip("LinkedIn", handle: h, url: "https://linkedin.com/in/\(h)", tint: Color(red: 0.05, green: 0.40, blue: 0.65)) }
                if let h = official.socials.tiktok { socialChip("TikTok", handle: h, url: "https://tiktok.com/@\(h)", tint: CivicTheme.ink) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.violet.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func socialChip(_ label: String, handle: String, url: String, tint: Color) -> some View {
        Button {
            Haptics.selection()
            if let resolved = URL(string: url) { presentedURL = SafariURL(url: resolved) }
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(tint, in: Capsule())
                Text("@\(handle)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.20), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var externalLinksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("DEEPER", systemImage: "link", tint: CivicTheme.cyan)
            VStack(spacing: 6) {
                if let url = official.wikipediaURL { linkRow("Wikipedia", url: url, systemImage: "w.circle.fill") }
                if let url = official.ballotpediaURL { linkRow("Ballotpedia", url: url, systemImage: "b.circle.fill") }
                if let url = official.openSecretsURL { linkRow("OpenSecrets (campaign finance)", url: url, systemImage: "dollarsign.circle.fill") }
                if let bioguide = official.externalIDs.bioguide,
                   let url = URL(string: "https://bioguide.congress.gov/search/bio/\(bioguide)") {
                    linkRow("Bioguide profile", url: url, systemImage: "person.crop.circle.badge.questionmark.fill")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.cyan.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func linkRow(_ label: String, url: URL, systemImage: String) -> some View {
        Button {
            Haptics.selection()
            presentedURL = SafariURL(url: url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            .padding(8)
            .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var yourFilingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("YOUR FILINGS WITH \(official.name.uppercased())", systemImage: "envelope.fill", tint: CivicTheme.green)
            ForEach(filingsForThisOfficial.prefix(5)) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: entry.receipt.action == .endorse ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(entry.receipt.action == .endorse ? CivicTheme.green : CivicTheme.red)
                        Text(entry.receipt.action == .endorse ? "ENDORSED" : "OPPOSED")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(entry.receipt.action == .endorse ? CivicTheme.green : CivicTheme.red)
                    }
                    Text(entry.issue.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.ink)
                        .lineLimit(2)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            ShareLink(item: shareText) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CivicTheme.cyan)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(CivicTheme.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.selection() })
        }
    }

    // MARK: - Helpers

    private func contactRow(label: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(CivicTheme.quietInk)
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
        }
        .padding(8)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    private func sectionLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(tint)
            Rectangle()
                .fill(tint.opacity(0.25))
                .frame(height: 1)
        }
    }

    private func phoneURL(_ phone: String) -> URL? {
        let cleaned = phone.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        return URL(string: "tel://\(cleaned)")
    }

    private var shareText: String {
        var lines: [String] = []
        lines.append("\(official.name) — \(official.role)")
        lines.append(official.displayDistrict)
        if let p = official.party { lines.append("Party: \(p)") }
        if let website = official.websites.first { lines.append(website) }
        lines.append("Via Athen")
        return lines.joined(separator: "\n")
    }
}
