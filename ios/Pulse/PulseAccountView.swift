import SwiftUI

struct PulseAccountView: View {
    @EnvironmentObject private var store: PulseStore
    @Environment(\.dismiss) private var dismiss
    @State private var register = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var formError: String?
    var body: some View {
        NavigationStack {
            Form {
                if let user = store.user {
                    Section("Аккаунт") {
                        Text(user.name).font(.headline)
                        Text(user.email).foregroundStyle(.secondary)
                        Text("Тот же аккаунт, что на сайте. Музыка и плейлисты синхронизируются автоматически.").font(.callout)
                    }
                    Section("Воспроизведение") { Toggle("DJ · плавные переходы", isOn: $store.dj) }
                    if !store.uploadStatus.isEmpty { Section("Импорт") { Text(store.uploadStatus) } }
                    Section {
                        Button("Обновить медиатеку") { Task { await store.refresh() } }
                        Button("Выйти из аккаунта", role: .destructive) { Task { await store.logout(); dismiss() } }.disabled(store.uploading)
                    }
                } else {
                    Section {
                        Picker("Аккаунт", selection: $register) { Text("Вход").tag(false); Text("Регистрация").tag(true) }.pickerStyle(.segmented)
                        if register { TextField("Имя", text: $name) }
                        TextField("Email", text: $email)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                            #endif
                        SecureField("Пароль · от 8 символов", text: $password)
                        Text("Используй email и пароль от сайта Pulse.").font(.caption).foregroundStyle(.secondary)
                        if let formError { Text(formError).foregroundStyle(.red) }
                        Button {
                            Task {
                                let success = await store.signIn(email: email, password: password, name: name, register: register)
                                if success { password = ""; dismiss() }
                                else { formError = store.error; store.error = nil }
                            }
                        } label: {
                            HStack { if store.authenticating { ProgressView().controlSize(.small) }; Text(register ? "Создать аккаунт" : "Войти") }
                        }.disabled(store.authenticating || password.count < 8 || !email.contains("@"))
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(store.signedIn ? "Мой Pulse" : "Добро пожаловать")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 480, height: 520)
        #endif
    }
}
