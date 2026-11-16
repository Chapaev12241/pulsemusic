import SwiftUI

struct PulseAccountView: View {
    @EnvironmentObject private var store: PulseStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pulseReducedMotion) private var reducedMotion
    @Namespace private var sectionAnimation
    @State private var section = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if store.signedIn {
                    HStack(spacing: 4) {
                        accountTab("Профиль", symbol: "person.crop.circle", value: 0)
                        accountTab("Общение", symbol: "bubble.left.and.bubble.right", value: 1)
                        accountTab("Настройки", symbol: "slider.horizontal.3", value: 2)
                    }.padding(5).background(PulseTheme.panel, in: Capsule()).padding(.horizontal, 20).padding(.vertical, 14)
                    Group {
                        if section == 0 { PulseProfileView(store: store) }
                        else if section == 1 { PulseFriendsView(social: store.social) }
                        else { PulseSettingsView(store: store) }
                    }.transition(.opacity)
                } else { PulseLoginView(store: store) }
            }
            .background(PulseAmbientBackground())
            .animation(reducedMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: section)
            .navigationTitle(store.signedIn ? "Мой Pulse" : "Аккаунт Pulse")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 690, height: 650)
        #endif
    }
    private func accountTab(_ title: String, symbol: String, value: Int) -> some View {
        Button { section = value } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 14))
                Text(title).font(PulseTheme.body(12, weight: section == value ? .semibold : .medium))
            }.frame(maxWidth: .infinity).frame(height: 42)
                .foregroundStyle(section == value ? Color.white : PulseTheme.muted)
                .background {
                    if section == value { Capsule().fill(PulseTheme.raised).matchedGeometryEffect(id: "account-tab", in: sectionAnimation) }
                }
        }.buttonStyle(PulseTactileButton()).accessibilityValue(section == value ? "Выбрано" : "")
    }
}
struct PulseLoginView: View {
    @ObservedObject var store: PulseStore
    @Environment(\.pulseReducedMotion) private var reducedMotion
    @State private var register = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var visiblePassword = false
    @State private var formError: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pulse").font(PulseTheme.heading(52)).foregroundStyle(PulseTheme.gradient)
                    Text(register ? "Твоя музыка\nначинается здесь." : "С возвращением.").font(PulseTheme.display(36)).id(register).transition(.opacity)
                    Text("Вся твоя музыка. На каждом устройстве.").font(PulseTheme.body(14)).foregroundStyle(PulseTheme.muted)
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
                            Button { visiblePassword.toggle() } label: { Image(systemName: visiblePassword ? "eye.slash" : "eye").foregroundStyle(PulseTheme.muted) }.buttonStyle(PulseTactileButton()).accessibilityLabel(visiblePassword ? "Скрыть пароль" : "Показать пароль")
                        }
                    }
                    if let formError { Text(formError).font(PulseTheme.body(14)).foregroundStyle(.red).transition(.opacity) }
                    Button(action: submit) {
                        HStack { if store.authenticating { ProgressView().controlSize(.small) }; Text(store.authenticating ? "Подключаем аккаунт…" : register ? "Создать аккаунт" : "Войти в Pulse") }.frame(maxWidth: .infinity)
                    }.buttonStyle(PulsePrimaryButton()).disabled(!valid || store.authenticating)
                }
                Label("Общая медиатека на iPhone, Mac и Windows", systemImage: "cloud").font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted)
            }.padding(.horizontal, 28).padding(.vertical, 32).frame(maxWidth: 460).frame(maxWidth: .infinity)
        }.background(PulseAmbientBackground())
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
            Text(title).font(PulseTheme.body(12, weight: .medium)).foregroundStyle(PulseTheme.muted)
            content().font(PulseTheme.body(16)).padding(.horizontal, 16).frame(minHeight: 54).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(PulseTheme.line))
        }
    }
}
