# MailReveal

MailReveal intercepts `message:` links and reveals the referenced email in Apple Mail’s existing three-pane viewer instead of leaving it in a separate message window.

The app is a menu-less native macOS utility. It asks Mail to resolve the RFC Message-ID using Mail’s own index, reads the resolved account, mailbox and message header, switches the existing viewer to that mailbox, selects the matching conversation and exact message, and closes the transient resolver window.

## Requirements

- macOS 13 or later
- Apple Mail
- Swift 6 or later from Xcode or the Command Line Tools

## Build

Run the tests and build the app bundle:

```shell
./Scripts/swiftpm.sh test
./Scripts/build-app.sh
```

The built app is written to `dist/MailReveal.app` and receives an ad-hoc signature suitable for local use.

## Test without changing the default handler

Open a known Mail Message-ID explicitly with the built app:

```shell
open -a "$PWD/dist/MailReveal.app" 'message://%3Cmessage-id%40example.com%3E'
```

macOS asks for Automation permission the first time MailReveal runs. Automation lets it change the existing viewer’s mailbox. Accessibility is required to read the transient resolver window and select the exact conversation and message in Mail’s existing viewer. Enable the built app under **System Settings → Privacy & Security → Accessibility** before testing. MailReveal does not open System Settings automatically, and Full Disk Access is not required.

## Installation

The signed app is installed at `~/Applications/MailReveal.app` and registered as the system default handler for `message:` links. A normal link can be tested without naming the app explicitly:

```shell
open 'message://%3Cmessage-id%40example.com%3E'
```

Rebuilding `dist/MailReveal.app` does not update the installed copy automatically.

## Current scope

- Success is silent: Mail comes forward with the message selected.
- Invalid links and lookup failures produce an alert.
- Incoming links are validated and normalised before being sent to Mail.
- MailReveal does not access Mail’s on-disk store or persist message data. It reads the target account, mailbox and header plus visible message-list labels in memory to select and verify the exact message.
