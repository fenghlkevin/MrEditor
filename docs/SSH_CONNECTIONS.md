# Independent SSH connections

Open **File → Open Remote…** (`⌃⌘O`), use the remote button on the empty home screen, or select a server in the **Servers** sidebar. The connection window starts on Saved Connections when profiles exist, and Quick Connect otherwise.

- **Quick Connect**: enter server, port, username, authentication and absolute starting directory. Choose **Connect Without Saving**, or **Save and Connect** and enter a name.
- **Saved Connections**: connect, edit, duplicate or delete a configuration. Editing supports saving without connecting. Duplicating does not copy stored credentials.
- Password, private key (including encrypted keys), SSH Agent and an independently authenticated jump host are supported. The private key picker stores its path; it does not copy the key.
- Credentials are remembered only when explicitly selected. They use the `MrEditor.SSH` macOS Keychain service. Temporary credentials live in the session's memory. Neither connection JSON nor process arguments/environment contain passwords.
- The first connection displays OpenSSH's real host fingerprint. Trust can be limited to the current session. Remembered host identities are kept in the application's own `known_hosts`; changed keys are rejected by OpenSSH.
- **Test Connection** checks authentication, remote command capabilities and access to the starting directory. It does not save the connection configuration.

The **Local** sidebar shows only local documents. The **Servers** sidebar groups open remote files under their server, including temporary connections. Document switching and closing happen in the sidebar; there is no top tab strip. Click a server name to connect and select a file directly; the arrow only expands or collapses its files. Existing open sessions are reused when the connection settings match. The ellipsis opens a dedicated editor for that server only, with Cancel and Save Changes. Saving closes the editor without connecting; cancelling discards form changes. Manage Servers opens the full manager. Authentication is requested only when necessary. Closing a remote file stops its follower; switching documents keeps the session available.

After connecting, select a file from the remote directory browser. Folders appear first; files default to newest modification time. You can enter subdirectories, go to the parent, edit the directory, filter by filename, sort by name and refresh. No file opens automatically. Compressed files and special filesystem entries cannot be opened. Listings show up to 10,000 entries with an explicit limit message.

Saved profiles store the starting directory, not the selected filename. Existing file-path profiles resolve to their parent directory and preselect the old file when it still exists. If that file has rotated away, the parent directory still opens. Successful migration updates an unchanged saved profile. **Choose Another File** in the viewer reuses the connection and replaces the displayed log only after a file is selected.

The SSH client remains `/usr/bin/ssh`, but new connections run with `-F` pointing at an application-generated configuration. They do not read `~/.ssh/config` or use system host trust. Explicit SSH Agent authentication may use the current agent. Legacy core APIs that accept `RemoteFile.Target` retain their existing behavior.

Each session owns a private 0700 temporary directory containing non-secret OpenSSH configuration, session host identities and a Unix socket. An askpass helper sends prompts to the running application over that socket. SSH master sockets are isolated per session and closed on session disposal. No password or passphrase is written to the helper, configuration, environment or arguments.

## Verification

```sh
swift test --filter 'RemoteDirectoryTests|SSHConnectionTests|RemoteFileTests|RemoteLinesTests|RemoteBufferTests'
```

`SSHTransportIntegrationTests` is opt-in (`MREDITOR_SSH_INTEGRATION=1`). It expects isolated local sshd listeners on ports 22479 and 22480, using the current user and `.build/ssh-integration/client_key` (test passphrase `test-passphrase`) as an authorized key, plus `.build/ssh-integration/app.log`. The fixture uses no system SSH configuration. It verifies encrypted-key authentication, session reuse, reading, filtering, following, jump-host forwarding changed-host-key rejection, directory listing, file selection, rotation refresh and legacy path migration.
