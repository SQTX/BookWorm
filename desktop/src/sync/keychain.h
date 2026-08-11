#pragma once

#include <QString>

/**
 * Secret storage backed by the macOS Keychain.
 *
 * Tokens must not go in QSettings. On macOS that is a plist in the user's
 * Library, world-readable within the account and trivially recovered from a
 * backup or a synced Preferences folder. A refresh token lives for thirty days
 * and grants full access to the library, so it belongs where the operating
 * system already guards credentials.
 *
 * The functions are free rather than a class: there is no state to hold, and
 * the Keychain itself is the storage.
 */
namespace BookWorm::Keychain {

/**
 * Store or replace a secret.
 *
 * @param account identifies the entry within the BookWorm service, e.g. the
 *   email the token belongs to, so two accounts do not overwrite each other.
 */
bool store(const QString &account, const QString &key, const QString &secret);

/** @returns the secret, or an empty string when there is none. */
QString retrieve(const QString &account, const QString &key);

/** Removing an entry that does not exist is success, not failure. */
bool remove(const QString &account, const QString &key);

} // namespace BookWorm::Keychain
