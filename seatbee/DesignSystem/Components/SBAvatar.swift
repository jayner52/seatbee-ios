import SwiftUI

struct SBAvatar: View {
    let name: String
    var size: CGFloat = 36
    var photoURL: URL? = nil

    var body: some View {
        if let url = photoURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    initialsView
                }
            }
            .frame(width: size, height: size)
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(avatarColor)

            Text(initials)
                .font(SBFont.fraunces(size * 0.4, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var avatarColor: Color {
        let colors: [Color] = [
            .sbGold, .sbSage, .sbBlush,
            Color(.sRGB, red: 139/255, green: 157/255, blue: 195/255, opacity: 1), // steel blue
            Color(.sRGB, red: 221/255, green: 160/255, blue: 221/255, opacity: 1), // plum
            Color(.sRGB, red: 135/255, green: 206/255, blue: 235/255, opacity: 1), // sky
            Color(.sRGB, red: 152/255, green: 216/255, blue: 200/255, opacity: 1), // mint
        ]
        let hash = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors[hash % colors.count]
    }
}

#Preview {
    HStack(spacing: 12) {
        SBAvatar(name: "Sarah Chen")
        SBAvatar(name: "Jon Park")
        SBAvatar(name: "Aunt Linda")
        SBAvatar(name: "M", size: 28)
    }
    .padding()
    .background(Color.sbIvory)
}
