import UIKit

/// Connecting to a music server: address, user and password, tried before they're saved.
final class ServerViewController: CardPage, UITextFieldDelegate {
    private let address = SettingsRow(.field("Address"))
    private let user = SettingsRow(.field("User"))
    private let password = SettingsRow(.field("Password"))
    private let connect = SettingsRow(.action("Connect"))
    private let disconnect = SettingsRow(.action("Disconnect"))
    private let note = UILabel()
    private let disconnectNote = UILabel()
    private let eye = UIButton(type: .system)
    private var checking = false

    init() {
        super.init(title: "Server")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let server = Server.shared
        address.field.placeholder = "music.example.com"
        address.field.keyboardType = .URL
        address.field.text = server.address.replacingOccurrences(of: "https://", with: "")
        user.field.placeholder = "Name"
        user.field.text = server.user
        user.field.textContentType = .username
        password.field.isSecureTextEntry = true
        password.field.textContentType = .password
        password.field.placeholder = server.isConfigured ? "Saved" : "Required"
        password.field.clearButtonMode = .never
        eye.frame = CGRect(x: 0, y: 0, width: 40, height: 44)
        eye.addAction(UIAction { [weak self] _ in self?.togglePassword() }, for: .touchUpInside)
        password.field.rightView = eye
        password.field.rightViewMode = .always
        showEye()
        for (row, key) in [(address, UIReturnKeyType.next), (user, .next), (password, .go)] {
            row.field.returnKeyType = key
            row.field.delegate = self
        }
        note.text = "Navidrome, or any server with the Subsonic API. Flaco downloads the original files."
        section("CONNECTION", [address, user, password, connect], note: note)
        disconnectNote.text = "The music already on this phone stays."
        if server.isConfigured { section("", [disconnect], note: disconnectNote) }

        connect.onAction = { [weak self] in self?.tryConnecting() }
        disconnect.onAction = { [weak self] in self?.confirmDisconnect() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !Server.shared.isConfigured { address.field.becomeFirstResponder() }
    }

    override func apply(_ theme: Theme) {
        super.apply(theme)
        eye.tintColor = theme.secondary
    }

    private func togglePassword() {
        password.field.isSecureTextEntry.toggle()
        showEye()
    }

    private func showEye() {
        let hidden = password.field.isSecureTextEntry
        eye.setImage(Icon.image(hidden ? "eye" : "eye.slash", 15), for: .normal)
        eye.accessibilityLabel = hidden ? "Show password" : "Hide password"
    }

    /// A hidden field empties itself when typing resumes after it was shown, so its edits are applied by hand.
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard textField === password.field, textField.isSecureTextEntry,
              let text = textField.text, let range = Range(range, in: text) else { return true }
        textField.text = text.replacingCharacters(in: range, with: string)
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case address.field: user.field.becomeFirstResponder()
        case user.field: password.field.becomeFirstResponder()
        default: tryConnecting()
        }
        return false
    }

    private func tryConnecting() {
        guard !checking else { return }
        view.endEditing(true)
        let server = Server.shared
        let typed = password.field.text ?? ""
        let connection = Server.Connection(
            address: address.field.text ?? "", user: user.field.text ?? "",
            password: typed.isEmpty ? server.savedPassword ?? "" : typed)
        checking = true
        connect.isEnabled = false
        connect.value = "CHECKING"
        Task { @MainActor in
            defer {
                checking = false
                connect.isEnabled = true
            }
            do {
                let name = try await server.check(connection)
                server.save(connection)
                connect.value = "CONNECTED"
                note.text = "Connected to \(name)."
                view.setNeedsLayout()
                Sync.shared.start()
                try? await Task.sleep(nanoseconds: 700_000_000)
                navigationController?.popViewController(animated: true)
            } catch {
                connect.value = ""
                note.text = error.localizedDescription
                view.setNeedsLayout()
            }
        }
    }

    private func confirmDisconnect() {
        let sheet = UIAlertController(title: "Disconnect from \(Server.shared.host)?", message: disconnectNote.text, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Disconnect", style: .destructive) { [weak self] _ in
            Server.shared.disconnect()
            self?.navigationController?.popViewController(animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }
}
