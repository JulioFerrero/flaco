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
        password.field.isSecureTextEntry = true
        password.field.placeholder = server.isConfigured ? "Saved" : "Required"
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
