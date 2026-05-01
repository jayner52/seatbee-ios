import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Environment(AppState.self) private var appState
    @State private var showEmailInput = false
    @State private var email = ""
    @State private var magicLinkSent = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            Image("SeatbeeLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)

            Spacer().frame(height: 32)

            // Headline
            VStack(spacing: 8) {
                Text("Your wedding,")
                    .font(SBFont.displayLarge)
                    .foregroundStyle(Color.sbCharcoal)

                Text("perfectly seated")
                    .font(SBFont.fraunces(28, weight: .medium))
                    .foregroundStyle(Color.sbGoldDk)
                    .italic()
            }

            Spacer().frame(height: 12)

            Text("AI-powered seating that handles the drama")
                .font(SBFont.meta)
                .foregroundStyle(Color.sbWarm)

            Spacer().frame(height: 48)

            // Auth buttons
            VStack(spacing: 14) {
                // Apple Sign In
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                            Task {
                                await appState.auth.signInWithApple(credential: credential)
                            }
                        }
                    case .failure:
                        break
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))

                // Google Sign In
                Button {
                    Task { await appState.auth.signInWithGoogle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "g.circle.fill")
                            .font(.system(size: 20))
                        Text("Continue with Google")
                            .font(SBFont.bodySemibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.sbIvory2)
                    .foregroundStyle(Color.sbCharcoal)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                    .overlay(
                        RoundedRectangle(cornerRadius: SBRadius.button)
                            .strokeBorder(Color.sbLine2, lineWidth: 1)
                    )
                }

                // Email Magic Link
                Button {
                    withAnimation(.seatbee) {
                        showEmailInput.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope")
                            .font(.system(size: 18))
                        Text("Continue with Email")
                            .font(SBFont.bodySemibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.sbIvory2)
                    .foregroundStyle(Color.sbCharcoal)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                    .overlay(
                        RoundedRectangle(cornerRadius: SBRadius.button)
                            .strokeBorder(Color.sbLine2, lineWidth: 1)
                    )
                }

                // Email input (revealed)
                if showEmailInput {
                    VStack(spacing: 12) {
                        TextField("your@email.com", text: $email)
                            .font(SBFont.body)
                            .padding(14)
                            .background(Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                            .overlay(
                                RoundedRectangle(cornerRadius: SBRadius.button)
                                    .strokeBorder(Color.sbLine2, lineWidth: 1)
                            )
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        SBButton(title: magicLinkSent ? "Link sent!" : "Send magic link", icon: "paperplane", variant: .gold, fullWidth: true) {
                            Task {
                                magicLinkSent = await appState.auth.sendMagicLink(email: email)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, SBSpacing.screenMargin)

            Spacer().frame(height: 24)

            // Footer
            Text("No passwords. We'll email you a magic link.")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)

            Spacer()

            // Error display
            if let error = appState.auth.error {
                Text(error)
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbError)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.sbIvory)
    }
}

#Preview {
    AuthView()
        .environment(AppState())
}
