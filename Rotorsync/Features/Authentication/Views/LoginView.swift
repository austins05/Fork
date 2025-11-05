import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("RotorSync Login")
                .font(.largeTitle)
                .fontWeight(.bold)

            TextField("Email", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .keyboardType(.emailAddress)
                .padding(.horizontal)

            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            Button(action: handleLogin) {
                Text("Login")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .disabled(isLoading)

            if isLoading {
                ProgressView()
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }

            Spacer()
        }
        .padding(.top, 50)
        .onAppear {
            // Check for valid session
            if isSessionValid() {
                DispatchQueue.main.async {
                    appState.isLoggedIn = true
                }
            }
        }
    }

    private func handleLogin() {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter email and password."
            return
        }

        isLoading = true
        errorMessage = nil

        APIService.shared.login(email: email, password: password) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let (user, token)):
                    // Save token to Keychain
                    KeychainService.saveToken(token)

                    // Save user data to UserDefaults
                    if let userData = try? JSONEncoder().encode(user) {
                        UserDefaults.standard.set(userData, forKey: "userData")
                    }

                    // Save session expiration (30 days)
                    let expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
                    UserDefaults.standard.set(expirationDate, forKey: "sessionExpiration")

                    // ✅ Trigger app-wide login
                    appState.isLoggedIn = true

                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func isSessionValid() -> Bool {
        guard let expirationDate = UserDefaults.standard.object(forKey: "sessionExpiration") as? Date,
              let token = KeychainService.getToken(),
              !token.isEmpty else {
            return false
        }
        return Date() < expirationDate
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(AppState())
    }
}
