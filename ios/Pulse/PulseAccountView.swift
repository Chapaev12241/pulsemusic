import SwiftUI

struct PulseAccountView: View {
    @EnvironmentObject private var store: PulseStore
    @Environment(\.dismiss) private var dismiss
    @State private var section = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if store.signedIn {
                    Picker("Раздел", selection: $section) {
                        Text("Профиль").tag(0); Text("Друзья и чаты").tag(1); Text("Настройки").tag(2)
                    }.pickerStyle(.segmented).padding(18)
                    Group {
                        if section == 0 { PulseProfileView(store: store) }
                        else if section == 1 { PulseFriendsView(social: store.social) }
                        else { PulseSettingsView(store: store) }
                    }
                } else { PulseLoginView(store: store) }
            }
            .background(PulseTheme.background)
            .navigationTitle(store.signedIn ? "Мой Pulse" : "Аккаунт Pulse")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 690, height: 650)
        #endif
    }
}
struct PulseLoginView: View {
    @ObservedObject var store: PulseStore
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var register = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var visiblePassword = false
    @State private var formError: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pulse").font(PulseTheme.heading(52)).foregroundStyle(PulseTheme.gradient)
                    Text(register ? "Твоя музыка\nначинается здесь." : "С возвращением\nна свою волну.").font(PulseTheme.heading(35)).id(register)
                    Text("Один аккаунт для сайта, iPhone и Mac.").font(.callout).foregroundStyle(PulseTheme.muted)
                }
                Picker("Аккаунт", selection: $register) { Text("Войти").tag(false); Text("Регистрация").tag(true) }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 16) {
                    if register { labeled("Имя") { TextField("Как тебя называть?", text: $name).textFieldStyle(.plain) }.transition(.opacity.combined(with: .move(edge: .top))) }
                    labeled("Email") {
                        TextField("name@example.com", text: $email).textFieldStyle(.plain)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled().textContentType(.emailAddress)
                            #endif
                    }
                    labeled("Пароль") {
                        HStack {
                            Group {
                                if visiblePassword { TextField("От 8 символов", text: $password).textFieldStyle(.plain) }
                                else { SecureField("От 8 символов", text: $password).textFieldStyle(.plain) }
                            }
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(register ? .newPassword : .password)
                            #endif
                            .onSubmit(submit)
                            Button { visiblePassword.toggle() } label: { Image(systemName: visiblePassword ? "eye.slash" : "eye").foregroundStyle(PulseTheme.muted) }.buttonStyle(.plain).accessibilityLabel(visiblePassword ? "Скрыть пароль" : "Показать пароль")
                        }
                    }
                    if let formError { Text(formError).font(.callout).foregroundStyle(.red).transition(.opacity) }
                    Button(action: submit) {
                        HStack { if store.authenticating { ProgressView().controlSize(.small) }; Text(store.authenticating ? "Подключаем аккаунт…" : register ? "Создать аккаунт" : "Войти в Pulse") }.frame(maxWidth: .infinity)
                    }.buttonStyle(PulsePrimaryButton()).disabled(!valid || store.authenticating)
                }
                Label("Музыка, избранное, друзья и переписка останутся с тобой.", systemImage: "cloud").font(.caption).foregroundStyle(PulseTheme.muted)
            }.padding(26).frame(maxWidth: 460).frame(maxWidth: .infinity)
        }.background(PulseTheme.background)
        .animation(reducedMotion ? nil : .easeInOut(duration: 0.2), value: register)
        .onChange(of: register) { _, _ in formError = nil }
    }
    private var valid: Bool { email.contains("@") && email.count <= 254 && password.utf16.count >= 8 && password.utf16.count <= 200 && (!register || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    private func submit() {
        guard valid, !store.authenticating else { return }
        formError = nil
        Task {
            let success = await store.signIn(email: email, password: password, name: name, register: register)
            if success { password = ""; await store.social.refresh() }
            else { formError = store.error; store.error = nil }
        }
    }
    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(PulseTheme.muted)
            content().font(.system(size: 14)).padding(14).background(PulseTheme.raised, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(PulseTheme.line))
        }
    }
}
