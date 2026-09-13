import UIKit

class SettingsViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case emulation
        case saveStates
        case about
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(dismiss(_:)))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    @objc private func dismiss(_ sender: Any) {
        dismiss(animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .emulation: return "Emulation"
        case .saveStates: return "Save States"
        case .about: return "About"
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .emulation: return 2
        case .saveStates: return 4  // 4 save slots
        case .about: return 1
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryView = nil

        switch Section(rawValue: indexPath.section)! {
        case .emulation:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Reset"
            } else {
                cell.textLabel?.text = "Audio"
                let toggle = UISwitch()
                toggle.isOn = UserDefaults.standard.bool(forKey: "audioEnabled")
                toggle.addTarget(self, action: #selector(audioToggled(_:)), for: .valueChanged)
                cell.accessoryView = toggle
            }
        case .saveStates:
            let slot = indexPath.row + 1
            let exists = SaveStateManager.shared.stateExists(slot: slot)
            cell.textLabel?.text = "Slot \(slot)\(exists ? " (saved)" : "")"
        case .about:
            cell.textLabel?.text = "DSEmu — melonDS-based DS Emulator"
            cell.selectionStyle = .none
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section)! {
        case .emulation:
            if indexPath.row == 0 {
                EmulatorCore.shared.reset()
                dismiss(animated: true)
            }
        case .saveStates:
            let slot = indexPath.row + 1
            let alert = UIAlertController(title: "Slot \(slot)", message: nil, preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
                _ = SaveStateManager.shared.saveState(slot: slot)
                tableView.reloadRows(at: [indexPath], with: .automatic)
            })
            if SaveStateManager.shared.stateExists(slot: slot) {
                alert.addAction(UIAlertAction(title: "Load", style: .default) { _ in
                    _ = SaveStateManager.shared.loadState(slot: slot)
                    self.dismiss(animated: true)
                })
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        case .about:
            break
        }
    }

    @objc private func audioToggled(_ sender: UISwitch) {
        UserDefaults.standard.set(sender.isOn, forKey: "audioEnabled")
        if sender.isOn {
            AudioManager.shared.start()
        } else {
            AudioManager.shared.stop()
        }
    }
}
