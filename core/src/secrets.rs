//! Widget secrets, kept in the OS credential store.
//!
//! A declared setting of type `secret` never reaches `settings.json`. Everything else a
//! widget declares is a preference the user can read back and edit; a token is not, so
//! it lives in the Keychain on macOS and the Credential Manager on Windows and is only
//! ever handed back to the widget that owns it.
//!
//! Nothing here deletes a secret on its own. Widgets are discovered by scanning a
//! folder, so "the widget is gone" and "the folder was briefly unreadable" look
//! identical from here — and one of those must not cost someone their token. Clearing
//! the field in Settings is the delete.

/// The credential store's service name. One service, one account per secret, so a user
/// auditing their Keychain sees every Notchly credential grouped under one heading.
const SERVICE: &str = "com.mberrish.notchly";

/// The account a secret is filed under.
///
/// Widget ids are author-chosen and keys are manifest-chosen, so the separator has to be
/// one neither can contain — `/` is already refused in ids by the widget protocol, and a
/// key that smuggled one in would otherwise be able to address another widget's secret.
pub fn account(widget_id: &str, key: &str) -> String {
    format!("{}\u{1f}{}", widget_id.replace('\u{1f}', "_"), key.replace('\u{1f}', "_"))
}

fn entry(widget_id: &str, key: &str) -> Result<keyring::Entry, String> {
    keyring::Entry::new(SERVICE, &account(widget_id, key)).map_err(|error| error.to_string())
}

/// The stored secret, or `None` when nothing is filed — which is not an error: a widget
/// asking before the user has pasted anything is the ordinary first run.
pub fn get(widget_id: &str, key: &str) -> Option<String> {
    entry(widget_id, key).ok()?.get_password().ok()
}

/// Whether a secret is filed, without reading it back.
pub fn is_set(widget_id: &str, key: &str) -> bool {
    get(widget_id, key).is_some()
}

/// Stores a secret. An empty value clears it, so the settings window needs no separate
/// delete path — emptying the field is the delete.
pub fn set(widget_id: &str, key: &str, value: &str) -> Result<(), String> {
    let entry = entry(widget_id, key)?;
    if value.is_empty() {
        return match entry.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(error) => Err(error.to_string()),
        };
    }
    entry.set_password(value).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::account;

    #[test]
    fn an_account_names_both_the_widget_and_the_key() {
        assert_eq!(account("com.you.w", "token"), "com.you.w\u{1f}token");
    }

    #[test]
    fn two_widgets_never_share_an_account() {
        assert_ne!(account("a", "token"), account("b", "token"));
    }

    /// Without escaping, a key of "b\u{1f}token" under widget "a" would address the very
    /// same account as key "token" under widget "a\u{1f}b".
    #[test]
    fn a_separator_in_a_key_cannot_forge_another_widgets_account() {
        assert_ne!(account("a", "b\u{1f}token"), account("a\u{1f}b", "token"));
    }
}
